#!/usr/bin/env bash
# Ensure the pinned Aether toolchain (ae + aeb) is installed and on PATH.
#
# Idempotent: if ae and aeb are already present it does nothing but print what
# it found — so it is cheap to call at the top of every CI lane. Pins come from
# ci/versions.env (override via the AETHER_REF / AEB_REF env vars).
#
# Aether compiles to C, so the only host prerequisites are curl, tar, GNU make,
# and a C compiler — no chicken-and-egg. aeb ships release BINARIES (v0.286+);
# when one exists for this platform+tag we install it (fast, no compile),
# otherwise we fall back to the public no-clone curl-pipe SOURCE build
# (aether get.sh, aeb install.sh). Both are pinnable.
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

# uname -> the {os}-{arch} slug a release asset is named for.
platform_slug() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
  esac
  printf '%s-%s' "$os" "$arch"
}

# Try to install a prebuilt aeb from the GitHub release for $AEB_REF. Returns 0
# on success (aeb now on PATH at $PREFIX/bin), non-zero to signal "fall back to
# source build". Defensive: any missing asset / bad download / non-runnable
# binary just returns non-zero — never aborts the script.
install_aeb_binary() {
  [ "${NO_BINARY:-0}" = "1" ] && return 1
  case "$AEB_REF" in v*) ;; *) return 1 ;; esac   # binaries are per-tag only
  slug=$(platform_slug)
  base="https://github.com/aether-lang-dev/aeb/releases/download/${AEB_REF}"
  tmp=$(mktemp -d)
  # Try the conventional asset names in order; stop at the first that downloads.
  for name in "aeb-${AEB_REF}-${slug}.tar.gz" "aeb-${slug}.tar.gz" \
              "aeb-${AEB_REF}-${slug}" "aeb-${slug}"; do
    url="${base}/${name}"
    if curl -fsSL "$url" -o "$tmp/asset" 2>/dev/null; then
      mkdir -p "$PREFIX/bin"
      case "$name" in
        *.tar.gz) tar -xzf "$tmp/asset" -C "$tmp" 2>/dev/null || { rm -rf "$tmp"; return 1; }
                  bin=$(find "$tmp" -type f -name aeb | head -1)
                  [ -n "$bin" ] || { rm -rf "$tmp"; return 1; }
                  cp "$bin" "$PREFIX/bin/aeb" ;;
        *)        cp "$tmp/asset" "$PREFIX/bin/aeb" ;;
      esac
      chmod +x "$PREFIX/bin/aeb"
      rm -rf "$tmp"
      # Prove it actually runs on this box before trusting it.
      if "$PREFIX/bin/aeb" --version >/dev/null 2>&1; then
        say "installed aeb ${AEB_REF} from a release binary (${name})"
        return 0
      fi
      rm -f "$PREFIX/bin/aeb"
      return 1
    fi
  done
  rm -rf "$tmp"
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
