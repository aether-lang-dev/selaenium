# NOTE: Grid live tests want a real browser — please run them on catchyOS 🚗💨

**To:** whoever's next at a keyboard on **catchyOS** (`ssh paul@192.168.0.160`)
**From:** the ChromeOS sandbox line, 2026-09-19 (ae 0.696.0 + aeb v0.319)
**Re:** the distributed-Grid live tests — `grid/tests/{status,queue,distribute,heartbeat}_live.sh`

## TL;DR

The distributed Grid is **built, unit-green, and its logic is live-proven** on the
ChromeOS box. The one thing that box **cannot** do is complete a real Chrome
session — its Chrome-for-Testing chromedriver is a broken build (details below).
So the browser-round-trip legs of the `*_live.sh` scripts can't go green here.
**catchyOS has a healthy CfT 152 pair** — please run them there and confirm green.
It should be a 10-minute copy/paste.

## Why not here (root-caused, not hand-waved)

This sandbox has **Chrome 138.0.7204.49** and drivermgr correctly resolves the
*matching* **chromedriver 138.0.7204.183** — the right pairing. But that cached
138 driver **hangs on every `POST /session`**, standalone, outside the grid
entirely:

```
$ ~/.cache/selenium/chromedriver/linux64/138.0.7204.183/chromedriver --port=49998 &
$ curl --max-time 40 -X POST :49998/session -d '{...--headless=new...}'
  → 40s timeout, empty body.  Driver log says "started successfully", then silence.
```

Meanwhile the *system* `/usr/bin/chromedriver` (153) creates a session in **1s** —
but it's 153 against Chrome 138, the wrong pairing. So: the only *working* driver
mismatches the browser, and the *matching* driver is a broken CfT build. **No
working Chrome grid session is possible on this box, independent of selaenium.**
(This is the precise cause behind the long-standing "live tests flake in the
headless env" note — it was never flake, it's a bad cached driver.)

The grid code is **faithfully proxying to a driver that never answers** — proven
by bisecting hub→node→driver: a POST straight to the node hangs identically, and
the node's log shows it *did* spawn the driver fine. Nothing above the driver is
at fault.

## What IS proven here (so you know what you're confirming, not discovering)

- **503 slot gate** (step 4b, node-authoritative): at capacity the node returns
  `{"error":"session not created","message":"node has no free slot"}` — confirmed
  live by hand.
- **Node-reported `inuse`**: `/se/grid/status` shows `inuse` 0→1 across a session
  via the node's heartbeat — confirmed live; the pure step-1 contract passes 3/3.
- **Unit**: `registry_probe` 19/19 (incl. the abandoned-session-frees path),
  `registry_stress` clean under repetition.

The live scripts self-skip the browser legs when chromedriver is absent, so what's
missing is specifically the **completed-session** assertions (status inuse=1 after
a real distribute; the queue unblocking when a real slot frees). Those need a
driver that actually drives.

## Toolchain floor — check this FIRST ⚙️

These tests build against the current pins (`ci/versions.env`), and the repo has a
hard floor:

| pin | value | why |
|---|---|---|
| `AETHER_REF` / `AETHER_FLOOR` | **ae 0.696.0** | aeb v0.319's `AETHER_PIN` is 0.696.0; the engine's own strict need is still only 0.681's `os.arch()`, but the floor tracks the aeb toolchain requirement |
| `AEB_REF` | **aeb v0.319** | coupled with ae 0.696.0 (its `AETHER_PIN`) |

⚠️ **catchyOS may be BELOW the floor** — the two-box workflow note last recorded
**ae 0.613** there, which pre-dates the 0.696 floor by a mile. Bump it before
building, and mind the ae/aetherc version-skew trap:

```sh
ae version install 0.696.0 && ae version use 0.696.0   # flips BOTH ae and aetherc
ae version 2>/dev/null; aetherc --version 2>/dev/null    # both must read 0.696.0 — no skew
# aeb: install the RELEASED v0.319 bundle (SHA-checked), not a dev build:
#   BASE=https://github.com/aether-lang-dev/aeb/releases/download/v0.319
#   curl -fsSL -O $BASE/aeb-linux-x86_64.tar.gz -O $BASE/aeb-linux-x86_64.tar.gz.sha256
#   sha256sum -c aeb-linux-x86_64.tar.gz.sha256 && tar xzf aeb-linux-x86_64.tar.gz
#   ./aeb-linux-x86_64/install.sh
aeb --version    # → aeb v0.319
```

Verify bar (same as any bump): engine rebuilds clean and `nm -D` shows **66**
`aether_sel_embed_*` exports; `aeb grid/.tests.ae` → grid 1/1. Then the live legs.

## How to run on catchyOS (the healthy box)

catchyOS has cache-only **Chrome-for-Testing 152** (no system Chrome), so the node
must be pointed at the CfT binary, and drivermgr must land on the matching 152
driver. Setup (from the two-box workflow):

```sh
ssh paul@192.168.0.160
cd ~/scm/selenium
git pull --ff-only origin main            # get 74c4cbf (4b) + 2db0eb4 (0.696) + this note
export PATH="$HOME/.aether/bin:$HOME/scm/aeb:$PATH"   # ae + aeb not on login PATH
export SEL_CHROME_BINARY="$HOME/.cache/selenium/chrome/linux64/152.0.7977.64/chrome"
# (do the toolchain-floor bump above first if ae/aeb are older)

aeb grid/.build.ae                         # build hub + node
# then each live script — they read SEL_CHROME_BINARY for the CfT Chrome:
sh grid/tests/status_live.sh               # inuse 0 → 1 (heartbeat) → 0
sh grid/tests/queue_live.sh                # saturate 1 slot, 2nd session QUEUES, unblocks on DELETE
sh grid/tests/distribute_live.sh           # hub routes newSession to the node
sh grid/tests/heartbeat_live.sh            # stale-node expiry after missed heartbeats
```

### Two things to watch

1. **`status_live` timing** — I updated it this session: `inuse` is now
   **node-authoritative** (reported via heartbeat, `SEL_NODE_HEARTBEAT=800`), not
   incremented by the hub at assign time. The script already **polls** for
   `inuse:1`/`inuse:0` (up to ~4s) instead of reading once — so the small
   report-lag is expected and handled. If it fails, capture the `st()` JSON it
   prints on `[FAIL]`.
2. **Driver resolution** — if the node still spawns a mismatched driver, check
   what `driver.ensure("chrome", ...)` resolves to on that box (drivermgr detects
   the CfT Chrome via `SEL_CHROME_BINARY` and should pick the cached 152 driver).
   The healthy pairing is chromedriver **152.0.7977.64** ↔ CfT Chrome **152**.

## Plan B (bulletproof): point the node at a podman `standalone-chromium` 🐋

catchyOS has **podman** — which sidesteps the whole cache-driver-resolution
question. Run a container whose Chrome + chromedriver are guaranteed-matched, and
point a selaenium **node** at it as its upstream W3C endpoint. That removes the one
variable that bit this sandbox: the driver *always* answers.

```sh
# a matched W3C endpoint on :4444, no host Chrome/driver involved
podman run -d --rm --name se-chromium -p 4455:4444 --shm-size=2g \
  docker.io/selenium/standalone-chromium:latest
# (podman pulls docker.io/... transparently; :latest ships a matched pair)
```

Two ways to use it, pick per what you're proving:

- **Fastest sanity check** — curl a session straight at the container to confirm
  the *box* can drive a browser at all (isolates selaenium from the driver):
  ```sh
  curl --max-time 30 -X POST :4455/session \
    -H 'Content-Type: application/json' \
    -d '{"capabilities":{"alwaysMatch":{"browserName":"chrome"}}}'
  # → a sessionId in ~1-2s means the container is healthy; then run the scripts.
  ```
- **True end-to-end through the grid** — if we want the `*_live.sh` scripts to
  drive the *container's* driver rather than a host one, the node's driver layer
  currently PATH/cache-resolves a local chromedriver (`driver.ensure`), so it
  won't proxy to an arbitrary remote endpoint out of the box. That's the seam a
  small `SEL_NODE_DRIVER_URL`-style override would open (a **new feature**, out of
  4b's scope — flag it back to me and I'll add it on the next ChromeOS pass if we
  want container-backed live tests to be first-class). For *now*, the container is
  the clean way to prove "this box CAN complete a session," and the cached CfT 152
  pair (above) is the way to run the scripts as-written.

Either path beats the broken 138 driver on ChromeOS. If even the podman
`standalone-chromium` session hangs on catchyOS, that's a genuinely surprising
box-level find worth writing up here.

## If they go green

Drop a one-line ✅ in this file (or delete it) and the step-4b live caveat is
closed. If a browser leg fails for a *non-driver* reason, that's a real find —
leave the `[FAIL]` JSON here and I'll pick it up on the next ChromeOS pass.

Thanks — the plumbing's all there, it just needs a browser that breathes. 🌬️
