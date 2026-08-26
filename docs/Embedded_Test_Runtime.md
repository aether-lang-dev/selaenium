# Embedded Test Runtime

*A WASM design sketch — parked, not chosen. One of three (see also
[In-Page Remote Driver](./In-Page_Remote_Driver.md) and
[Same-Origin DOM Driver](./Same-Origin_DOM_Driver.md)). The most ambitious of
the three, and the closest to "Selenium-RC done right".*

## One line

Ship the WASM engine **with a small embedded language runtime beside it**, so the
test script itself runs *inside the browser* — the author writes
`driver.get(…); driver.findElement(…).click()` in Lua (or QuickJS, Wren, or
Aether-to-WASM), and it executes in the page at WASM speed, only touching the
wire when it actually acts on the browser.

## The lineage, and why this is the RC insight completed

Selenium-RC put the script server-side and shipped commands *to* the browser one
COMET frame at a time. Every step of control flow — every `if`, every loop
iteration, every assertion — was a network round-trip away from the browser it
drove. A thousand-assertion test paid a thousand latencies, because the *brain*
and the *browser* were on opposite ends of a wire.

Invert it. Put the script **in** the browser, next to the engine:

- The **control flow** (loops, conditionals, the test's own logic) runs locally
  in the embedded interpreter — zero round-trips.
- Only the **browser actions** (`get`, `click`, `findElement`) cross a boundary,
  and even that boundary can be any of the three transports (remote WebDriver,
  BiDi WebSocket, or the same-origin DOM adapter from the sibling sketches).

RC couldn't do this because in 2005 there was no way to run a real 3GL in the
page. WASM is exactly that missing piece.

## How it composes

```
   ┌────────────────────── browser tab (WASM) ──────────────────────┐
   │                                                                 │
   │   embedded 3GL runtime         selenium_core engine             │
   │   (Lua / QuickJS / Wren / …)   (the shared protocol brain)      │
   │        │                              │                         │
   │   test.lua:                     build_request / by_locator /    │
   │     for i=1,1000 do  ◀── runs    route / decode  (all pure,     │
   │       el=drv:find(...)   here     already exported)             │
   │       el:click()  ──────────────▶ one command ──▶ transport ────┼──▶ browser
   │       assert(...)  ◀── runs here                                 │
   │     end                                                         │
   └─────────────────────────────────────────────────────────────────┘
```

The 3GL calls a tiny host binding (`drv:find`, `el:click`) that turns each call
into a `selenium_core` command; the engine builds the request and decodes the
response; the transport (pluggable) does the one hop to the actual browser.

## Which 3GL

- **Lua** is the natural first pick — small, embeddable, well-understood as a
  test/config language, and *we already have a Lua binding* whose surface
  (`WebDriver`, `WebElement`, `By`) could be reused almost verbatim, just wired
  to the WASM engine instead of a `.so`.
- **QuickJS** if authors want to write tests in JavaScript that nonetheless run
  through the shared engine (not the host page's JS).
- **Aether-compiled-to-WASM** is the purest option: the test language and the
  engine language are one, and the whole thing is a single toolchain.

## What it unlocks

- **Fast in-browser test suites** — the tight loop of a test doesn't pay network
  latency per step; it runs at interpreter speed and only serializes real
  actions.
- **Self-contained, shippable tests** — a `.wasm` + a `.lua` is a complete,
  driver-less test artifact you can drop into a page, a CI browser job, or a bug
  report ("here is the failing scenario, it runs itself").
- **Record / replay** — with a stub transport, the same bundle becomes an offline
  W3C conformance oracle: feed recorded responses, assert the requests the script
  would emit. Servirtium-style VCR, client-side.
- One brain, every layer: the in-page script, the embedded engine, and every
  native binding all speak the identical protocol — no drift anywhere.

## The honest cost

- **Biggest bundle of the three** — engine (~60–85 KB) *plus* an interpreter.
  Acceptable for a test tool, not for a product page.
- **Two host bindings to maintain** — the 3GL↔engine glue is a real surface, on
  top of the WASM build itself.
- **Async still bites at the boundary** — the browser actions are async even if
  the control flow is local; the interpreter needs a way to await them
  (coroutines/Asyncify), which is the same sync/async note as the other sketches,
  concentrated at the action calls.
- **Scope discipline** — this is a platform, not a binding. It is the highest-
  value and highest-effort of the three; it should only be picked as a
  deliberate product direction, not as "one more language".

## Status

Parked — deliberately, as the most ambitious option. If ever picked, stage it:
first the [In-Page Remote Driver](./In-Page_Remote_Driver.md) transport, then
Lua-in-WASM calling it, then the record/replay stub. Each stage is useful on its
own.
