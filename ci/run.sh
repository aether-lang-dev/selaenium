#!/usr/bin/env bash
# CI entry point — aeb IS the CI here (no GitHub Actions).
#
# Ensures the pinned toolchain, builds the engine, runs the full presubmit
# (engine probe + all 18 binding tests + the consumer-install examples), and
# prints an honest summary: which nodes actually EXECUTED vs SKIPPED because
# their toolchain/driver is absent on this box. A skip is green — the binding is
# fine, the box is under-provisioned — but CI must not let a wall of skips read
# as "everything ran", so the tally is explicit.
#
# Usage:
#   ci/run.sh                 # toolchain + full presubmit
#   ci/run.sh --offline       # engine probe only (fast, no per-binding toolchain)
#   ci/run.sh --no-toolchain  # assume ae/aeb already on PATH (skip install)
#   TARGET=php/.tests.ae ci/run.sh --no-toolchain   # run one node
#
# Exit non-zero iff a node actually FAILED (a skip never fails the run).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

OFFLINE=0
DO_TOOLCHAIN=1
for arg in "$@"; do
  case "$arg" in
    --offline)      OFFLINE=1 ;;
    --no-toolchain) DO_TOOLCHAIN=0 ;;
    *) echo "ci/run: unknown arg '$arg'"; exit 2 ;;
  esac
done

if [ "$DO_TOOLCHAIN" = "1" ]; then
  "$HERE/toolchain.sh"
fi
export PATH="${PREFIX:-$HOME/.local}/bin:$HOME/.aether/bin:$PATH"
command -v aeb >/dev/null 2>&1 || { echo "ci/run: aeb not on PATH (run ci/toolchain.sh)"; exit 1; }

# Pick the target set.
TARGET="${TARGET:-}"
if [ -z "$TARGET" ]; then
  if [ "$OFFLINE" = "1" ]; then
    TARGET="selenium_core/tests/.tests.ae"   # pure-Aether engine probe, no FFI, no browser
  else
    TARGET=".presubmit.ae"                    # everything (toolchain-gated skips)
  fi
fi

echo "=================================================================="
echo " ci/run: aeb $TARGET"
echo "         $(aeb --version 2>&1 | head -1)"
echo "=================================================================="

# Always (re)build the engine first — every binding deps its .so.
aeb selenium_core/.build.ae >/dev/null 2>&1 || { echo "ci/run: FATAL — engine build failed"; aeb selenium_core/.build.ae; exit 1; }

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
aeb "$TARGET" 2>&1 | tee "$LOG"
RC="${PIPESTATUS[0]}"

echo
echo "------------------------------- summary --------------------------"
# Node self-reports carry these markers in their stdout (captured above and in
# target/.aeb/logs/*). Count them for an at-a-glance executed/skipped/failed view.
ran=$(grep -ciE 'PASS(ED)?[:) ]|green|examples,' "$LOG" || true)
skipped=$(grep -ciE 'SKIPPED' "$LOG" || true)
failed=$(grep -ciE 'FAIL(ED)?[: ]' "$LOG" || true)
printf '  executed/green markers : %s\n' "$ran"
printf '  skipped (toolchain gap): %s\n' "$skipped"
printf '  failure markers        : %s\n' "$failed"
if grep -qiE 'SKIPPED' "$LOG"; then
  echo "  --- skipped nodes (verify these on a box with the toolchain) ---"
  grep -iE 'SKIPPED' "$LOG" | sed 's/^/    /' | head -30
fi
echo "------------------------------------------------------------------"

if [ "$RC" -ne 0 ]; then
  echo "ci/run: FAILED (aeb exit $RC)"
  exit "$RC"
fi
echo "ci/run: GREEN (aeb exit 0)"
