#!/usr/bin/env bash
# Ensure the pinned Aether toolchain (ae + aeb) is installed and on PATH.
#
# Idempotent: if ae and aeb are already present it does nothing but print what
# it found — so it is cheap to call at the top of every CI lane. Pins come from
# ci/versions.env (override via the AETHER_REF / AEB_REF env vars).
#
# Aether compiles to C, so the only host prerequisites are curl, tar, GNU make,
# and a C compiler — no chicken-and-egg. Both installers are the public
# no-clone curl-pipe path (aether get.sh, aeb install.sh); each is pinnable.
#
# Usage:  ci/toolchain.sh            # install if missing, print versions
#         FORCE=1 ci/toolchain.sh    # reinstall even if present
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
  say "installing aeb ${AEB_REF} …"
  AEB_REF="$AEB_REF" PREFIX="$PREFIX" AETHER="$(command -v ae)" \
    curl -sSL "https://raw.githubusercontent.com/aether-lang-dev/aeb/main/install.sh" | sh
else
  say "aeb present: $(aeb --version 2>&1 | head -1) (skipping; FORCE=1 to reinstall)"
fi

say "ae  -> $(command -v ae)   $(ae  --version 2>&1 | head -1)"
say "aeb -> $(command -v aeb)  $(aeb --version 2>&1 | head -1)"
