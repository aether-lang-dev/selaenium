#!/usr/bin/env bash
# Ensure the pinned Aether toolchain (ae + aeb) is installed and on PATH.
#
# Idempotent: if ae and aeb are already present it does nothing but print what
# it found — so it is cheap to call at the top of every CI lane. Pins come from
# ci/versions.env (override via the AETHER_REF / AEB_REF env vars).
#
# Prerequisites: curl, tar, GNU make, a C compiler (Aether compiles to C, so no
# chicken-and-egg). aeb ships prebuilt release BINARIES (v0.286+): when one
# exists for this platform+tag AND `unzip` is present we install it (fast, no
# aeb compile — bin/aeb is a script and its Makefile install needs no cc),
# otherwise we fall back to the public no-clone curl-pipe SOURCE build (aether
# get.sh, aeb install.sh). Both are pinnable.
#
# Usage:  ci/toolchain.sh                 # install if missing, print versions
#         FORCE=1 ci/toolchain.sh         # reinstall even if present
#         NO_BINARY=1 ci/toolchain.sh     # skip the binary path, always source-build
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/versions.env"

PREFIX="${PREFIX:-$HOME/.local}"
export PATH="$PREFIX/bin:$HOME/.aether/bin:$PATH"

say() { printf 'ci/toolchain: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

for tool in curl tar make cc; do
  have "$tool" || { say "MISSING prerequisite: $tool (need curl, tar, GNU make, a C compiler)"; exit 1; }
done

# uname -> the {os}-{arch} slug the release assets are named for
# (aeb-{os}-{arch}.zip: os in linux/macos/freebsd/windows, arch in amd64/arm64,
# with -musl variants on linux). Empty for an unrecognised platform.
platform_slug() {
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) return 0 ;;
  esac
  case "$(uname -s)" in
    Linux)
      # musl vs glibc: ldd's banner names the libc. Prefer the matching build.
      if ldd --version 2>&1 | grep -qi musl; then printf 'linux-%s-musl' "$arch"
      else printf 'linux-%s' "$arch"; fi ;;
    Darwin)  printf 'macos-%s' "$arch" ;;
    FreeBSD) printf 'freebsd-%s' "$arch" ;;
    *) return 0 ;;
  esac
}

# Install a PREBUILT aeb from the GitHub release for $AEB_REF. The platform asset
# (aeb-{slug}.zip) is a full install tree — bin/aeb (a bash script, so no C
# compiler needed) + share/aeb/ (the SDK runtime) — plus a Makefile whose
# `install` target stages it into $PREFIX and writes an AEB_HOME wrapper (this is
# what stamps it; a bare bin/aeb warns it is an "un-installed tree"). Returns 0
# on success (aeb runnable at $PREFIX/bin), non-zero to fall back to source.
# Fully defensive: missing asset / no unzip / bad tree / non-runnable -> non-zero.
install_aeb_binary() {
  [ "${NO_BINARY:-0}" = "1" ] && return 1
  case "$AEB_REF" in v*) ;; *) return 1 ;; esac   # binaries are per-tag only
  have unzip || { say "no unzip; using source build for aeb"; return 1; }
  slug=$(platform_slug)
  [ -n "$slug" ] || return 1
  url="https://github.com/aether-lang-dev/aeb/releases/download/${AEB_REF}/aeb-${slug}.zip"
  tmp=$(mktemp -d)
  if ! curl -fsSL "$url" -o "$tmp/aeb.zip" 2>/dev/null; then rm -rf "$tmp"; return 1; fi
  # TODO(release-eng ask): no per-asset .sha256 published for the platform zips
  # yet, so the download is unverified. Verify here once checksums ship.
  if ! unzip -q "$tmp/aeb.zip" -d "$tmp" 2>/dev/null; then rm -rf "$tmp"; return 1; fi
  tree=$(find "$tmp" -maxdepth 1 -type d -name "aeb-${slug}" | head -1)
  [ -n "$tree" ] && [ -f "$tree/share/aeb/Makefile" ] || { rm -rf "$tmp"; return 1; }
  # Install via the bundled Makefile (stages files + writes the wrapper; the
  # binary is prebuilt, so this needs no compiler).
  if ! make -C "$tree/share/aeb" install PREFIX="$PREFIX" >/dev/null 2>&1; then
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  if "$PREFIX/bin/aeb" --version >/dev/null 2>&1; then
    say "installed aeb ${AEB_REF} from the prebuilt release binary (aeb-${slug}.zip)"
    return 0
  fi
  return 1
}

# ---- ae (the Aether compiler) --------------------------------------------
if [ "${FORCE:-0}" = "1" ] || ! have ae; then
  say "installing Aether ${AETHER_REF} …"
  AETHER_REF="$AETHER_REF" PREFIX="$PREFIX" \
    curl -sSL "https://raw.githubusercontent.com/aether-lang-dev/aether/main/get.sh" | sh
else
  say "ae present: $(ae --version 2>&1 | head -1) (skipping; FORCE=1 to reinstall)"
fi

# ---- aeb (the build runner; written in Aether, so needs ae first) --------
if [ "${FORCE:-0}" = "1" ] || ! have aeb; then
  # Prefer a release binary (fast, no compile); fall back to the source build.
  if install_aeb_binary; then
    :
  else
    say "installing aeb ${AEB_REF} from source …"
    AEB_REF="$AEB_REF" PREFIX="$PREFIX" AETHER="$(command -v ae)" \
      curl -sSL "https://raw.githubusercontent.com/aether-lang-dev/aeb/main/install.sh" | sh
  fi
else
  say "aeb present: $(aeb --version 2>&1 | head -1) (skipping; FORCE=1 to reinstall)"
fi

say "ae  -> $(command -v ae)   $(ae  --version 2>&1 | head -1)"
say "aeb -> $(command -v aeb)  $(aeb --version 2>&1 | head -1)"
