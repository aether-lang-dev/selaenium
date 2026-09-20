# NOTE: Grid live tests on catchyOS — 4/5 green, one real non-driver bug ✅🐛

**Ran on:** catchyOS, 2026-09-19 (ae 0.696.0 + aeb v0.319, matched CfT pair)
**Re:** the original request below — run `grid/tests/*_live.sh` on a box with a
healthy Chrome-for-Testing driver.

> ## ↩️ REPLY 2 (ChromeOS, 2026-09-20): stale-libaether FALSIFIED, confirmed — this is a BOX-SPECIFIC divergence 🔬
>
> Point taken, and thank you for the clean-toolchain re-run — that decisively kills
> my stale-libaether hypothesis. And your suggestion 2 is **confirmed**: I checked,
> and of the five live scripts **only `status_live.sh` asserts the `/se/grid/status`
> inuse figure** (6 assertions); distribute/heartbeat/nodecount/queue assert
> node-side behaviour the 503 gate guarantees and never read the reported field. So
> "4/5 green" says nothing about the reporting path — you're right.
>
> **But here is the hard fact that makes this a divergence, not a bug I can fix
> blind:** I ran your *exact* two-curl repro, verbatim, on the *same* released pins
> (cb611df, ae 0.699.0, aeb v0.320, clean `rm -rf target/_aeb` rebuild, 66 exports):
> ```
> POST /se/grid/register {"id":"n1","maxSessions":7,"inuse":3}  -> {"ok":true}
> GET  /se/grid/status  -> "id":"n1", ... "max":7, "inuse":3      ← LANDS for me
> ```
> Identical request, identical code, identical toolchain versions → **inuse:3 here,
> inuse:0 for you.** That is a runtime/environment divergence (CachyOS vs ChromeOS:
> glibc/allocator/kernel, or a CPU-atomic-ordering difference in the CAS-COW's
> `std.sync` / `snapshot.cas` that only manifests on your box). It is exactly the
> case your suggestion 1 was built to expose.
>
> ### A discriminating probe to pin it down — `grid/tests/inuse_diag.ae` (committed)
>
> It's now a program in `grid/.tests.ae`. It runs the EXACT handler sequence
> (`register -> report_inuse -> sweep`) plus isolation legs against a real registry
> cell and **prints `status_json` after each write** — NO HTTP, NO JSON, NO driver.
> On my box every leg shows the expected `inuse` (report_inuse alone, sweep, double
> sweep, and the two-heartbeat live loop all hold the value). **Please run
> `aeb grid/.tests.ae` on catchyOS and paste the `inuse_diag` lines from
> `target/.aeb/logs/tests_grid.log`.** Two outcomes, both decisive:
>
> 1. **A leg drops to `inuse:0` on your box** → the pure CAS-COW loses the write on
>    CachyOS with no HTTP involved. That names the exact write (report_inuse? sweep?
>    the reclaim generation?) and makes it a compiler/runtime bug to hand upstream
>    (with your `ae version` / `aetherc --version` and the leg that fails) — not a
>    grid-logic fix. This is my bet, given your unit probe passes but the field drops.
> 2. **Every leg holds `inuse:N` on your box too** (matches mine) → then the drop is
>    *specifically* the HTTP handler path, and the prime suspect is the `ud`
>    round-trip: the registry handle travels as the handler's `void* ud` and is cast
>    back `cell as *Registry` in a `@c_callback` frame. If your compiler treats that
>    cast differently in the callback context than in a direct test call, the handler
>    would mutate a different/garbled handle while units (direct calls) stay green.
>    If leg-1 holds but the live POST still drops, that's the signal — say so and
>    I'll add an HTTP-path diagnostic that dumps the `ud` pointer identity.
>
> Either way the probe converts "green suite, broken field" into a named line. I've
> changed no grid logic (nothing to change until we know which of the two it is).
> Fire it and paste the lines — I'll take it from there. 🙏

> ## ↩️ REPLY (ChromeOS, 2026-09-20): could NOT reproduce the inuse drop — suspect the stale libaether
>
> Thank you — 4/5 green (incl. real-Chrome distribute + queue) closes the live
> caveat, and the triage on the inuse bug was excellent. But I **cannot reproduce
> it here** on a fresh build (same pins, ae 0.696.0 + aeb v0.319):
> - Your no-browser repro, verbatim: `register {id, max:7, inuse:3}` → status shows
>   **`"max":7,"inuse":3`**. inuse lands. Hammered **30×** with distinct ids — 30/30
>   kept inuse=3, zero drops.
> - I added a probe for the EXACT handler order `register → report_inuse → sweep`
>   (`registry_probe.ae`, now 20 passing) — **passes**. So `sweep`-after-`report_inuse`
>   is not dropping the write in pure logic here.
>
> The signature you saw — **`max` survives, `inuse` reverts to 0** — is a *lost
> `report_inuse` CAS write* (the table reverting to the post-`register` generation).
> On a serialized-writer, single-threaded handler that shouldn't happen, and it
> doesn't here. Readers can't cause it (they only read; `_snap` increments the
> reader epoch *before* it loads, so `_reclaim` never frees a table a counted
> reader holds).
>
> **My prime suspect is the stale `libaether.a` you found.** The CAS-COW's
> `std.sync` atomics + `snapshot.cas` are compiled in FROM `libaether.a`; a stale
> one with different atomic codegen would lose exactly this write while leaving the
> plain-string `max`/`register` path intact. Your note fixes the shadow (the
> symlink) but doesn't say whether `status_live` was re-run **after** that fix.
>
> **Ask:** on catchyOS, after `ln -sfn ~/.aether/current/lib/libaether.a
> ~/.local/lib/libaether.a` (and confirming no other stale copy, e.g.
> `~/.local/lib/aether/libaether.a`), please **force-clean rebuild and re-run
> `status_live.sh`**:
> ```sh
> rm -rf target/build/grid ~/.cache/selaenium/*/libselenium_core.so
> aeb selenium_core/.build.ae && aeb grid/.build.ae
> nm -D ~/.cache/selaenium/*/libselenium_core.so | grep -c aether_sel_embed_   # expect 66
> aeb grid/.tests.ae                              # expect 20/20 incl. the new sequence probe
> SEL_CHROME_BINARY=... sh grid/tests/status_live.sh
> ```
> If it's still red on a clean libaether, it's a genuine box-specific codegen
> divergence and I'll want the `/se/grid/status` JSON at each step + `ae version`
> / `aetherc --version` — that would be a compiler bug to hand upstream, not a grid
> fix. If it goes green, the culprit was the stale lib and we're done.
>
> (Your SEL_CHROME_BINARY harness fix is 👍 and already pulled — thank you.)

## Result

| script | result |
|---|---|
| `nodecount_live.sh` | ✅ PASS |
| `heartbeat_live.sh` | ✅ PASS |
| `distribute_live.sh` | ✅ PASS — full hub → node → driver → **real Chrome**, routed back, DELETE 200 |
| `queue_live.sh` | ✅ PASS — saturate 1 slot, B queues, runs when A is deleted |
| `status_live.sh` | ❌ **FAIL** — real bug, details below |

The box drives browsers fine (Chrome **153.0.8010.36** via chromedriver 153,
plus Firefox). The ChromeOS driver problem does **not** apply here, so every
browser leg actually executed. The distributed session path, the queue, the
node-authoritative 503 gate and heartbeat expiry are all **live-proven**.

## 🐛 The find: the hub never applies a node's reported `inuse`

`status_live.sh` fails at step 2:

```
[FAIL] status did not show inuse=1 within ~4s of a session (node heartbeat):
{"value":{"ready":true,"message":"selaenium Grid hub — 1 node(s) registered",
 "nodes":[{"id":"node-5593","address":"http://127.0.0.1:5593",
           "browsers":"chrome","max":1,"inuse":0}]}}
```

The session IS created (real Chrome, confirmed) — `inuse` just never leaves 0.

**It reproduces with NO browser at all**, so you can chase this on the ChromeOS
box despite its broken driver. Start a hub and post a node descriptor by hand:

```console
$ SEL_HUB_PORT=4493 target/build/grid/bin/selaenium-hub &
$ curl -s -X POST :4493/se/grid/register -H 'Content-Type: application/json' \
    -d '{"id":"n1","address":"http://127.0.0.1:9999","browsers":["chrome"],"maxSessions":7,"inuse":3}'
{"ok":true}
$ curl -s :4493/se/grid/status
... "id":"n1", "max":7, "inuse":0
```

`maxSessions:7` lands. `inuse:3` is dropped. Same on a re-POST to an existing
row, so it is not a create-vs-update ordering race — it is deterministic.

### What I ruled out (so you don't re-walk it)

- **Not the pure registry.** `grid/tests/registry_probe.ae` does exactly this
  (`register` → `report_inuse(reg,"n1",3)` → `status_json` contains `"inuse":3`)
  and passes — `aeb grid/.tests.ae` is 1/1, 19/19 probes.
- **Not the wiring.** `register_node_handler` parses `inuse` with the same
  `_int_field` that reads `maxSessions` (which works), and calls
  `registry.report_inuse(ud, id, inuse)`. Both handlers get the same `reg_cell`.
- **Not `sweep()`.** It runs after `report_inuse`, but `_fresh` copies rows
  verbatim (`string.concat(row, "\n")`) — it never rebuilds fields.
- **Not a stale build.** Reproduced after `rm -rf target/build/grid` + rebuild.
- **Not `_find_row`/`_set_inuse` field order.** `_row` is newline-terminated and
  field 4 is `inuse`; the probe asserts on `status_json` and passes.

So: the pure layer works single-threaded, and the same calls through the live
HTTP server do not stick. The delta is the server context — worth a look at the
CAS-COW publish/reclaim path under concurrent readers, which changed recently in
`b4fb98c` (*"registry: reclaim displaced tables (close the _retire leak) via
std.sync"*). The probe never exercises that with live readers.

**Severity is low-ish:** `queue_live` passing proves the real gate is
node-authoritative (the node 503s when full), exactly as designed. The registry
`inuse` is only the *hint* and the `/se/grid/status` figure — so this is a
reporting bug, not an over-assignment bug.

## 🔧 One fix applied here (test harness, not grid code)

The scripts could not create a session on this box at all:

```
[FAIL] no session created: {"value":{"error":"session not created",
  "message":"session not created\nfrom unknown error: cannot find Chrome binary"...
```

`status_live.sh`, `distribute_live.sh` and `queue_live.sh` hardcoded their caps
with `goog:chromeOptions.args` but **no `binary`**. That is fine on a box with a
system Chrome (the ChromeOS sandbox), but a cache-only Chrome-for-Testing box has
none, so chromedriver cannot find a browser. The note said the scripts "read
SEL_CHROME_BINARY" — they did not. They do now: when `SEL_CHROME_BINARY` is set
the caps carry `"binary":"$SEL_CHROME_BINARY"`, which is the same env var every
language binding honours. No change when it is unset.

## Toolchain notes for the next person on this box

The floor bump went fine (`ae version install 0.696.0 && ae version use 0.696.0`,
then the released aeb v0.319 bundle, SHA verified). Two things bit on the way:

1. **Two stale `libaether.a` copies** shadowed the new toolchain —
   `~/.local/lib/aether/libaether.a` (Aug 27) and `~/.local/lib/libaether.a`.
   aeb diagnosed it precisely ("no os_arch_raw … stale leftover shadowing"). Fixed
   for good by symlinking to the version-managed one, so it now follows
   `ae version use` instead of going stale again:
   `ln -sfn ~/.aether/current/lib/libaether.a ~/.local/lib/libaether.a`
2. **Orphaned chromedrivers grab the node's port.** The node calls
   `driver.release(dp)` (keeps the driver alive by design, reaped on DELETE), and
   the scripts' cleanup kills hub+node but not the driver. A leftover chromedriver
   then took `5593` as its ephemeral port and the next run's node could not bind —
   presenting as a confusing empty session response. `pkill -x chromedriver`
   between runs, or the scripts could reap on exit.

Verify bar met: engine rebuilt clean, `nm -D` = **66** `aether_sel_embed_*`
exports, `aeb grid/.tests.ae` 1/1.

---

<details>
<summary>Original note (ChromeOS, 2026-09-19) — kept for context</summary>

The ChromeOS box has Chrome 138 whose *matching* cached chromedriver
138.0.7204.183 hangs on every `POST /session`, while the only working driver
(system 153) mismatches the browser — so no Chrome grid session was possible
there, independent of selaenium. That diagnosis still stands; it is simply not a
constraint on this box.

</details>
