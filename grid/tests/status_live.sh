#!/usr/bin/env sh
# status_live.sh — the LIVE proof of GET /se/grid/status: the Grid introspection
# endpoint reports the registered nodes AND tracks their slot usage as sessions
# come and go.
#
# Asserts:
#   1. with a node registered, /se/grid/status is {"value":{"ready":true,...,
#      "nodes":[{...}]}} carrying the node's id + address + "inuse":0.
#   2. after distributing a session to the node, status shows "inuse":1.
#   3. after DELETE, status shows "inuse":0 again (the slot was released).
#
# Steps 1 needs only the binaries; 2-3 need chromedriver + chrome (self-skipped
# with a partial PASS if the driver is absent, since step 1 is the core contract).
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HUB="target/build/grid/bin/selaenium-hub"
NODE="target/build/grid/bin/selaenium-node"
HUB_PORT=4493
NODE_PORT=5593

if [ ! -x "$HUB" ] || [ ! -x "$NODE" ]; then echo "SKIP status_live: hub/node not built"; exit 0; fi

TMP="$(mktemp -d)"
cleanup() {
  [ -n "${NODE_PID:-}" ] && kill "$NODE_PID" 2>/dev/null || true
  [ -n "${HUB_PID:-}" ] && kill "$HUB_PID" 2>/dev/null || true
  pkill -f "selaenium-node" 2>/dev/null || true
  pkill -f "selaenium-hub" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

st() { curl -s "http://127.0.0.1:$HUB_PORT/se/grid/status"; }
fail() { echo "[FAIL] $1"; echo "--- status ---"; st; echo; exit 1; }

SEL_HUB_PORT="$HUB_PORT" "$HUB" >"$TMP/hub.log" 2>&1 & HUB_PID=$!
sleep 2
SEL_NODE_PORT="$NODE_PORT" SEL_HUB_URL="http://127.0.0.1:$HUB_PORT" SEL_NODE_BROWSERS="chrome" \
  SEL_NODE_MAX=1 SEL_NODE_HEARTBEAT=800 "$NODE" >"$TMP/node.log" 2>&1 & NODE_PID=$!
sleep 1

# 1. status reports the node, ready, inuse 0
s="$(st)"
printf '%s' "$s" | grep -q '"ready":true' || fail "status not ready: $s"
printf '%s' "$s" | grep -q "\"address\":\"http://127.0.0.1:$NODE_PORT\"" || fail "node address not in status: $s"
printf '%s' "$s" | grep -q '"inuse":0' || fail "expected inuse 0 at rest: $s"
echo "  [ok] /se/grid/status ready=true, node listed, inuse=0"

if ! command -v chromedriver >/dev/null 2>&1; then
  echo "  [skip] inuse tracking needs chromedriver (absent) — the status contract (step 1) passed"
  echo "[PASS] /se/grid/status reports live nodes (slot-tracking legs skipped: no chromedriver)"
  echo "PASS: status_live (partial)"
  exit 0
fi

# 2. distribute a session; status should show inuse 1
caps='{"capabilities":{"alwaysMatch":{"browserName":"chrome","goog:chromeOptions":{"args":["--headless=new","--no-sandbox","--disable-gpu","--disable-dev-shm-usage"]}}}}'
resp="$(curl -s -X POST "http://127.0.0.1:$HUB_PORT/session" -H 'Content-Type: application/json' -d "$caps")"
sid="$(printf '%s' "$resp" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')"
[ -n "$sid" ] || fail "no session created: $(printf '%s' "$resp" | head -c 200)"
s2="$(st)"
printf '%s' "$s2" | grep -q '"inuse":1' || fail "status did not show inuse=1 after a session: $s2"
echo "  [ok] after distributing a session, status shows inuse=1"

# 3. delete; status should return to inuse 0
curl -s -o /dev/null -X DELETE "http://127.0.0.1:$HUB_PORT/session/$sid" || true
sleep 1
s3="$(st)"
printf '%s' "$s3" | grep -q '"inuse":0' || fail "status did not return to inuse=0 after DELETE: $s3"
echo "  [ok] after DELETE, status shows inuse=0 (slot released)"

echo "[PASS] /se/grid/status reports live nodes and tracks slot usage across a session"
echo "PASS: status_live"
