# Architecture — the Aether reboot

Selenium-WebDriver, rebooted as **one pure-Aether engine + thin per-language
bindings**, built with **aeb** (not Bazel). This note is the map of what the repo
*is*; the [top-level README](../README.md) has the binding matrix and the live
status.

## The shape

```
selenium_core/          ONE engine, pure Aether — the whole protocol brain
  selenium_core.ae        143 W3C routes, path templating, By/capabilities
                          normalization, W3C error decode, the std.http.client
                          round-trip to the driver/Grid
  embed.ae                the flat C ABI (aether_sel_embed_*), handle-based
  _embed_strdup.c         ~15 lines: the caller-owned-string bridge (the only C)
  .build.ae               aeb node → selenium_core/native/libselenium_core.so
  tests/probe.ae          pure-Aether engine probe (no browser, no FFI)

<lang>/                  18 thin bindings, each re-gluing to the ONE .so over that
                        language's FFI (see the README matrix). No protocol logic.

aether/                 reserved for the Aether-LANGUAGE client (stub for now)
.presubmit.ae           aeb aggregator; run `aeb .presubmit.ae` from the repo root
docs/                   this note + the parked WASM design sketches
```

**The one rule:** bindings carry no protocol logic. Everything a binding used to
reimplement lives once in `selenium_core/`, reached over the `aether_sel_embed_*`
ABI. A binding opens a session, issues commands by name with JSON params, reads
back the value or a typed error, and closes.

## Why a reboot, not a Bazel→aeb migration

The original plan was to migrate the inherited classic Selenium tree (307
`BUILD.bazel`, 75 custom `.bzl` macros, 227 Closure atom targets, spec-driven
BiDi/CDP codegen, Maven/NuGet/PyPI publishing, the Grid) tree-by-tree into aeb.
That is a multi-month reimplementation of build *logic*, most of it not in the
BUILD files but in the macros.

We chose the cleaner path instead: **a from-scratch reboot.** The engine
reimplements the W3C protocol once in Aether (ported from
`javascript/selenium-webdriver/lib/{command,http,error,by}.js`); every binding is
a fresh, thin FFI layer. Classic Selenium and all its Bazel/Rake/pnpm tooling
were removed from `main` and preserved on the **`classic-selenium`** branch for
reference. `main` has **zero Bazel files** — the "no Bazel" goal is met by
deletion + reconstruction, not by translation.

Two bindings (Rust, Ruby) were briefly migrated off the classic Bazel tree before
that pivot; that work is superseded by the reboot and lives only in git history.

## Toolchain divergence from classic (intentional)

- **aeb selects toolchains from `PATH`**, where Bazel pinned hermetic ones. A
  documented, accepted trade: reproducibility for simplicity. Bindings whose
  toolchain is too old on a given box **skip loudly** rather than fail (e.g. a
  JDK/kotlinc/groovy/ruby below the required version), and are verified on a box
  that has it (`catchyos`, `192.168.0.160`, carries the newer toolchains + GHC via
  ghcup).
- **aeb feature gaps** are driven upstream via a note to the aeb-maintaining
  sibling (`~/scm/aeb/selenium-porting-needs-for-aeb.md`), not hacked locally.

## What the reboot does NOT yet have (vs classic)

These are genuine capability gaps, not residue — tracked as the remaining
"perfect reboot" work:

- **Selenium Manager** — classic auto-downloads the right driver; our bindings
  assume a driver is already running.
- **WebDriver-BiDi** — the engine is W3C-classic-HTTP only; no BiDi (WebSocket,
  event-driven) surface yet. See the parked WASM sketches in this dir for where
  BiDi would tie in.
- **Grid** — the distributed server; out of scope for a client reboot unless
  explicitly revisited.
- **Publish** — bindings build + test, but there is no `pip`/gem/npm/NuGet/Maven
  publish story (aeb's publish side is itself a TODO upstream).
- **CI** — GitHub Actions still to be rebuilt around `aeb .presubmit.ae`.

## Cross-compiled release — the engine `.so`/`.dylib` (three tiers)

The engine cross-compiles: `ae build --target=aarch64-macos --emit=lib` produces
a real Mach-O arm64 dylib **from a Linux runner** — no macOS host needed for the
*build*. What differs per target is the TLS story, and it splits cleanly:

- **Tier 1 — local driver over `http://`: works cross-built, no work.** Plaintext
  reaches the network layer in a `--target` build (fails "connection refused",
  not "no OpenSSL"). This is the normal case (driving a local
  chromedriver/geckodriver), so a cross-built macOS/any-platform `.so` is usable
  today for local automation.
- **Tier 2 — remote Grid over `https://`: ~25 contained lines.** `std.http.client`
  HTTPS is OpenSSL, which zig cross-builds omit — but the pure-Aether
  `std.cryptography.tls13_client` links with zero native deps and cross-builds
  clean (verified). Frame HTTP over its `conn_send`/`conn_recv`; lift
  `aether/tests/integration/https_pure_tls_vertical/client.ae`. Keep it behind a
  narrow `https_get`/`https_post -> (body, err)` seam so it's deletable when
  Aether wires pure-TLS under `std.http.client` (ask filed:
  `aether/asks/http-client-pure-tls-backend-for-crossbuild.md`). Gotchas: set
  `SSL_CERT_FILE`; pass `std.bytes` handles, never `bytes.data(b)` (raw ptr
  segfaults); IP-SAN verification needs ae ≥ 0.603.0.
- **BiDi needs none of the above** — the WebSocket client already speaks `wss://`,
  so the (future, per Simon) BiDi transport is TLS-covered with no tls13_client
  work.

So a single Linux runner can cross-build the platform matrix now; only the
classic HTTPS-Grid path wants the small Tier-2 helper. Pairs with the
SHA256-per-artifact + out-of-band on-target attestation model (a homelab runs the
suite on real hardware and attests a specific hash passed).
