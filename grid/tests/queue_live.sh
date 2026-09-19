#!/usr/bin/env sh
# queue_live.sh — the LIVE proof of the new-session QUEUE: when the only node for
# a browser is saturated, the hub HOLDS a newSession until a slot frees, then
# runs it on the node (rather than failing or silently using a local driver).
#
# Scenario: one node, ONE slot, chrome.
#   1. Session A -> the hub -> runs on the node, fills its only slot.
#   2. Session B -> the hub, fired in the BACKGROUND. The node is full but hosts
#      chrome, so the distributor QUEUES B (it blocks, doesn't return yet).
#   3. Assert B has NOT returned while A holds the slot (it's queued, not failed).
#   4. DELETE A -> frees the node slot.
#   5. B now unblocks, gets the slot, and returns a real node session
#      (id 0-<node_port>-...). That's the queue working.
#
# Needs chromedriver + chrome. Self-skips if binaries/driver absent.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HUB="target/build/grid/bin/selaenium-hub"
NODE="target/build/grid/bin/selaenium-node"
HUB_PORT=4473
NODE_PORT=5573

if [ ! -x "$HUB" ] || [ ! -x "$NODE" ]; then echo "SKIP queue_live: hub/node not built"; exit 0; fi
if ! command -v chromedriver >/dev/null 2>&1; then echo "SKIP queue_live: chromedriver not on PATH"; exit 0; fi

TMP="$(mktemp -d)"
cleanup() {
  [ -n "${NODE_PID:-}" ] && kill "$NODE_PID" 2>/dev/null || true
  [ -n "${HUB_PID:-}" ] && kill "$HUB_PID" 2>/dev/null || true
  pkill -f "selaenium-node" 2>/dev/null || true
  pkill -f "selaenium-hub" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# A box with cache-only Chrome-for-Testing has no system Chrome, so chromedriver
# fails with "cannot find Chrome binary" unless the capability carries the path.
# SEL_CHROME_BINARY is the same env var the language bindings honour.
if [ -n "${SEL_CHROME_BINARY:-}" ]; then
    CHROME_BIN_CAP=",\"binary\":\"$SEL_CHROME_BINARY\""
else
    CHROME_BIN_CAP=""
fi
CAPS="{\"capabilities\":{\"alwaysMatch\":{\"browserName\":\"chrome\",\"goog:chromeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]$CHROME_BIN_CAP}}}}"
new_session() { curl -s -X POST "http://127.0.0.1:$HUB_PORT/session" -H 'Content-Type: application/json' -d "$CAPS"; }
sid_of() { sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p'; }
fail() { echo "[FAIL] $1"; cat "$TMP/hub.log" 2>/dev/null; exit 1; }

SEL_HUB_PORT="$HUB_PORT" SEL_GRID_QUEUE_TIMEOUT=30000 "$HUB" >"$TMP/hub.log" 2>&1 & HUB_PID=$!
sleep 2
# ONE slot node.
SEL_NODE_PORT="$NODE_PORT" SEL_HUB_URL="http://127.0.0.1:$HUB_PORT" SEL_NODE_BROWSERS="chrome" SEL_NODE_MAX=1 "$NODE" >"$TMP/node.log" 2>&1 & NODE_PID=$!
sleep 2

curl -s "http://127.0.0.1:$HUB_PORT/se/grid/nodecount" | grep -q '"nodes":1' || fail "node did not register"
echo "  [ok] 1-slot chrome node registered"

# Session A fills the slot.
a="$(new_session)"; a_sid="$(printf '%s' "$a" | sid_of)"
[ -n "$a_sid" ] || fail "session A not created: $(printf '%s' "$a" | head -c 200)"
case "$a_sid" in 0-"$NODE_PORT"-*) : ;; *) fail "A '$a_sid' not on the node" ;; esac
echo "  [ok] session A on the node ($a_sid) — slot now full"

# Session B in the background; capture when it returns.
( new_session >"$TMP/b.json" 2>/dev/null; echo done >"$TMP/b.done" ) &
sleep 3   # give B time to be queued (it must block, not return)

if [ -f "$TMP/b.done" ]; then fail "session B returned while A held the only slot — it was NOT queued (b=$(cat "$TMP/b.json" | head -c 200))"; fi
echo "  [ok] session B is QUEUED (has not returned while the slot is full)"

# Free the slot.
del="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "http://127.0.0.1:$HUB_PORT/session/$a_sid")"
echo "  [ok] session A deleted (HTTP $del) — slot freed"

# B should now unblock and succeed on the node.
i=0
while [ ! -f "$TMP/b.done" ]; do
  i=$((i+1)); [ "$i" -gt 100 ] && fail "session B never returned after the slot freed (queue stuck)"
  sleep 0.2
done
b_sid="$(cat "$TMP/b.json" | sid_of)"
[ -n "$b_sid" ] || fail "session B returned but no sessionId: $(cat "$TMP/b.json" | head -c 200)"
case "$b_sid" in 0-"$NODE_PORT"-*) echo "  [ok] queued session B ran on the node after the slot freed ($b_sid)" ;;
  *) fail "B '$b_sid' did not run on the node (fell back to local?)" ;; esac

curl -s -o /dev/null -X DELETE "http://127.0.0.1:$HUB_PORT/session/$b_sid" || true

echo "[PASS] the hub queues a newSession when nodes are saturated and runs it when a slot frees"
echo "PASS: queue_live"
