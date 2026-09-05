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

TAG=""; NO_BUILD=0; IS_DRAFT=0; GH_FLAGS=()
for a in "$@"; do
  case "$a" in
    --no-build) NO_BUILD=1 ;;
    --draft)    IS_DRAFT=1; GH_FLAGS+=(--draft) ;;
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

# Self-check the SOURCE-consumer path: `ae add <repo>@<tag>` must land the tree
# AT THE BUILT COMMIT. Two things make a naive check lie:
#   1. A DRAFT release does NOT push its git tag (GitHub holds it until publish),
#      so `ae add @<tag>` cannot resolve yet — skip with a clear note rather than
#      fail a draft for a tag that intentionally isn't public.
#   2. `ae add` clones then `git checkout <tag> || true` and can FALL BACK to a
#      cached/default checkout on a miss, exiting 0. So checking exit status is
#      not enough — verify the resolved commit equals the one we built.
# Hard gate for a real (non-draft) release; a miss means FFI consumers can use
# it but source consumers (e.g. datastar-aether) cannot pin it.
REPO_SLUG="github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo aether-lang-dev/selaenium)"
if [ "$IS_DRAFT" = "1" ]; then
  printf 'publish: draft — tag %s is NOT pushed until you publish the draft, so the\n' "$TAG"
  printf 'publish:         ae-add source path cannot be verified yet. After publishing:\n'
  printf 'publish:           ae add %s@%s   (should check out %s)\n' "$REPO_SLUG" "$TAG" "${COMMIT:0:9}"
elif have ae; then
  printf 'publish: verifying source path — ae add %s@%s must land %s …\n' "$REPO_SLUG" "$TAG" "${COMMIT:0:9}"
  probe="$(mktemp -d)"; trap 'rm -rf "$probe"' EXIT
  # Start from a clean package cache for THIS repo so a stale prior clone cannot
  # mask a miss (the exact false pass this gate is meant to catch).
  rm -rf "${AETHER_HOME:-$HOME/.aether}/packages/$REPO_SLUG"
  ( cd "$probe" && ae init _probe >/dev/null 2>&1 && cd _probe 2>/dev/null || cd "$probe"
    ae add "$REPO_SLUG@$TAG" ) >/dev/null 2>&1 || true
  pkg="${AETHER_HOME:-$HOME/.aether}/packages/$REPO_SLUG"
  got="$(git -C "$pkg" rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$got" != "$COMMIT" ]; then
    die "SOURCE-PATH GATE FAILED — 'ae add $REPO_SLUG@$TAG' landed ${got:0:9}, not the
       built commit ${COMMIT:0:9}. The binaries are published but a source consumer
       (e.g. datastar-aether) would get different code. Check: git ls-remote --tags origin '$TAG'"
  fi
  printf 'publish: OK — ae add %s@%s checks out %s (source consumers can pin this release)\n' "$REPO_SLUG" "$TAG" "${COMMIT:0:9}"

  # Manifest-resolution gate: with an aether.toml [package] modules declaration,
  # a consumer imports with NO --lib. Prove that against the JUST-TAGGED package.
  # Needs ae >= 0.637.0 ([dependencies] onto the search path); older ae cannot
  # test it, so skip-with-note rather than fail. `[patch]` points at the package
  # we already resolved above, so this checks the tagged tree's own aether.toml.
  ae_ver="$(ae --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  ae_ge_637="$(printf '%s\n0.637.0\n' "$ae_ver" | sort -V | tail -1)"
  if [ ! -f "$pkg/aether.toml" ]; then
    printf 'publish: note — %s has no aether.toml; ae-add consumers still need --lib (no module export)\n' "$TAG"
  elif [ "$ae_ge_637" = "$ae_ver" ] && [ -n "$ae_ver" ]; then
    mp="$(mktemp -d)"
    ( cd "$mp" && ae init _mres >/dev/null 2>&1 && cd _mres 2>/dev/null || cd "$mp"
      # declare the dep and patch it to the resolved package, then import with no --lib
      cat > aether.toml <<TOML
[package]
name = "_mres"
[dependencies]
"${REPO_SLUG#github.com/}" = "${TAG#v}"
[patch]
"${REPO_SLUG#github.com/}" = "$pkg"
[[bin]]
name = "_mres"
path = "main.ae"
TOML
      printf 'import webdriver\nmain() { }\n' > main.ae
      ae build main.ae -o _mres.out ) >/dev/null 2>&1 \
      && printf 'publish: OK — import webdriver resolves from %s with NO --lib (aether.toml modules work)\n' "$TAG" \
      || { rm -rf "$mp"; die "MANIFEST GATE FAILED — $TAG ships an aether.toml but 'import webdriver'
       does NOT resolve from it without --lib. Check its [package] modules line against
       the tree; see docs/module-system-design.md in the aether repo."; }
    rm -rf "$mp"
  else
    printf 'publish: note — ae %s < 0.637.0; cannot verify aether.toml module resolution (needs [dependencies] support)\n' "${ae_ver:-unknown}"
  fi
else
  printf 'publish: WARNING — ae not on PATH; could NOT verify the ae-add source path for %s\n' "$TAG"
fi

printf 'publish: next — attest each artifact on its target hardware by SHA256 (release/README.md).\n'
