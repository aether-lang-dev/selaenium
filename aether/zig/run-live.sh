#!/usr/bin/env bash
# Drives the Zig live-surface test: start the content server + chromedriver,
# pass their URLs to the pre-built selenium-live binary via env, tear down.
# Self-skips (exit 0) if chromedriver is absent. Args: <path-to-selenium-live>
set -u
BIN="${1:?usage: run-live.sh <selenium-live binary>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! command -v chromedriver >/dev/null 2>&1; then
  echo "SKIPPED: chromedriver not on PATH"
  exit 0
fi

# Content server (prints "PORT <n>").
SRV_OUT="$(mktemp)"
python3 "$HERE/content_server.py" >"$SRV_OUT" 2>/dev/null &
SRV_PID=$!
for _ in $(seq 1 50); do
  WEBPORT="$(sed -n 's/^PORT //p' "$SRV_OUT" 2>/dev/null | head -1)"
  [ -n "$WEBPORT" ] && break
  sleep 0.1
done
if [ -z "${WEBPORT:-}" ]; then echo "content server did not start"; kill $SRV_PID 2>/dev/null; exit 1; fi

# chromedriver on an ephemeral port.
CDPORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
chromedriver --port="$CDPORT" >/dev/null 2>&1 &
CD_PID=$!

cleanup() { kill "$CD_PID" "$SRV_PID" 2>/dev/null; rm -f "$SRV_OUT"; }
trap cleanup EXIT

# Wait for chromedriver.
for _ in $(seq 1 100); do
  if python3 -c "import socket,sys; s=socket.socket();
try: s.connect(('127.0.0.1',$CDPORT)); s.close()
except OSError: sys.exit(1)" 2>/dev/null; then break; fi
  sleep 0.1
done

SEL_CHROMEDRIVER_URL="http://127.0.0.1:$CDPORT" \
  SEL_BASE_URL="http://127.0.0.1:$WEBPORT" \
  "$BIN"
