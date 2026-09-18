#!/usr/bin/env sh
# heartbeat_live.sh — the LIVE proof of node heartbeat + stale-node expiry.
#
# Two halves, both load-bearing for the distributor not routing to dead nodes:
#   1. A live node that HEARTBEATS keeps nodecount at 1 across several TTL windows
#      (a one-shot registration would expire; the periodic re-POST sustains it).
#   2. A node that STOPS (killed) stops heartbeating, and the hub expires it — its
#      last_ms goes stale past the TTL, reads freshness-filter it out, and a
#      register-triggered sweep compacts it — so nodecount drops back to 0.
#
# Short TTL + fast heartbeat are set via env so the test runs in ~10s, not 15s.
# Needs only the hub + node binaries — no driver, no browser.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HUB="target/build/grid/bin/selaenium-hub"
NODE="target/build/grid/bin/selaenium-node"
HUB_PORT=4483
NODE_PORT=5583
TTL=3000          # a node is stale 3s after its last heartbeat
HB=800            # node re-registers every 0.8s (well within the TTL)

if [ ! -x "$HUB" ] || [ ! -x "$NODE" ]; then echo "SKIP heartbeat_live: hub/node not built"; exit 0; fi

TMP="$(mktemp -d)"
cleanup() {
  [ -n "${NODE_PID:-}" ] && kill "$NODE_PID" 2>/dev/null || true
  [ -n "${HUB_PID:-}" ] && kill "$HUB_PID" 2>/dev/null || true
  pkill -f "selaenium-node" 2>/dev/null || true
  pkill -f "selaenium-hub" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

nc() { curl -s "http://127.0.0.1:$HUB_PORT/se/grid/nodecount"; }
fail() { echo "[FAIL] $1"; exit 1; }

SEL_HUB_PORT="$HUB_PORT" SEL_GRID_NODE_TTL="$TTL" "$HUB" >"$TMP/hub.log" 2>&1 & HUB_PID=$!
sleep 2
SEL_NODE_PORT="$NODE_PORT" SEL_HUB_URL="http://127.0.0.1:$HUB_PORT" SEL_NODE_BROWSERS="chrome" \
  SEL_NODE_MAX=1 SEL_NODE_HEARTBEAT="$HB" "$NODE" >"$TMP/node.log" 2>&1 & NODE_PID=$!
sleep 1

nc | grep -q '"nodes":1' || fail "node did not register ($(nc))"
echo "  [ok] node registered: $(nc)"

# Half 1: heartbeat sustains the node across > 1 TTL window (would expire at 3s
# without a heartbeat; we wait ~5s and it's still there).
sleep 5
nc | grep -q '"nodes":1' || fail "heartbeat did not sustain the node past the TTL ($(nc))"
echo "  [ok] heartbeat sustained the node across a TTL window (still $(nc))"

# Half 2: kill the node; it stops heartbeating; after the TTL it must expire.
kill "$NODE_PID" 2>/dev/null || true; pkill -f "selaenium-node" 2>/dev/null || true
NODE_PID=""
echo "  [ok] node killed — it will stop heartbeating"
# wait past the TTL, then a read (nodecount) freshness-filters it out.
sleep 4
after="$(nc)"
echo "$after" | grep -q '"nodes":0' || fail "dead node did not expire after the TTL (nodecount=$after)"
echo "  [ok] dead node expired from the registry after the TTL ($after)"

echo "[PASS] node heartbeat sustains a live node; a dead node expires after its TTL"
echo "PASS: heartbeat_live"
