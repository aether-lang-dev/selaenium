#!/usr/bin/env bash
# Drives the Zig consumer example's live mode: spawn chromedriver, pass its URL
# via SEL_CHROMEDRIVER_URL, run the example with SELENIUM_CORE_LIB unset. The
# example navigates a data: URL (no content server needed). Skips (exit 0) if
# chromedriver is absent. Args: <path-to-selenium-example>
set -u
BIN="${1:?usage: run-example-live.sh <selenium-example binary>}"

if ! command -v chromedriver >/dev/null 2>&1; then
  echo "consumer(live): SKIPPED — chromedriver not on PATH"
  exit 0
fi

CDPORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
chromedriver --port="$CDPORT" >/dev/null 2>&1 &
CD_PID=$!
trap 'kill "$CD_PID" 2>/dev/null' EXIT

for _ in $(seq 1 100); do
  if python3 -c "import socket,sys
try:
    s=socket.socket(); s.connect(('127.0.0.1',$CDPORT)); s.close()
except OSError: sys.exit(1)" 2>/dev/null; then break; fi
  sleep 0.1
done

env -u SELENIUM_CORE_LIB \
  SEL_MODE=live SEL_CHROMEDRIVER_URL="http://127.0.0.1:$CDPORT" \
  "$BIN"
