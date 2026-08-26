#!/usr/bin/env bash
# Haskell binding: build with cabal (links the engine .so), then run the test.
# chromedriver + a content server are started here, URLs passed via env; the
# test self-skips if chromedriver is absent. SKIPS LOUDLY (exit 0) if GHC/cabal
# is not installed. Args: <engine .so path>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${1:-${SELENIUM_CORE_LIB:?need engine .so via arg or SELENIUM_CORE_LIB}}"

if ! command -v cabal >/dev/null 2>&1 || ! command -v ghc >/dev/null 2>&1; then
  echo "haskell tests: SKIPPED — GHC/cabal not on PATH (authored here, verify on a box with GHC)"
  exit 0
fi

# Stage the engine .so where the .cabal extra-lib-dirs points.
mkdir -p "$HERE/native"
cp "$ENGINE" "$HERE/native/libselenium_core.so"

# The engine .so lives in two candidate dirs: the staged copy under
# $HERE/native and the in-tree build output next to $ENGINE. cabal 9.10 rejects
# a bare relative extra-lib-dirs and won't expand ${pkgroot} at configure time,
# so we pass both dirs (absolute) and their rpaths on the command line.
ENGINE_DIR="$(cd "$(dirname "$ENGINE")" && pwd)"
NATIVE_DIR="$HERE/native"
CABAL_LIBFLAGS=(
  --extra-lib-dirs="$NATIVE_DIR"
  --extra-lib-dirs="$ENGINE_DIR"
  --ghc-options="-optl-Wl,-rpath,$NATIVE_DIR"
  --ghc-options="-optl-Wl,-rpath,$ENGINE_DIR"
)

# Build the test executable (offline; no external deps beyond base).
( cd "$HERE" && cabal build --offline "${CABAL_LIBFLAGS[@]}" test:live 2>&1 ) || {
  ( cd "$HERE" && cabal build "${CABAL_LIBFLAGS[@]}" test:live ) || { echo "haskell tests: cabal build FAILED"; exit 1; }
}

BIN="$(cd "$HERE" && cabal list-bin test:live 2>/dev/null)"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then echo "haskell tests: could not locate test binary"; exit 1; fi

# No chromedriver → FFI-only run (the test self-skips the live part).
if ! command -v chromedriver >/dev/null 2>&1; then
  SELENIUM_CORE_LIB="$ENGINE" "$BIN"
  exit $?
fi

# Content server (prints "PORT <n>") + chromedriver.
SRV_OUT="$(mktemp)"
python3 "$HERE/content_server.py" >"$SRV_OUT" 2>/dev/null &
SRV_PID=$!
for _ in $(seq 1 50); do
  WEBPORT="$(sed -n 's/^PORT //p' "$SRV_OUT" 2>/dev/null | head -1)"
  [ -n "$WEBPORT" ] && break; sleep 0.1
done
CDPORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
chromedriver --port="$CDPORT" >/dev/null 2>&1 &
CD_PID=$!
cleanup() { kill "$CD_PID" "$SRV_PID" 2>/dev/null; rm -f "$SRV_OUT"; }
trap cleanup EXIT
for _ in $(seq 1 100); do
  python3 -c "import socket,sys
try:
    s=socket.socket(); s.connect(('127.0.0.1',$CDPORT)); s.close()
except OSError: sys.exit(1)" 2>/dev/null && break
  sleep 0.1
done

SELENIUM_CORE_LIB="$ENGINE" \
  SEL_CHROMEDRIVER_URL="http://127.0.0.1:$CDPORT" \
  SEL_BASE_URL="http://127.0.0.1:$WEBPORT" \
  "$BIN"
