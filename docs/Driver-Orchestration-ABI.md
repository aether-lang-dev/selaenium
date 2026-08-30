# Driver-process orchestration in the engine ABI

## Problem

The pure-Aether engine (`libselenium_core.so`) is a **protocol client**: you
hand `aether_sel_embed_open(base_url)` a URL to an *already-running*
chromedriver and it speaks W3C WebDriver over HTTP. It does **not** launch the
driver process.

So every binding that wants a real browser session must, on its own, do the
"driver lifecycle" dance:

1. find the `chromedriver` / `geckodriver` binary (PATH, a cache dir, …),
2. pick a free TCP port,
3. spawn it with `--port=N`,
4. wait until the port accepts connections (readiness),
5. hand the URL to the engine,
6. kill + reap the process at teardown.

Today this is **re-implemented per binding** — Java `ProcessBuilder`, dart
`proc_open`, python `subprocess`, zig's external `run-live.sh`, etc. It is
exactly the duplicated, fiddly, cross-language logic the "thick core, thin
bindings" architecture is meant to absorb (and it is the role Selenium Manager
plays in classic Selenium).

The zig binding made this concrete: Zig 0.16 reworked `std.net`/`std.process`
around a new `Io` interface, so its author punted the spawning to a shell
script rather than track the churn. If the **engine** owns driver spawning,
that churn — and every binding's bespoke spawner — disappears.

## Design goal: be ready for full driver *management*, not just launch

Launching a driver already on `PATH` is the easy 20%. The capability that took
the Selenium team ~a decade to get right — and that Playwright arguably does
better — is driver/browser **management**: detect the installed browser, detect
its version, resolve the *matching* driver version, find it in a cache or
download+cache it (and optionally download a pinned "Chrome for Testing"
browser), all offline-tolerant and proxy-aware. We want to be best-of-all here.

So the ABI is **layered** to separate RESOLUTION from LAUNCH, letting resolution
grow (PATH → cache → download) without ever changing the launch verbs or any
binding:

- **Resolution layer** (grows over time): "which driver binary should I run for
  the browser installed here?" → an absolute path to a correct driver.
- **Launch layer** (stable, implemented first): "spawn *this* binary on a free
  port, wait for readiness, hand back a URL, tear down."

A binding calls `resolve` then `launch`, or the convenience `ensure` that does
both. Early on, `resolve` is just "find on PATH"; later it gains version-match +
download+cache — with zero binding churn.

## Proposal

Add driver orchestration to the engine's append-only `sel_embed_` ABI. Every
primitive is confirmed present in Aether today (composition inside the one `.so`
all bindings share):
- find driver on PATH: `os.run_capture` (`command -v <exe>`)
- free port: `http_server_bind_raw(s,"127.0.0.1",0)` → `http_server_port(s)`
  (getsockname on bind-0; already implemented in `aether_http_server.c`)
- spawn: `os.spawn_proc(prog, argv, env)` → token
- readiness: `tcp_connect_raw("127.0.0.1", port)` in a bounded `sleep(50)` poll
- teardown: `os.kill(token, 15)` + `os.wait(token)` (reap)

### New verbs (append-only; two layers + a convenience)

**Launch layer (implemented first — all primitives confirmed):**
```
// Spawn an EXPLICIT driver binary on a free port, wait until it accepts
// connections (bounded by timeout_ms). Returns an opaque driver handle, or
// null if it never came up. Path is absolute — resolution is the caller's
// (or resolve_driver's) job, keeping launch dumb and stable.
void*  aether_sel_embed_launch_driver(const char* driver_path, int timeout_ms);

// "http://127.0.0.1:<port>" to pass to aether_sel_embed_open(). Caller frees.
char*  aether_sel_embed_driver_url(void* dh);
int    aether_sel_embed_driver_pid(void* dh);          // spawn token (diag)

// Kill + reap the driver process and free the handle. Safe to call once.
void   aether_sel_embed_stop_driver(void* dh);
```

**Resolution layer (grows over time — v1 = PATH lookup only):**
```
// Resolve the driver binary to run for `browser` (e.g. "chrome"). v1: find the
// conventional driver ("chromedriver") on PATH. LATER (no signature change):
// detect the installed browser version, resolve the matching driver version,
// return a cached copy, downloading+caching it (and optionally a pinned
// "Chrome for Testing" browser) if absent. `hint` carries optional policy —
// a pinned version, a cache dir, "offline", a channel — as a small JSON/opts
// string so the surface stays append-only as management grows.
// Returns an absolute driver path (caller frees), or "" if none resolvable.
char*  aether_sel_embed_resolve_driver(const char* browser, const char* hint);
```

**Convenience (what most bindings call):**
```
// resolve_driver(browser,hint) → launch_driver(path,timeout). Returns a driver
// handle or null (→ the binding SKIPs its live test: same "no driver" story).
void*  aether_sel_embed_ensure_driver(const char* browser, const char* hint,
                                      int timeout_ms);
```

### Binding usage (replaces every bespoke spawner)

```c
void* dh = aether_sel_embed_ensure_driver("chrome", "", 10000);
if (!dh) { /* SKIP: no driver resolvable */ return; }
char* url = aether_sel_embed_driver_url(dh);
void* h   = aether_sel_embed_open(url);
/* ... newSession, navigate, … , quit ... */
aether_sel_embed_close(h);
aether_sel_embed_free_string(url);
aether_sel_embed_stop_driver(dh);
```

Every binding's live test collapses to this. Zig stops needing `run-live.sh`
and never touches `std.Io`; the others drop ProcessBuilder/proc_open/subprocess.
And when `resolve_driver` later gains version-match + download+cache, **no
binding changes** — the management capability lands once, in the engine, for all
18 bindings at once (the win Selenium Manager delivers for classic Selenium,
here native to the core).

## Open design points (need decisions)

### 1. Readiness wait — RESOLVED (no upstream ask needed)
Aether has a **builtin** `sleep(ms)` (milliseconds) — registered in the global
symbol table (`compiler/analysis/typechecker.c`), ambient like `println`, used
throughout the stdlib/examples (e.g. `std/http/client/httptest`,
`examples/actors/*`). No import, no `os.sleep_ms` ask. The readiness loop is a
plain bounded poll:

```
elapsed = 0
loop {
    if tcp_connect_ok(host, port) { break }         // std.net.tcp_connect_raw
    if elapsed >= timeout_ms { return null }         // driver never came up
    sleep(50)                                        // builtin, ms
    elapsed = elapsed + 50
}
```

Correct for the **production** launch path too (a real timed wait, not a
CPU-burning busy-spin) — which matters because driver-launch is prod logic,
not test-only.

### 2. Content server for the *live tests* — in the engine too?
The live tests also need a tiny HTTP server serving `/one` + `/two`. That is a
**test fixture**, not production ABI — it must NOT live in the shipped
`sel_embed_` surface. But `std.net.http_server_*` (with `http_server_port` for
the ephemeral port) means the engine *could* offer a **separate test-support**
entry point, so bindings stop hand-rolling a content server too. Options:
- keep a small per-binding content server (status quo), or
- a `sel_testkit_*` surface (separate from `sel_embed_`) serving the fixture
  pages, or
- replace the two-page fixture with a static `file://` page / `data:` URL so no
  server is needed at all.
This is orthogonal to driver orchestration and can follow.

### 3. Handle ownership / multi-driver
The driver handle is independent of the session handle (`sel_embed_open`), so
one process can launch N drivers. Teardown is the caller's responsibility
(`stop_driver`), mirroring `open`/`close`.

## The full capability pipeline (from research) — PURE / NET / FS / PROC

The world-class driver *manager* (Selenium Manager / WebDriverManager territory)
is a 13-step pipeline. Tagging each step by execution kind shows exactly what
belongs in the shared engine vs. an injected host adapter:

| # | Capability | Kind | Home |
|---|-----------|------|------|
| 1 | Normalize browser+platform+arch target | PURE | engine |
| 2 | Locate installed browser binary | FS (probe recipes PURE) | engine calls FS adapter; recipe table is engine data |
| 3 | Detect browser version | PROC + PURE parse | engine |
| 4 | Resolve matching driver version | PURE algorithm + NET for data | **algorithm in engine**, JSON injected |
| 5 | Consult resolution cache (TTL) | FS + PURE TTL logic | TTL logic engine; read/write FS adapter |
| 6 | Query vendor metadata endpoint (CfT/gecko/Edge) | NET | host adapter, bytes → engine |
| 7 | Locate driver in binary cache | FS + PURE path derivation | path derivation engine; existence FS |
| 8 | Download + verify + unpack driver | NET + FS + PURE checksum/format | adapters; format logic engine |
| 9 | (opt) resolve+download pinned browser (CfT) | NET + FS | same shape as 6–8 |
| 10 | Compose launch command | PURE | engine |
| 11 | Launch driver process | PROC | engine |
| 12 | Readiness probe (port/`/status`) | NET loopback + PURE policy | engine |
| 13 | Teardown (kill, reap, unlock) | PROC + FS | engine |

**The PURE + PROC steps (1, 3, 4-alg, 5-TTL, 7-path, 10, 11, 12-policy, 13) are
the engine core — ported once, shared by all 18 bindings.** NET and FS are thin
**injectable adapters** so the core is testable with no network and no disk, and
so offline/proxy/corporate-CA/cache-locking stay at the edge.

### Endpoints the resolution algorithm targets (verified)
- Chrome M115+: `https://googlechromelabs.github.io/chrome-for-testing/` JSON —
  `latest-patch-versions-per-build[-with-downloads].json` (primary: MAJOR.MINOR
  .BUILD → co-versioned chromedriver), falling back to
  `latest-versions-per-milestone[-with-downloads].json` keyed by MAJOR.
- Firefox: geckodriver mapping (Selenium's `geckodriver-support.json`) + GitHub
  releases.
- Edge: `msedgedriver.azureedge.net`.
- Cache root: `~/.cache/selenium` (override `SE_CACHE_PATH`); metadata TTL ~1h
  (browser) / ~1 day (driver).

## Pain points to design OUT (Selenium's decade of scars)

1. **Version skew / browser auto-update race** — system Chrome updates under
   you; the cached mapping goes stale mid-CI → mismatch failure. Make the
   pinned-browser path (CfT) first-class, make TTL/mismatch behavior explicit
   and overridable (not a silent 1h window), and give a real "pin exact driver
   + fall back to previous stable" knob.
2. **Flaky/blocked downloads** (proxy, corporate CA, offline, GitHub rate
   limits) — the #1 real-world failure. NET is an injectable adapter with
   retry+resume+proxy+CA at the host edge; a true offline mode resolves purely
   from cache; a metadata-fetch failure is NEVER fatal when a usable cached
   driver exists.
3. **Cache corruption / parallel-process races** — partial downloads, half-
   unpacked archives, parallel test procs racing the cache dir. Atomic
   write-temp-then-rename, content-addressed cache keyed by verified checksum,
   per-driver file locks, self-healing (detect a bad artifact → re-fetch).
4. **Detection brittleness across OSes** — version-probe commands + install-path
   recipes drift (Snap/Flatpak Chrome, Windows registry variance, macOS
   quarantine). Keep probe recipes as PURE injectable DATA (not hardcoded), and
   always let an explicit user-supplied path short-circuit the whole pipeline.

Bonus: Selenium Manager stops at "return the path" — no launch/readiness/
teardown, so readiness races and orphaned driver processes were each binding's
problem. Our ABI owns PROC too, so 11–13 (launch, readiness w/ backoff,
guaranteed reap) live in the engine and behave identically everywhere.

## Rollout

**Phase A — Launch layer (now, this sweep).** Implement the launch-layer verbs
(`launch_driver` / `driver_url` / `driver_pid` / `stop_driver`) + `ensure_driver`
with `resolve_driver` v1 = PATH lookup, over `os.spawn_proc` +
`http_server`-bind-0 free port + `tcp_connect` readiness + builtin `sleep(ms)`.
Rebuild engine, C smoke test (launch/reach/reap a real chromedriver), retrofit
the bindings' live tests (zig first — deletes `run-live.sh`).

**Phase B — Selenium-Manager → Aether port (separate planned workstream).** See
[Selenium-Manager-Port.md](./Selenium-Manager-Port.md). Grows `resolve_driver`
from PATH-only into the full pipeline (detect → version → match → cache →
download → CfT) with ZERO binding churn. Phased: chrome vertical slice first,
then firefox/edge; NET/FS as injectable adapters; port the Rust `tests/` suite
(cache/offline/proxy/rules) as the correctness net.

**Phase C — content server** (decision 2, deferred).
