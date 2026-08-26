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

# Fresh per-node logs each run, so the summary can't read a stale FAILED.
rm -rf target/.aeb/logs 2>/dev/null || true

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
aeb "$TARGET" 2>&1 | tee "$LOG"
RC="${PIPESTATUS[0]}"

# IMPORTANT: aeb currently does NOT propagate a node's non-zero return to its own
# exit code (a failing .tests.ae still lets `aeb` exit 0 — filed as REQUEST 4 in
# ~/scm/aeb/selenium-porting-needs-for-aeb.md). So we do NOT trust RC alone: we
# scan every per-node log for a FAILED marker and fail the run ourselves. This
# keeps the gate honest today; once aeb propagates, RC becomes sufficient and
# this stays as belt-and-suspenders.
LOGDIR="target/.aeb/logs"
FAILS=""
SKIPS=""
if [ -d "$LOGDIR" ]; then
  # A node marks failure by printing "<name> ... FAILED" (see the .tests.ae
  # nodes). SKIPPED (toolchain/driver absent) is green and only listed.
  FAILS="$(grep -rliE '(tests|example|package|build)[^:]*: .*FAILED|: FAILED' "$LOGDIR" 2>/dev/null || true)"
  SKIPS="$(grep -riE 'SKIPPED' "$LOGDIR" 2>/dev/null || true)"
fi

echo
echo "------------------------------- summary --------------------------"
node_logs=$(find "$LOGDIR" -name '*.log' 2>/dev/null | wc -l | tr -d ' ')
fail_ct=$(printf '%s' "$FAILS" | grep -c . || true)
skip_ct=$(printf '%s' "$SKIPS" | grep -c . || true)
printf '  node logs written : %s\n' "$node_logs"
printf '  failed nodes      : %s\n' "$fail_ct"
printf '  skip markers      : %s (toolchain/driver absent — green, verify elsewhere)\n' "$skip_ct"
if [ -n "$SKIPS" ]; then
  echo "  --- skips ---"
  printf '%s\n' "$SKIPS" | sed 's/^/    /' | head -30
fi
if [ -n "$FAILS" ]; then
  echo "  --- FAILED nodes (log → offending line) ---"
  for f in $FAILS; do
    echo "    $f:"
    grep -iE 'FAILED|Error|No module|not found' "$f" | sed 's/^/      /' | head -4
  done
fi
echo "------------------------------------------------------------------"

if [ "$RC" -ne 0 ] || [ -n "$FAILS" ]; then
  echo "ci/run: FAILED (aeb exit $RC; failed node logs: ${fail_ct})"
  exit 1
fi
echo "ci/run: GREEN (all nodes passed or skipped)"
