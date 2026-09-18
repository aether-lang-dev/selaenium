#!/usr/bin/env sh
# nodecount_live.sh — the LIVE proof that /se/grid/nodecount reflects a real
# registration, i.e. the "-1" gap is closed.
#
# WHY THIS EXISTS: the registry read path is easy to get falsely-green. A POST
# /se/grid/register that returns {"ok":true} proves only that the HANDLER ran,
# not that the node landed in the registry — the original bug returned a 2xx ack
# while nodecount stayed -1 because a pool-thread handler's actor send was
# silently dropped. This test distinguishes "handler acked" from "state actually
# changed": it registers nodes and asserts the COUNT moves 0 -> 1 -> 2, and that
# a re-register is idempotent (stays 2). Only the pool-owned CAS registry (no
# actor hand-off) makes this pass.
#
# Needs only the hub binary — no driver, no browser, no container. Self-skips
# cleanly if the hub isn't built or can't bind. Runnable standalone or from CI.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

HUB="${SEL_HUB_BIN:-}"
if [ -z "$HUB" ]; then
    for cand in target/build/grid/bin/selaenium-hub target/build/grid/selaenium-hub \
                target/tests/grid/bin/selaenium-hub; do
        [ -x "$cand" ] && HUB="$cand" && break
    done
fi
if [ -z "$HUB" ] || [ ! -x "$HUB" ]; then
    echo "SKIP (nodecount_live): no selaenium-hub binary; build it with \`aeb grid/.build.ae\`"
    exit 0
fi
command -v curl >/dev/null 2>&1 || { echo "SKIP (nodecount_live): curl not found"; exit 0; }

# A high, unlikely-taken port so parallel test runs don't collide.
PORT="${SEL_HUB_PORT:-14791}"
URL="http://127.0.0.1:${PORT}"

SEL_HUB_PORT="$PORT" "$HUB" >/dev/null 2>&1 &
hub_pid=$!
trap 'kill "$hub_pid" 2>/dev/null; wait "$hub_pid" 2>/dev/null || true' EXIT INT TERM

# Wait for readiness (or a dead hub — port in use).
ready=0
i=0
while [ "$i" -lt 20 ]; do
    if curl -fsS "${URL}/status" 2>/dev/null | grep -q '"ready": *true'; then ready=1; break; fi
    kill -0 "$hub_pid" 2>/dev/null || break
    i=$((i + 1)); sleep 0.5
done
[ "$ready" = "1" ] || { echo "SKIP (nodecount_live): hub never became ready on :$PORT"; exit 0; }

# nodecount is {"nodes":N} — extract N.
count() { curl -fsS "${URL}/se/grid/nodecount" 2>/dev/null | sed 's/.*"nodes"[: ]*\([0-9-]*\).*/\1/'; }
register() { # id addr browsers-json max
    curl -fsS -X POST "${URL}/se/grid/register" -H 'Content-Type: application/json' \
        -d "{\"id\":\"$1\",\"address\":\"$2\",\"browsers\":$3,\"maxSessions\":$4}" >/dev/null 2>&1
}
expect() { # got want label
    if [ "$1" != "$2" ]; then
        echo "  [FAIL] $3: nodecount=$1, expected $2"
        echo "FAIL: nodecount_live"
        exit 1
    fi
    echo "  [ok] $3: nodecount=$1"
}

expect "$(count)" 0 "empty registry (not -1)"
register node-A "http://127.0.0.1:5555" '["chrome","firefox"]' 3
expect "$(count)" 1 "after registering node-A"
register node-B "http://127.0.0.1:5556" '["chrome"]' 1
expect "$(count)" 2 "after registering node-B"
register node-A "http://127.0.0.1:5555" '["chrome"]' 2   # re-register: replace, not add
expect "$(count)" 2 "re-register node-A is idempotent"

echo "  [PASS] /se/grid/nodecount reflects real registrations — the -1 gap is closed"
echo "PASS: nodecount_live"
exit 0
