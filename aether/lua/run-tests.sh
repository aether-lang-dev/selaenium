#!/usr/bin/env bash
# Build the Lua 5.4 C extension + (if needed) a Lua 5.4 host, then run the FFI
# test and the live-surface test. Debian ships a 5.3 interpreter but 5.4 dev
# headers, so a 5.4 extension can't load in the distro `lua` — we build a small
# 5.4 host (host/lua54.c) unless a real lua5.4 binary is present. The live test
# gets chromedriver + a content server started here, URLs passed via env; it
# self-skips if chromedriver is absent. Args: <engine .so path>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${1:?usage: run-tests.sh <libselenium_core.so>}"

CFLAGS="$(pkg-config --cflags lua5.4 2>/dev/null || echo -I/usr/include/lua5.4)"
LIBS="$(pkg-config --libs lua5.4 2>/dev/null || echo -llua5.4)"

# The C extension (dlopen's the engine at run time; not on its link line).
cc -O2 -fPIC -shared $CFLAGS "$HERE/src/selenium_core.c" -o "$HERE/selenium_core_native.so" -ldl || {
  echo "lua: failed to build the C extension"; exit 1; }

# Pick a Lua 5.4 runner.
if command -v lua5.4 >/dev/null 2>&1; then
  LUA="lua5.4"
else
  cc -O2 $CFLAGS "$HERE/host/lua54.c" -o "$HERE/lua54" $LIBS -lm -ldl || {
    echo "lua: failed to build the 5.4 host"; exit 1; }
  LUA="$HERE/lua54"
fi

export SELENIUM_CORE_LIB="$ENGINE"
export LUA_CPATH="$HERE/?.so"
export LUA_PATH="$HERE/src/?.lua"

# FFI test.
"$LUA" "$HERE/test/ffi_test.lua" || exit 1

# Live test: start content server + chromedriver, pass URLs via env.
if ! command -v chromedriver >/dev/null 2>&1; then
  echo "  (live) SKIPPED: chromedriver not on PATH"
  exit 0
fi
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

SEL_CHROMEDRIVER_URL="http://127.0.0.1:$CDPORT" \
  SEL_BASE_URL="http://127.0.0.1:$WEBPORT" \
  "$LUA" "$HERE/test/live_test.lua"
