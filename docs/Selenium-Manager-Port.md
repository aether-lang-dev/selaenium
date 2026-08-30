# Porting Selenium Manager to Aether

A phased plan to re-home the driver/browser **management** capability — the
thing Selenium's team took ~a decade to get right, and that Playwright arguably
does better — from the upstream Rust `selenium-manager` into the pure-Aether
engine, so all 18 bindings get it natively over the flat C ABI (no separate
binary to shell out to).

This is **Phase B** of [Driver-Orchestration-ABI.md](./Driver-Orchestration-ABI.md).
Phase A (launch/readiness/teardown) ships first and independently; this port
grows `sel_embed_resolve_driver` from "find on PATH" into the full pipeline
with **zero binding churn**.

## Source of truth

The complete Rust source is on the `classic-selenium` branch: `rust/src/*.rs`
(~8,900 LOC, 44 files) + `rust/tests/*.rs` (the correctness suite). Key modules:

| Rust module | LOC | Concern | Port target |
|-------------|-----|---------|-------------|
| `lib.rs` | 2040 | orchestration, the `SeleniumManager` trait, shared flow | engine core flow |
| `chrome.rs` | 700 | Chrome detect + CfT resolution | `driver/chrome.ae` |
| `firefox.rs` | 807 | Firefox detect + geckodriver mapping | `driver/firefox.ae` |
| `edge.rs` | 652 | Edge detect + msedgedriver | `driver/edge.ae` |
| `files.rs` | 943 | cache paths, unpack, fs ops | FS adapter + PURE path logic |
| `config.rs` | 387 | precedence: CLI > toml > SE_* env | PURE config resolver |
| `metadata.rs` | 267 | `se-metadata.json` TTL cache | PURE TTL + FS adapter |
| `downloads.rs` | 113 | fetch archives | NET adapter |
| `lock.rs` | 151 | cache file locking | FS adapter (os primitives) |
| `rules.rs` | 51 | version-match rules | PURE |
| `mirror.rs` | 32 | mirror/CfT endpoint URLs | PURE data |
| `shell.rs` | 73 | run detection commands | PROC (`os.run_capture`) |

We **port the algorithm, not transliterate** — most of this is PURE logic
(version rules, path/cache derivation, JSON parsing of endpoint responses),
which Aether does cleanly, with a thin I/O edge.

## Two faces: flat C ABI + a beautiful Aether builder-DSL

The driver manager has TWO end-user surfaces over the SAME pure core:

1. **Flat `sel_embed_*` C ABI** — for the 18 FFI bindings (ctypes/Fiddle/koffi/
   Panama/…). Scalar-only, append-only, string-ownership convention. Unchanged
   from the Phase-A shape (`resolve_driver`/`ensure_driver`/…).

2. **A native Aether builder-DSL** — for the pure-Aether consumer and the future
   Aether-language Selenium client. This is where we bring the "DSL with scope"
   beauty (aether/docs/closures-and-builder-dsl.md — the Smalltalk→Ruby→Groovy→
   SwiftUI lineage), the same `builder func(){…}` mechanism aeb's own build
   grammar uses. Target shape:

   ```aether
   import webdriver

   driver = webdriver.chrome() {          // builder func: block fills config
       version("stable")                  // or pin "152.0.7977.64"
       cache("~/.cache/selenium")         // override cache root
       offline()                          // resolve from cache only
       on_progress callback |pct| {       // download progress closure
           println("downloading… ${pct}%")
       }
   }                                      // → resolves + launches, returns a handle
   // … use driver …
   driver.stop()
   ```

   `webdriver.chrome()` is a `builder` function: the trailing block fills a
   config (via `version`/`cache`/`offline`/`on_progress` setters on the injected
   `_builder`), then the function runs the resolve→launch pipeline and returns a
   driver handle. `on_progress` is a `callback` closure (real download progress).
   The C ABI verbs are the same pipeline with the config passed as scalars/JSON
   `hint` instead of a block.

   This keeps the FFI bindings flat and the Aether surface delightful — one core,
   two faces. The builder-DSL face is authored alongside B1 so the shape is
   proven early (even if only `version`/`cache`/`offline` are wired first).

## Architecture: PURE core + injected adapters

The research pipeline (13 capabilities) splits by execution kind. The **PURE +
PROC** steps become the engine core; **NET + FS** become injectable adapters so
the core is unit-testable with no network and no disk — the single most
important structural decision, because it's what makes offline/proxy/cache-race
correctness tractable and testable.

```
resolve_driver(browser, hint)
  ├─ normalize target                         [PURE]   engine
  ├─ detect browser + version                 [PROC]   os.run_capture + PURE parse
  ├─ cache lookup (se-metadata TTL)           [FS+PURE] FS adapter + PURE TTL
  ├─ resolve driver version                   [PURE]   algorithm in engine…
  │    └─ vendor metadata (CfT/gecko/Edge)    [NET]    …JSON injected by adapter
  ├─ binary cache lookup (version→path)       [FS+PURE] PURE path + FS existence
  └─ download + verify + unpack if missing    [NET+FS+PURE] adapters; format PURE
        └─ (opt) pinned browser (CfT)          [NET+FS]  same shape
```

Adapters are a tiny interface the engine calls (and tests fake):
- **NET**: `http_get(url) -> (bytes, status, err)` — backed by `std.http.client`;
  retry/resume/proxy/CA live here, at the edge.
- **FS**: read/write/exists/atomic-rename/unpack — backed by `std.fs`; atomic
  write-temp-then-rename + per-driver locks live here.
- **PROC**: version detection + (Phase A) launch — `os.run_capture`/`spawn_proc`.

## Design-out list (baked in from day one)

1. Version skew → first-class pinned-browser (CfT) path; explicit overridable
   TTL/mismatch; "pin exact + fall back to previous stable" knob.
2. Flaky downloads → NET adapter with retry/resume/proxy/CA; true offline mode
   (resolve from cache only); metadata-fetch failure never fatal if cache usable.
3. Cache corruption/races → atomic temp+rename, content-addressed cache by
   verified checksum, per-driver locks, self-heal (bad artifact → re-fetch).
4. Detection brittleness → probe recipes as PURE injectable DATA; explicit
   user-supplied path always short-circuits the pipeline.

## Phased milestones

- **B0 — skeleton + adapters.** Define the NET/FS adapter seam + the
  `resolve_driver` flow shell in the engine; a fake NET/FS for tests. No real
  resolution yet — just the injectable structure.
- **B1 — Chrome vertical slice.** Port `chrome.rs` + the CfT rule
  (`latest-patch-versions-per-build` → milestone fallback) + `rules.rs` +
  `metadata.rs` TTL + `files.rs` path/unpack. Prove: detect system Chrome →
  resolve chromedriver version → cache/download → hand path to Phase A launch.
  Port `rust/tests/{cache,rules,offline}_tests.rs` as the net.
- **B2 — Firefox + Edge.** Port `firefox.rs` (geckodriver mapping + GitHub
  releases) and `edge.rs`. Port their test files.
- **B3 — pinned browser download (CfT/Firefox/Edge).** Capability 9 — hermetic
  browser install, the Playwright-grade determinism story.
- **B4 — config + proxy + offline hardening.** Port `config.rs` precedence
  (CLI > toml > SE_*), `SE_PROXY`, `--offline`, corporate-CA; port
  `proxy_tests.rs` / `offline_tests.rs`.
- **B5 — engine ABI surface + binding ergonomics.** Finalize the append-only
  `sel_embed_resolve_*` verbs and any hint/opts JSON; document the binding-side
  one-liner.

Each B-milestone lands `resolve_driver` capability with **no change to any
binding** — the whole point of the Phase-A layering.

## Aether-primitive mapping (confirmed available)

- HTTP fetch: `std.http.client` (engine already uses it for the WebDriver
  round-trip).
- Filesystem/cache: `std.fs` (atomic write helpers exist — see
  `aether_fs.c` `fs_write_atomic_raw`).
- Process/detection: `os.run_capture`, `os.spawn_proc`, `os.kill`, `os.wait`.
- Free port / readiness: `http_server` bind-0 + `http_server_port`;
  `tcp_connect_raw`; builtin `sleep(ms)`.
- JSON: engine already parses/builds JSON for the protocol layer.

Nothing here needs a new Aether primitive — it's composition inside the one
`.so` all bindings share.
