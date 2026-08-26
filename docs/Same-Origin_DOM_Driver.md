# Same-Origin DOM Driver

*A WASM design sketch — parked, not chosen. One of three (see also
[In-Page Remote Driver](./In-Page_Remote_Driver.md) and
[Embedded Test Runtime](./Embedded_Test_Runtime.md)).*

## One line

Compile the pure-Aether engine to `wasm32`, run it in the page, and point its
transport callback not at a network endpoint but at a JS shim that **executes
each command against the hosting page's own `document`** — Selenium 1.0's
same-origin DOM driving, with the real W3C brain behind it.

## The lineage

Selenium 1.0 ("Selenium Core") injected a bundle of JavaScript into the page and
drove the DOM directly, same-origin: `click`, `type`, `select`, locator
strategies — all implemented in that injected JS. It was fast and needed no
driver process, but the command semantics were a bespoke JS reimplementation:
its own locator quirks, its own error behavior, forever diverging from what the
"real" drivers did.

This is that same in-page, no-driver, same-origin model — but the *semantics*
come from the shared `selenium_core` engine instead of a hand-written JS core.
You get Selenium Core's immediacy with the W3C protocol's correctness.

## How it works

The engine turns a call like `findElement(By.ID, "submit")` into a normalized
command; the transport callback, instead of sending HTTP, dispatches it to a JS
shim that maps W3C commands onto DOM operations in the current document:

```
WASM engine                       JS shim (the DOM adapter)
-----------                       -------------------------
by_locator("id","submit")   ──▶   {"using":"css selector","value":"*[id='submit']"}
route/build "findElement"   ──▶   document.querySelector("*[id='submit']")
        "clickElement"      ──▶   el.click()
        "getElementText"    ──▶   el.textContent
        "executeScript"     ──▶   Function(script)(…args)
        "getElementRect"    ──▶   el.getBoundingClientRect()
```

`sel_embed_by_locator` already produces the exact `{using, value}` the native
bindings use, so the shim's `querySelector` sees the same locator every other
binding would — the `By.ID → *[id='…']` rewrite, xpath, css, etc., all shared.
The W3C error taxonomy (`no such element`, `stale element reference`, …) is
decoded by the engine's `error_code`/`response_error_code`, so the shim reports
failures the same way a driver would.

## Where it's actually useful

- Driving **in-page content** you already control: an embedded app, an iframe, a
  design-system playground, a test harness that lives in the page it exercises.
- **Browser-extension content scripts** that need to poke the DOM with real
  WebDriver semantics but have no driver and no network round-trip.
- Teaching / demos: "here is what `findElement` *means*" running live, with no
  chromedriver to install.

## What it cannot be

Not a general WebDriver client. It only reaches the DOM the page can already
touch:

- **Same-origin only** — it can drive its own document and same-origin frames;
  cross-origin frames and separate tabs are off-limits (the browser's own
  boundary, not ours).
- **No true browser control** — no real navigation to arbitrary origins, no
  network interception, no `newSession`/capabilities negotiation, no screenshots
  of chrome outside the document. Commands that have no DOM analog simply have no
  meaning here.
- It is Selenium *Core*, not Selenium *WebDriver* — the same trade the 1.0
  architecture made, taken deliberately.

## The honest cost

- **The shim is the surface area.** Every command you want must be mapped to a
  DOM operation by hand; the engine gives you the correct *request*, but "what
  does `click` do to a real element (scroll into view, dispatch trusted-ish
  events, honor pointer-events)" lives in the shim, and getting it faithful is
  the work.
- **Async for some ops** (waiting, animations) — same sync/async bridging note as
  the other two sketches, though many DOM ops are synchronous and escape it.
- **Trust boundary** — running in-page means the code under test can observe and
  perturb the driver; fine for your own content, wrong for adversarial pages.

## Status

Parked. If picked, the smallest proof is: WASM engine + a DOM-adapter shim
covering `findElement`/`click`/`getElementText`/`executeScript` against the
host document, driven by the shared `by_locator` output.
