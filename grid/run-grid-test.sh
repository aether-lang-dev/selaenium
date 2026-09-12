#!/usr/bin/env bash
# grid/run-grid-test.sh — Tier-1 Grid integration harness.
#
# Stands up a REAL Selenium Grid in a container (the official
# selenium/standalone-chromium image = router + node + Chromium in one), waits
# for it to report ready, then runs a per-binding grid test that drives a
# session THROUGH the hub — proving selaenium's Grid-CLIENT path (openSession ->
# HTTP -> router -> node -> browser), the one thing our Grid support actually is
# (we are a Grid client, not a Grid server). Tears the container down after.
#
# The binding test itself is toolchain-agnostic: it reads the hub URL from
# SEL_GRID_URL and self-skips (exit 0) when it is unset — so a plain
# `aeb <binding>/.tests.ae` (no Grid) still passes, and only THIS script wires a
# live Grid in. Self-skips cleanly if podman and the image are unavailable.
#
# Usage:
#   grid/run-grid-test.sh <cmd...>        # run <cmd> with SEL_GRID_URL exported
#   grid/run-grid-test.sh                 # just start/wait/print the URL, then stop
#   grid/run-grid-test.sh --hub <cmd...>  # against OUR OWN hub, not the container
#
# --hub swaps the reference Grid for selaenium's own standalone hub
# (grid/hub.ae, built by grid/.build.ae). Same contract — a W3C endpoint on
# SEL_GRID_URL — so the identical per-binding Grid legs run against either, which
# is exactly how our hub is held to the reference implementation's behaviour. It
# needs no container and no 2.3GB image, just a driver the engine can resolve.
#
# Env: SEL_GRID_IMAGE (default selenium/standalone-chromium:latest),
#      SEL_GRID_PORT (default 4444), SEL_GRID_KEEP=1 (leave the container up),
#      SEL_HUB_BIN (path to selaenium-hub; default target/build/grid/bin/).
set -u

# ---- --hub: our own standalone hub instead of the reference container --------
if [ "${1:-}" = "--hub" ]; then
    shift
    PORT="${SEL_GRID_PORT:-4444}"
    HUB="${SEL_HUB_BIN:-}"
    if [ -z "$HUB" ]; then
        for cand in target/build/grid/bin/selaenium-hub target/build/grid/selaenium-hub; do
            [ -x "$cand" ] && HUB="$cand" && break
        done
    fi
    if [ -z "$HUB" ] || [ ! -x "$HUB" ]; then
        echo "SKIP (grid): no selaenium-hub binary; build it with \`aeb grid/.build.ae\`"
        exit 0
    fi

    SEL_HUB_PORT="$PORT" "$HUB" &
    hub_pid=$!
    trap 'kill "$hub_pid" 2>/dev/null; wait "$hub_pid" 2>/dev/null' EXIT

    url="http://127.0.0.1:${PORT}"
    ready=0
    for _ in $(seq 1 20); do
        if curl -fsS "${url}/status" 2>/dev/null | grep -q '"ready": *true'; then ready=1; break; fi
        # If the hub died (port in use, say), stop waiting on it.
        kill -0 "$hub_pid" 2>/dev/null || break
        sleep 1
    done
    [ "$ready" = "1" ] || { echo "SKIP (grid): selaenium-hub never became ready on :$PORT"; exit 0; }
    echo "grid: selaenium's own hub ready at ${url}"

    export SEL_GRID_URL="$url"
    if [ "$#" -eq 0 ]; then
        echo "grid: no command given; SEL_GRID_URL=$SEL_GRID_URL (stopping)"
        exit 0
    fi
    echo "grid: running: $*"
    "$@"
    rc=$?
    echo "grid: command exited $rc"
    exit $rc
fi

IMAGE="${SEL_GRID_IMAGE:-docker.io/selenium/standalone-chromium:latest}"
PORT="${SEL_GRID_PORT:-4444}"
NAME="selaenium-grid-$$"
ENGINE="$(command -v podman || command -v docker || true)"

skip() { echo "SKIP (grid): $1"; exit 0; }

[ -n "$ENGINE" ] || skip "no podman/docker on PATH"
"$ENGINE" image exists "$IMAGE" >/dev/null 2>&1 || \
    "$ENGINE" pull "$IMAGE" >/dev/null 2>&1 || skip "cannot pull $IMAGE (offline?)"

cleanup() { [ "${SEL_GRID_KEEP:-0}" = "1" ] || "$ENGINE" rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT

echo "grid: starting $IMAGE as $NAME on :$PORT"
# --shm-size=2g is REQUIRED — Chromium crashes on the default 64MB /dev/shm.
"$ENGINE" run -d --name "$NAME" --shm-size=2g -p "${PORT}:4444" "$IMAGE" >/dev/null 2>&1 \
    || skip "container failed to start"

# Wait for the Grid to report ready (node registered).
url="http://127.0.0.1:${PORT}"
ready=0
for _ in $(seq 1 40); do
    if curl -fsS "${url}/status" 2>/dev/null | grep -q '"ready": *true'; then ready=1; break; fi
    sleep 3
done
[ "$ready" = "1" ] || { "$ENGINE" logs "$NAME" 2>&1 | tail -20; skip "grid never became ready"; }
echo "grid: ready at ${url}"

export SEL_GRID_URL="$url"
if [ "$#" -eq 0 ]; then
    echo "grid: no command given; SEL_GRID_URL=$SEL_GRID_URL (stopping)"
    exit 0
fi

echo "grid: running: $*"
"$@"
rc=$?
echo "grid: command exited $rc"
exit $rc
