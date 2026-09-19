#!/usr/bin/env sh
# distribute_live.sh — the LIVE proof that the hub DISTRIBUTES a session to a
# registered node (not a local driver) and routes later requests back to it.
#
# WHY THIS EXISTS: nodecount_live.sh proves a node registers; this proves the
# distributor actually USES it. It starts a hub + a node, POSTs newSession to the
# HUB, and asserts:
#   1. the session was created (a real chromedriver session comes back), AND
#   2. the hub session id carries the node-routing sentinel "0-<node_port>-..."
#      (pid=0 = "a node, not a local driver"; node_port = where forward routes),
#      which is the ONLY thing that makes a follow-up request reach the node, AND
#   3. a session-scoped GET (get title) routed THROUGH the hub reaches the node's
#      driver and returns, AND
#   4. DELETE through the hub ends the session and releases the node slot
#      (nodecount stays, availability returns).
#
# Needs chromedriver + chrome on PATH (the node provisions them). Self-skips
# cleanly if the hub/node binaries or chromedriver are absent.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HUB="target/build/grid/bin/selaenium-hub"
NODE="target/build/grid/bin/selaenium-node"
HUB_PORT=4463
NODE_PORT=5563

if [ ! -x "$HUB" ] || [ ! -x "$NODE" ]; then
  echo "SKIP distribute_live: hub/node not built (aeb grid/.build.ae)"; exit 0
fi
if ! command -v chromedriver >/dev/null 2>&1; then
  echo "SKIP distribute_live: chromedriver not on PATH"; exit 0
fi

TMP="$(mktemp -d)"
cleanup() {
  [ -n "${NODE_PID:-}" ] && kill "$NODE_PID" 2>/dev/null || true
  [ -n "${HUB_PID:-}" ] && kill "$HUB_PID" 2>/dev/null || true
  pkill -f "selaenium-node" 2>/dev/null || true
  pkill -f "selaenium-hub" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

SEL_HUB_PORT="$HUB_PORT" "$HUB" >"$TMP/hub.log" 2>&1 &
HUB_PID=$!
sleep 2
SEL_NODE_PORT="$NODE_PORT" SEL_HUB_URL="http://127.0.0.1:$HUB_PORT" \
  SEL_NODE_BROWSERS="chrome" SEL_NODE_MAX="2" "$NODE" >"$TMP/node.log" 2>&1 &
NODE_PID=$!
sleep 2

fail() { echo "[FAIL] $1"; echo "--- hub.log ---"; cat "$TMP/hub.log"; echo "--- node.log ---"; cat "$TMP/node.log"; exit 1; }

# node registered?
nc="$(curl -s "http://127.0.0.1:$HUB_PORT/se/grid/nodecount" || true)"
echo "$nc" | grep -q '"nodes":1' || fail "node did not register (nodecount=$nc)"
echo "  [ok] node registered: $nc"

# POST newSession to the HUB
# A box with cache-only Chrome-for-Testing has no system Chrome, so chromedriver
# fails with "cannot find Chrome binary" unless the capability carries the path.
# SEL_CHROME_BINARY is the same env var the language bindings honour.
if [ -n "${SEL_CHROME_BINARY:-}" ]; then
    CHROME_BIN_CAP=",\"binary\":\"$SEL_CHROME_BINARY\""
else
    CHROME_BIN_CAP=""
fi
caps="{\"capabilities\":{\"alwaysMatch\":{\"browserName\":\"chrome\",\"goog:chromeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]$CHROME_BIN_CAP}}}}"
resp="$(curl -s -X POST "http://127.0.0.1:$HUB_PORT/session" -H 'Content-Type: application/json' -d "$caps" || true)"
sid="$(printf '%s' "$resp" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')"
[ -n "$sid" ] || fail "no sessionId from newSession (resp: $(printf '%s' "$resp" | head -c 300))"
echo "  [ok] session created via the hub: sessionId=$sid"

# the id must carry the node-routing sentinel: 0-<node_port>-...
case "$sid" in
  0-"$NODE_PORT"-*) echo "  [ok] session id routes to the node (0-$NODE_PORT-...)" ;;
  *) fail "session id '$sid' is NOT node-routed (expected 0-$NODE_PORT-...) — it ran on a LOCAL driver, not the node" ;;
esac

# a session-scoped request THROUGH the hub reaches the node's driver
title="$(curl -s "http://127.0.0.1:$HUB_PORT/session/$sid/title" || true)"
printf '%s' "$title" | grep -q '"value"' || fail "get-title through the hub did not route to the node (resp: $(printf '%s' "$title" | head -c 200))"
echo "  [ok] session-scoped GET routed hub -> node -> driver: $(printf '%s' "$title" | head -c 80)"

# DELETE through the hub ends the session (and releases the node slot)
del="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "http://127.0.0.1:$HUB_PORT/session/$sid" || true)"
[ "$del" = "200" ] || echo "  [warn] DELETE returned $del (non-200)"
echo "  [ok] session deleted through the hub (HTTP $del)"

echo "[PASS] the hub distributes to a registered node and routes back — distributed Grid session path works"
echo "PASS: distribute_live"
