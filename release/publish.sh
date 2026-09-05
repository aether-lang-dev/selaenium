#!/usr/bin/env bash
# Cut a GitHub Release for a tag and attach the cross-built engine artifacts +
# their checksums. Manual, CLI-only — no GitHub Actions, no repo settings, no
# secrets: it uses your existing `gh` auth to create the release and upload
# assets. (Registry publishing — PyPI/npm/Maven/… — is deliberately NOT here.)
#
# Usage:
#   release/publish.sh v1.2.3               # build (if needed) + create the release
#   release/publish.sh v1.2.3 --draft       # create as a draft to review first
#   release/publish.sh v1.2.3 --no-build    # use whatever is already in release/dist
#
# Steps: ensure artifacts for <tag> exist (build them unless --no-build), then
# `gh release create <tag>` with every artifact, its .sha256, and SHA256SUMS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DIST="$ROOT/release/dist"
cd "$ROOT"

die() { printf 'publish: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

TAG=""; NO_BUILD=0; GH_FLAGS=()
for a in "$@"; do
  case "$a" in
    --no-build) NO_BUILD=1 ;;
    --draft)    GH_FLAGS+=(--draft) ;;
    --prerelease) GH_FLAGS+=(--prerelease) ;;
    -*)         die "unknown flag: $a" ;;
    *)          [ -z "$TAG" ] && TAG="$a" || die "unexpected arg: $a" ;;
  esac
done
[ -n "$TAG" ] || die "usage: release/publish.sh <tag> [--draft] [--prerelease] [--no-build]"
case "$TAG" in v*) ;; *) die "tag should look like vX.Y.Z (got '$TAG')" ;; esac

have gh || die "gh (GitHub CLI) not found — install it, or upload release/dist/* by hand"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login'"

# One release serves BOTH consumers of this repo:
#   - source consumers (`ae add <repo>@<tag>` = git clone + `git checkout <tag>`)
#     get the tree AT THE TAGGED COMMIT;
#   - FFI consumers get the prebuilt libselenium_core.* assets built HERE.
# So the tag and the binaries must be the SAME code. Pin the tag to the exact
# commit we build, and refuse to build from a dirty tracked tree (untracked
# scratch is fine) — otherwise the two consumers could get different sources.
COMMIT="$(git rev-parse HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "working tree has uncommitted TRACKED changes — commit or stash them so the
       tag ($TAG @ ${COMMIT:0:9}) and the built binaries are the same code
       (untracked files are fine; use 'git status' to see what's dirty)"
fi

# Build the matrix for this tag unless told to reuse dist.
if [ "$NO_BUILD" = "0" ]; then
  printf 'publish: building artifacts for %s …\n' "$TAG"
  RELEASE_TAG="$TAG" "$HERE/build.sh" || die "build failed — fix it, or --no-build to publish existing dist"
fi

# Collect what to upload: every artifact, its sidecar, and the manifest.
# nullglob makes an unmatched glob expand to nothing (not a literal), so an empty
# dist yields an empty list rather than bogus filenames.
shopt -s nullglob
bins=( "$DIST"/*.so "$DIST"/*.dylib "$DIST"/*.dll "$DIST"/*.dll.lib )
sums=( "$DIST"/*.sha256 )
manifest=( "$DIST"/SHA256SUMS )   # nullglob: empty if it doesn't exist
shopt -u nullglob
[ "${#bins[@]}" -gt 0 ] || die "no engine artifacts in release/dist — run release/build.sh (or drop --no-build)"
assets=( "${bins[@]}" "${sums[@]}" "${manifest[@]}" )
# Count only the loadable libraries (not the Windows .dll.lib import stubs) for
# the "N platform artifacts" note.
nbin=0; for f in "${bins[@]}"; do case "$f" in *.dll.lib) ;; *) nbin=$((nbin+1)) ;; esac; done

notes="Cross-built \`libselenium_core\` engine, ${nbin} platform artifact(s), each with a \`.sha256\` (and a combined \`SHA256SUMS\`).

Built from a single Linux host via \`ae build --target\` — see \`release/README.md\` for the build-here / attest-on-hardware model and the per-artifact coverage caveats (local \`http://\` works everywhere; BiDi \`ws://\`/\`wss://\` is covered; remote HTTPS-Grid needs the Tier-2 TLS helper)."

printf 'publish: creating release %s (tag -> %s) with %d asset(s)%s …\n' \
  "$TAG" "${COMMIT:0:9}" "${#assets[@]}" "$([ "${#GH_FLAGS[@]}" -gt 0 ] && echo " (${GH_FLAGS[*]})")"

# --target "$COMMIT": create the tag at the exact commit we built, NOT at the
# remote default-branch HEAD (gh's default) — that could be a different commit
# than the one whose tree produced these binaries.
gh release create "$TAG" "${GH_FLAGS[@]}" \
  --target "$COMMIT" \
  --title "$TAG" --notes "$notes" \
  "${assets[@]}" \
  || die "gh release create failed"

printf 'publish: done — %s\n' "$(gh release view "$TAG" --json url -q .url 2>/dev/null || echo "$TAG created")"

# Self-check the SOURCE-consumer path: `ae add <repo>@<tag>` must resolve, i.e.
# the tag is pushed and checks out. A draft release still creates the tag, so
# this works for --draft too. Hard gate — a release that FFI consumers can use
# but source consumers (e.g. datastar-aether via `ae add`) cannot is not "done".
# Skip only if `ae` is absent (can't check) — say so loudly rather than pass.
REPO_SLUG="github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo aether-lang-dev/selaenium)"
if have ae; then
  printf 'publish: verifying source path — ae add %s@%s …\n' "$REPO_SLUG" "$TAG"
  probe="$(mktemp -d)"; trap 'rm -rf "$probe"' EXIT
  ( cd "$probe" && ae init _probe >/dev/null 2>&1 && cd _probe 2>/dev/null || cd "$probe"
    ae add "$REPO_SLUG@$TAG" ) >/dev/null 2>&1 \
    && printf 'publish: OK — ae add resolves %s@%s (source consumers can pin this release)\n' "$REPO_SLUG" "$TAG" \
    || die "SOURCE-PATH GATE FAILED — 'ae add $REPO_SLUG@$TAG' did not resolve. The
       binaries are published but a source consumer (e.g. datastar-aether) cannot
       pin this tag. Check the tag pushed: git ls-remote --tags origin '$TAG'"
else
  printf 'publish: WARNING — ae not on PATH; could NOT verify the ae-add source path for %s\n' "$TAG"
fi

printf 'publish: next — attest each artifact on its target hardware by SHA256 (release/README.md).\n'
