# docs

Design notes for the Selenium-on-Aether port.

- **[Architecture](./Architecture.md)** — what the repo is: one pure-Aether
  engine + 18 thin FFI bindings, aeb not Bazel, why a reboot rather than a
  migration, and the remaining capability gaps vs classic.
- **[WebDriver-BiDi](./WebDriver-BiDi.md)** — design note for the BiDi layer
  (the persistent-WebSocket, event-driven protocol). Transport + model proven
  live (`selenium_core/bidi_probe.ae`); the engine-layer + ABI plan awaits
  review — the open question is async events over a synchronous FFI.

## WASM binding — three parked directions

The pure-Aether engine can compile to `wasm32` and run in a browser tab. Because
the engine already separates *building* a WebDriver request from *sending* it
(`sel_embed_build_request` and the pure `route`/`by_locator`/`error_code`
helpers are exported; only the `std.http.client` round-trip is browser-forbidden),
the transport becomes a swappable JS shim — and *what you plug in* is the whole
design space. Three shapes, all inheriting the Selenium-RC lineage, none chosen
yet:

- **[In-Page Remote Driver](./In-Page_Remote_Driver.md)** — WASM brain, JS-shim
  transport (`fetch` / WebSocket-BiDi) to a real remote browser. *RC-over-BiDi.*
- **[Same-Origin DOM Driver](./Same-Origin_DOM_Driver.md)** — WASM brain drives
  the hosting page's own `document` directly. *Selenium 1.0, with the real brain.*
- **[Embedded Test Runtime](./Embedded_Test_Runtime.md)** — WASM hosts a 3GL
  (Lua / QuickJS / Aether) so the test script runs *inside* the browser.
  *RC done right — control flow local, only actions cross the wire.*

Parked pending a decision; see each note for the smallest proof if picked.
