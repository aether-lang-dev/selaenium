# In-Page Remote Driver

*A WASM design sketch — parked, not chosen. One of three (see also
[Same-Origin DOM Driver](./Same-Origin_DOM_Driver.md) and
[Embedded Test Runtime](./Embedded_Test_Runtime.md)).*

## One line

Compile the pure-Aether engine to `wasm32`, run it inside a browser tab, and let
a thin JS shim carry each command to a **real remote browser** over `fetch()` or
a WebSocket — the protocol brain in the page, the transport in JavaScript.

## The lineage

Selenium-RC (2005) split the driving intelligence from the browser: your
Ruby/Java process held the logic, and COMET carried commands into the browser it
steered. The browser side and the driver side were two separate
implementations, and they drifted — a locator fixed server-side could still be
wrong in the injected JS core.

This is that split done without the drift. The intelligence — the W3C command
map, path templating, `By` normalization, request construction, response and
error decoding — is the *same* `selenium_core` engine that backs all eighteen
native bindings, just recompiled to WebAssembly instead of a `.so`. Only the
transport is new, and the transport is the one part that was never protocol
logic to begin with.

## Why it works: the engine already has the seam

`selenium_core/embed.ae` exposes the round-trip as two separable halves:

- **Pure request construction** — `sel_embed_build_request(name, session_id,
  params_json)` returns the concrete `"METHOD PATH\nbody"` for a command
  *without sending it*. Plus `sel_embed_route`, `sel_embed_by_locator`,
  `sel_embed_error_code` — all pure, all already exported.
- **The actual send** — the native `execute()` path calls `http_roundtrip(...)`
  over `std.http.client`, which a browser sandbox forbids.

A browser WASM build simply doesn't use the second half. The JS shim becomes the
transport:

```
WASM engine                         JS shim (the transport)
-----------                         -----------------------
build_request("findElement", …) ──▶ { method:"POST",
                                       path:"/session/…/element",
                                       body:'{"using":"css selector",…}' }
                                          │
                                          ▼  fetch() / WebSocket
                                    remote WebDriver / Grid / BiDi
                                          │
decode(responseBody)          ◀────── response JSON
```

## The two transports the shim can offer

1. **`fetch()` to a WebDriver endpoint.** Same-origin, or a CORS-enabled Grid, or
   a same-origin reverse proxy in front of chromedriver. The classic W3C
   HTTP-JSON protocol, issued from in-page code, byte-identical to what the Java
   binding sends.
2. **WebSocket to WebDriver-BiDi.** BiDi is bidirectional and event-driven —
   exactly what RC faked with COMET, now a W3C standard. A WASM brain speaking
   BiDi over a WebSocket is the RC channel reborn: subscribe to DOM/network
   events, stream them back, no polling. This is the sharpest fit for the whole
   idea.

## What you get

- A real WebDriver client that lives in a web page and steers a real (remote)
  browser — a dashboard that runs a smoke test on click, a self-testing web app,
  an in-page automation console.
- Zero protocol drift: the in-page controller and every server-side binding run
  the identical engine.

## The honest cost

- **Async impedance.** `execute()` is synchronous; `fetch`/WebSocket are
  promises. Bridging needs an async ABI variant, Emscripten Asyncify, or running
  the WASM brain in a Worker with synchronous message passing. This is the real
  engineering — the same sync/async mismatch the Node and Dart bindings already
  navigate, one layer deeper.
- **CORS / reachability.** `fetch()` can only reach a same-origin or
  CORS-permitting endpoint; chromedriver is neither by default, so a proxy or a
  BiDi WebSocket is usually required.
- **Bundle size.** ~60–85 KB of `.wasm` plus JS glue — fine for a tool, heavy
  for a product page.

## Status

Parked. If picked, the smallest proof is: WASM engine + a `fetch`-based shim
doing `build_request` → same-origin WebDriver → `decode`, driving one real
`newSession`/`get`/`findElement`/`click`/`quit`.
