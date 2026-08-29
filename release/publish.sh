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

# Build the matrix for this tag unless told to reuse dist.
if [ "$NO_BUILD" = "0" ]; then
  printf 'publish: building artifacts for %s …\n' "$TAG"
  RELEASE_TAG="$TAG" "$HERE/build.sh" || die "build failed — fix it, or --no-build to publish existing dist"
fi

# Collect what to upload: every artifact, its sidecar, and the manifest.
# nullglob makes an unmatched glob expand to nothing (not a literal), so an empty
# dist yields an empty list rather than bogus filenames.
shopt -s nullglob
bins=( "$DIST"/*.so "$DIST"/*.dylib "$DIST"/*.dll )
sums=( "$DIST"/*.sha256 )
manifest=( "$DIST"/SHA256SUMS )   # nullglob: empty if it doesn't exist
shopt -u nullglob
[ "${#bins[@]}" -gt 0 ] || die "no engine artifacts in release/dist — run release/build.sh (or drop --no-build)"
assets=( "${bins[@]}" "${sums[@]}" "${manifest[@]}" )
nbin="${#bins[@]}"

notes="Cross-built \`libselenium_core\` engine, ${nbin} platform artifact(s), each with a \`.sha256\` (and a combined \`SHA256SUMS\`).

Built from a single Linux host via \`ae build --target\` — see \`release/README.md\` for the build-here / attest-on-hardware model and the per-artifact coverage caveats (local \`http://\` works everywhere; BiDi \`ws://\`/\`wss://\` is covered; remote HTTPS-Grid needs the Tier-2 TLS helper)."

printf 'publish: creating release %s with %d asset(s)%s …\n' \
  "$TAG" "${#assets[@]}" "$([ "${#GH_FLAGS[@]}" -gt 0 ] && echo " (${GH_FLAGS[*]})")"

gh release create "$TAG" "${GH_FLAGS[@]}" \
  --title "$TAG" --notes "$notes" \
  "${assets[@]}" \
  || die "gh release create failed"

printf 'publish: done — %s\n' "$(gh release view "$TAG" --json url -q .url 2>/dev/null || echo "$TAG created")"
printf 'publish: next — attest each artifact on its target hardware by SHA256 (release/README.md).\n'
