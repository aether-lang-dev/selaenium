# Embedded Test Runtime

*A WASM design sketch — parked, not chosen. One of three (see also
[In-Page Remote Driver](./In-Page_Remote_Driver.md) and
[Same-Origin DOM Driver](./Same-Origin_DOM_Driver.md)). The most ambitious of
the three, and the closest to "Selenium-RC done right".*

## One line

A high-level language runs **inside the browser** and drives the page through
our engine — the test/automation script's control flow executes in-page at
interpreter speed, and only the browser *actions* cross to the engine and its
transport. The strongest candidate is **RexxJS** (`../rexxjs/`), because its
`ADDRESS` mechanism *is* the Selenium-RC dispatch model as a first-class
language feature, and it already runs in the browser — so this becomes "write
one `ADDRESS SELENIUM` handler," not "compile a language runtime to WASM."

## The lineage, and why this is the RC insight completed

Selenium-RC put the script server-side and shipped commands *to* the browser one
COMET frame at a time. Every step of control flow — every `if`, every loop
iteration, every assertion — was a network round-trip away from the browser it
drove. A thousand-assertion test paid a thousand latencies, because the *brain*
and the *browser* were on opposite ends of a wire.

Invert it. Put the script **in** the browser, next to the engine:

- The **control flow** (loops, conditionals, the test's own logic) runs locally
  in the interpreter — zero round-trips.
- Only the **browser actions** (`get`, `click`, `find`) cross a boundary — and
  that boundary can be any of the three transports (remote WebDriver, BiDi
  WebSocket, or the same-origin DOM adapter from the sibling sketches).

RC couldn't do this because in 2005 there was no way to run a real HLL in the
page. A browser-native interpreter is exactly that missing piece.

## Why RexxJS is the natural fit (and re-scopes the whole idea)

REXX's **`ADDRESS` verb** is the language's built-in way to send commands to an
external subsystem and read back a `result` / `RC`. That is *precisely* the RC
model — a script names a target and issues string commands to it:

```rexx
REQUIRE "rexxjs/address-selenium" AS SELENIUM
ADDRESS SELENIUM
"get https://example.com/login"
"type #username 'alice'"
"type #password 'secret'"
"click #submit"
IF RC \= 0 THEN SAY "login failed:" RESULT
title = "text h1"           /* result flows into a REXX variable */
SAY "landed on:" title
```

Two things make this cheap where the original sketch was expensive:

1. **RexxJS already runs in the browser** and already ships DOM-automation
   handlers (`core/src/web/iframe-rpc-bridge.js`, `dom-output-handler.js`). We
   don't compile an interpreter to WASM — the interpreter is there. The
   ~60–85 KB "engine + interpreter" bundle cost the sketch worried about mostly
   evaporates; we ship the engine and register a handler.
2. **The `ADDRESS` handler contract is small and documented.** A target is a
   module (`@rexxjs-meta`, a `_META()` declaring its `methods`) plus a handler
   `ADDRESS_SELENIUM_HANDLER(command, params, ctx)` that parses a verb +
   `key=value` params and returns `{ success, result, ... }`. It sits beside the
   existing `address-docker` / `address-sqlite` / `address-gcp` targets — the
   same ecosystem, same author, MIT.

So the deliverable is one bridge file, not a platform: **`address-selenium.js`
turns each REXX command into a `selenium_core` call** (`route` / `by_locator` /
`build_request` / decode) and dispatches the wire request over the chosen
transport.

## How it composes

```
   ┌─────────────────────────── browser tab ───────────────────────────┐
   │                                                                    │
   │   RexxJS interpreter            selenium_core (WASM)               │
   │   (browser-native)              the shared protocol brain          │
   │                                                                    │
   │   login.rexx:                   ADDRESS_SELENIUM_HANDLER(cmd):      │
   │     ADDRESS SELENIUM            ├─ by_locator("#submit")           │
   │     DO i = 1 TO 1000  ◀─runs─┐  ├─ build_request("elementClick")   │
   │       "click #next"  ────────┼─▶└─ decode(reply)                   │
   │       IF RC\=0 THEN LEAVE     │        │                            │
   │     END               ◀─runs─┘        ▼ transport ────────────────┼─▶ browser
   │                                (fetch/Grid | BiDi ws | same-origin) │
   └────────────────────────────────────────────────────────────────────┘
```

The REXX loop runs in-page (no per-iteration latency); each `"click …"` becomes
one engine call + one transport hop. The engine is the *same* `selenium_core`
that backs all 18 native bindings — one protocol brain, no drift.

## What this is actually FOR — the use cases

This is not "another binding." It is a distinct capability with real audiences:

- **Driver-less, in-page test artifacts.** A `.wasm` + a `.rexx` is a complete,
  self-running scenario you can drop into a page or a bug report: *"here is the
  failing flow — open this tab and it runs itself,"* no chromedriver, no install.
  Especially strong for **repro bundles** attached to issues.
- **Automation embedded in the app under test.** A shipped web app can carry its
  own smoke test / health-check / guided-tour script in REXX, run it on demand
  (a "self-test" button, a canary in production), and report results — the app
  tests *itself* from the inside.
- **Fast, tight-loop suites.** Data-driven tests that loop thousands of times
  (fuzzing a form, walking a table, property checks) pay interpreter speed for
  control flow and only serialize the actual browser actions — the RC latency
  tax is gone.
- **Non-developer / ops automation.** REXX is deliberately readable and was
  built for exactly this "glue + dispatch" role; an SRE or QA author can write
  `ADDRESS SELENIUM; "click #deploy"` without a JS toolchain, a node_modules, or
  a build step. It slots next to RexxJS's existing `ADDRESS` targets
  (docker/sqlite/gcp/ssh/claude), so one REXX script can drive a browser *and*
  a database *and* a container in the same flow.
- **Record / replay conformance oracle.** With a stub transport, the same bundle
  runs entirely offline: feed recorded responses, assert the requests the script
  *would* emit. Servirtium-style VCR, client-side — a browserless way to test
  that the protocol layer is correct.
- **Teaching / live demos.** "Here is what `findElement` + `click` *mean*,"
  running in a tab with a visible REXX script and no setup.

The through-line: **the driving intelligence lives in the browser, in a readable
HLL, next to the page** — RC's ergonomics without RC's latency or its second,
drifting implementation.

## The honest cost

- **Transport still has to be chosen.** The same fork as the sibling sketches:
  `fetch` to a real WebDriver/Grid (needs same-origin or CORS/proxy), a BiDi
  WebSocket (now unblocked — see [WebDriver-BiDi](./WebDriver-BiDi.md)), or the
  same-origin DOM adapter (drives only the hosting page). The `ADDRESS` handler
  is transport-agnostic; something must supply one.
- **Async at the boundary.** Browser actions are async; the handler contract is
  already async-friendly (`ADDRESS_*_HANDLER` may return a promise), but a REXX
  script expects `result` synchronously after a command, so the bridge must
  bridge that — RexxJS's existing async ADDRESS targets (claude, gcp) show the
  pattern, so this is a solved shape here, not new research.
- **We still need the WASM engine build.** No `wasm/` target exists yet;
  compiling `selenium_core` to wasm32 is the html-sanitizer pattern (proven
  there), but it is real work and hasn't been started.
- **Scope discipline.** This is a product direction, not "one more language."
  Pick it deliberately.

## Status

Parked — but **materially cheaper than first sketched**, because RexxJS supplies
the in-browser HLL + the RC-style `ADDRESS` dispatch for free. If picked, stage
it: (1) a WASM build of `selenium_core` exposing `route`/`by_locator`/
`build_request`/`decode`; (2) one transport (the [In-Page Remote
Driver](./In-Page_Remote_Driver.md) `fetch`/BiDi path is the most general); (3)
`address-selenium.js` — the RexxJS `ADDRESS SELENIUM` handler over (1)+(2); (4)
the record/replay stub transport. Each stage is useful on its own.
