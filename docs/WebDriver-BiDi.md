# WebDriver-BiDi — design note

*Status: design, pre-implementation. The transport + protocol model are
**proven** (`selenium_core/bidi_probe.ae`, green live against Chrome 152); this
note is the plan for the committed engine layer. BiDi/wire semantics are flagged
high-risk in AGENTS.md, so this is deliberately design-first.*

## Guidance from Simon Stewart (WebDriver/BiDi's creator), 2026-08

Reviewed with Simon; two rulings shape everything below:

1. **Strategic — "BiDi support is the way forwards. Classic will disappear."**
   BiDi is not an additive extra beside classic W3C-HTTP; it is the *future
   primary protocol*, and the classic HTTP surface is on a path to obsolescence.
   The reboot should treat BiDi as a first-class peer to the W3C engine now and
   the eventual successor — not a bolt-on. (We still keep the W3C engine: it
   works, it ships today, and classic won't vanish overnight. But new design
   weight goes to BiDi.)

2. **Technical — BiDi is genuinely concurrent.** "WebSockets are asynchronous by
   nature. A single BiDi client can issue **multiple commands and await multiple
   events simultaneously**. The client manages timeout semantics." This rules
   out the simple "one logical caller / poll-drain" model an earlier draft
   proposed — see [The real design question](#the-real-design-question-a-concurrent-client-over-a-synchronous-ffi)
   below, now reframed around multiplexing.

Spec: **<https://w3c.github.io/webdriver-bidi/>** — the W3C WebDriver-BiDi
specification (the link Simon gave). This is the normative reference for the
command/event catalog, the JSON-RPC framing, and the session/subscription model.

## What's already true

- The classic **W3C engine is complete** (143 routes, HTTP round-trip, 18
  bindings) and keeps working — but per Simon it is the *legacy* surface;
  BiDi is where new capability and design attention go.
- Aether shipped a **WebSocket client** (`std.http.ws_connect`, v0.590.0),
  which was the sole blocker.
- The **vertical slice is proven live**: W3C `newSession` with
  `webSocketUrl:true` → `ws_connect` to `value.capabilities.webSocketUrl` →
  JSON-RPC command-by-id (`session.status`) → `session.subscribe` →
  `browsingContext.navigate` → **received the async `browsingContext.load`
  event**. Both request/reply and bidirectional events work.

## The shape of BiDi vs. the W3C engine

|                | W3C (classic)                    | BiDi                                   |
|----------------|----------------------------------|----------------------------------------|
| Transport      | HTTP, one round-trip per command | one **persistent WebSocket**           |
| Model          | stateless request → response     | JSON-RPC: `{id, method, params}` → reply `{id, result}` **by id**, plus unsolicited `{type:"event", method, params}` |
| Concurrency    | synchronous, 1:1                 | many in-flight commands (match by id) + **async events at any time** |
| Session        | `sessionId` in the URL path      | rides an existing W3C session's `webSocketUrl` |

BiDi is not a new *set of routes* — it's a different *interaction model*. That's
why it wants its own module, not new entries in the W3C route table.

## Proposed structure

```
selenium_core/
  selenium_core.ae      the W3C engine (unchanged)
  selenium_bidi.ae      NEW — the BiDi session over a ws handle
  embed.ae              extended with a small BiDi ABI surface
  bidi_probe.ae         the proven live probe (already committed)
```

`selenium_bidi.ae` owns a `BidiSession`:

```
struct BidiSession {
    ws: ptr            // the std.http ws_connect handle
    next_id: int       // monotonic command id
    // (event buffering — see the open question below)
}
```

Core operations, all pure Aether over `ws_send_text` / `ws_recv` / `ws_message`.
**These signatures are provisional** — they show the *shape*, but their exact
form (blocking vs non-blocking, who owns the id) is decided by the concurrency
model below (A/B/C), because Simon's multiplexing ruling means `bidi_command`
cannot simply "read until my reply arrives" while another command is also in
flight:

- `bidi_open(ws_url) -> BidiSession`  — `ws_connect`, ready to command
- `bidi_send(s, id, method, params_json)` — frame + send one command (caller
  supplies `id` so concurrent commands stay distinct)
- `bidi_await_reply(s, id, timeout_ms) -> reply_json` — the reply for that id
  (or a typed BiDi error / timeout) — form depends on A/B/C
- `bidi_subscribe(s, events[])` / `bidi_unsubscribe(...)`
- `bidi_next_event(s, timeout_ms) -> event_json | ""` — next event, concurrently
  with any in-flight commands

The W3C engine is **untouched**. A binding that wants BiDi first does a normal
`newSession` (with `webSocketUrl:true` in caps), reads the `webSocketUrl`, and
calls `bidi_open` — the two channels coexist for the same browser session.

## The real design question: a concurrent client over a synchronous FFI

This is the crux. Simon's technical ruling settles what the client must *be* and
kills the easy way out:

> A single BiDi client can issue **multiple commands and await multiple events
> simultaneously.** The client manages timeout semantics.

So a conforming BiDi client is **multiplexed**: many commands in flight at once
(each awaited independently, matched by `id`), plus events streaming
concurrently — all on the one WebSocket. The earlier draft's "single logical
caller, poll-drain the socket" model is **retired**: it cannot express two
commands outstanding at once, and it starves events behind a blocking command
read.

The tension is now sharp, and real:

- **BiDi wants concurrency** — a reader continuously draining the socket,
  routing each frame to *either* the waiter for its `id` (a pending-command
  table) *or* the event stream.
- **Our engine speaks through a synchronous, callback-free C ABI** — a binding
  calls, blocks, gets one result. There is no natural place in that ABI for
  "and also, at any time, here is an event" or "three commands are in flight."

Reconciling those is the design work. Two broad shapes, to be chosen at review:

**A. Concurrency in the engine (a reader thread behind the ABI).**
The engine owns a background thread that drains the socket into a mutex-guarded
pending-command table (keyed by `id`) and an event queue. `bidi_command`
registers an id, blocks on its slot's condition; `bidi_next_event(timeout_ms)`
pops the queue. Multiplexing "just works" and every binding gets it for free.
*Cost:* threads + locks inside the engine, crossing the FFI boundary — the
high-risk area AGENTS.md flags; reentrancy and lifetime become real concerns;
Aether's threading story has to support it.

**B. Concurrency in the binding (engine stays a thin frame relay).**
The engine exposes only framing — `bidi_send(json)`, `bidi_recv(timeout_ms) ->
frame_json` — and each binding owns the reader loop + id-dispatch in its *native*
async (asyncio for Python, goroutines for Go, the event loop for Node, …). The
engine holds no threads and no state beyond the socket. *Cost:* every binding
reimplements the multiplexer, so the "one brain, thin bindings" property erodes
exactly where it's hardest to get right (concurrent dispatch, cancellation,
timeouts) — the drift risk we built this architecture to avoid.

**C. A hybrid** — the engine does frame demux (id-table + event queue, single
reader) but exposes it through *non-blocking* poll calls (`bidi_poll_reply(id)`,
`bidi_poll_event()` returning immediately), leaving the *waiting/scheduling* to
the binding's own loop. No engine threads; multiplexing preserved centrally;
each binding only adapts polling to its async primitive. This looks like the
sweet spot but needs validation.

**Open questions for the build:**
- Which of A / B / C? (Leaning C — central demux, no engine threads, bindings
  own only the wait — but it hinges on how cleanly each FFI family drives a poll
  loop.)
- Timeout semantics are **the client's** (Simon confirmed): where do they live —
  per-command in the demux, or in the binding's wait? Probably the binding, with
  the engine offering a bounded `recv`.
- Cancellation: a command whose waiter gives up must not leak its id-table slot
  or mis-route a late reply.
- Does the ABI need a stable per-command id the *caller* supplies, or does the
  engine mint and return it? (Caller-supplied composes better with async.)

## DECISION: C — central demux + non-blocking poll (2026-08-30)

**Chosen: shape C.** The engine owns the ONE multiplexer — a single reader that
drains the WebSocket and routes each frame to *either* the id-keyed
pending-reply table *or* a bounded event queue — but exposes it through
**non-blocking poll calls**, so the engine holds **no threads**. Each binding
adapts polling to its own native async (asyncio, goroutines, the Node event
loop, …) and owns only the *wait*. This keeps the multiplexer central and
correct (the "one brain" property that is the whole point of the shared engine)
without threads/reentrancy across the FFI boundary (the high-risk area
AGENTS.md flags — which rules out A) and without 18 reimplementations of the
hardest concurrent code (the drift that rules out B).

**Prior art — BEEP (RFC 3080/3081, 2001).** BEEP solved this exact problem
20 years ago: multiplex independent request/reply exchanges plus one-way
notifications over a single connection, correlated by a per-message `msgno`
(MSG→RPY/ERR for request/reply, MSG→ANS*→NUL for streamed answers, plus
unsolicited). BiDi's `{id, result}` replies vs. unsolicited `{type:"event"}`
are a strict subset of BEEP's model, and BEEP libraries universally put the
correlation table in ONE place and let the application drive the I/O loop —
i.e. exactly shape C. Two lessons borrowed:
- **Bounded event queue with a defined overflow policy.** BEEP had explicit
  per-channel flow control (SEQ/windows); BiDi dropped flow control (WebSocket
  frames it), which risks an unbounded event queue if a binding drains slower
  than events arrive. The demux's event queue is therefore **bounded**; on
  overflow it drops the oldest event and sets a "lost events" marker the next
  `poll_event` surfaces (never blocks the reader, never grows without bound).
- **Skip the ceremony.** BEEP's weight (channel-management protocol, profiles,
  tunneling) is why it never caught on. BiDi already dropped channels (one
  WebSocket, `id` only); we keep only the correlation-table core.

**Resolved sub-questions:**
- **How the binding waits:** the engine exposes the WebSocket's readable fd
  (`bidi_fd(h)`) so a binding can `select`/`epoll`/`asyncio.add_reader` on it,
  AND a bounded `bidi_pump(h, timeout_ms)` that blocks up to `timeout_ms`
  advancing the demux one step (for bindings that prefer a simple bounded recv
  over fd integration). Poll calls (`poll_reply`/`poll_event`) always return
  immediately. No busy-spin: the binding blocks on its own primitive, then
  drains what's ready.
- **Command id:** the **caller supplies** the id (`bidi_send(h, id, …)`) — it
  composes better with async (the caller already has a future/task keyed by it)
  and keeps the engine stateless about id generation.
- **Timeouts:** the **binding's** (Simon confirmed) — the engine offers only the
  bounded `pump`; per-command deadlines live in the binding's wait.
- **Cancellation:** a waiter that gives up calls `bidi_cancel(h, id)` to drop its
  pending-reply slot; a late reply for a cancelled/unknown id is discarded by the
  demux (never mis-routed, never leaks).

## The C ABI extension (`aether_sel_embed_bidi_*`)

Shape C — non-blocking demux, all strings caller-owned. The engine holds no
threads; a binding drives the poll loop with its own async, waiting on `bidi_fd`
or the bounded `bidi_pump`.

```
// lifecycle
aether_sel_embed_bidi_open(ws_url) -> handle      // ws_connect to the session's webSocketUrl
aether_sel_embed_bidi_close(h)

// send (caller supplies the id → concurrent commands stay distinct)
aether_sel_embed_bidi_send(h, id, method, params_json) -> int   // 0 queued / -1 err

// advance the single demux one step, blocking up to timeout_ms (0 = non-blocking).
// Reads any ready frames off the socket, routing replies → id-table, events →
// bounded queue. Returns 1 if it made progress, 0 on timeout, -1 on socket error.
aether_sel_embed_bidi_pump(h, timeout_ms) -> int
// the readable socket fd, for a binding that selects/epolls/add_readers on it
// instead of using pump's bounded wait.
aether_sel_embed_bidi_fd(h) -> int

// drain (both return immediately — the binding calls these after a wait)
aether_sel_embed_bidi_poll_reply(h, id) -> char*   // reply `result`/`error` JSON, or "" if not yet in
aether_sel_embed_bidi_poll_event(h) -> char*       // next queued event JSON, or "" if none
aether_sel_embed_bidi_lost_events(h) -> int        // count dropped by the bounded queue, then resets

// cancellation: drop a waiter's pending-reply slot (a late reply is discarded)
aether_sel_embed_bidi_cancel(h, id)
```

Append-only; the existing W3C exports are unchanged. A typical binding loop:
`send(id,…)` → wait on `fd`/`pump` → `poll_reply(id)` until non-empty (its own
timeout), draining `poll_event` alongside for the subscribed event stream.

## Scope — what BiDi gives us that W3C can't

Worth stating so review can prioritise. BiDi's value (not reachable over classic
W3C): **network interception** (`network.*`), **console/JS log capture**
(`log.entryAdded`), **real event streams** (DOM mutations, dialog handling),
`script.*` with proper realms/preload scripts, and low-latency
`browsingContext` events. First useful modules after the plumbing lands:
`session`, `browsingContext`, `log`, then `network` and `script`.

## Rollout

1. ✅ **This note reviewed** (Simon on the event model + scope).
2. ✅ `selenium_bidi.ae` + the ABI (shape C: `bidi_demux.ae` frame router +
   `selenium_bidi.ae` live session), driven by the proven probe. Went well past
   one module: `session` + `browsingContext` + `script.evaluate` + `log.entry
   Added` + the full `network.*` interception suite.
3. ✅ **Python wired (ctypes) with GREEN live tests (2026-09-03).** All 22
   `aether_sel_embed_bidi_*` verbs bound in `python/selenium/_native.py`; the
   `BiDi` class + lazy `driver.bidi` accessor in `_webdriver.py`.
   `python/test/test_live_chrome.py` runs green against real Chrome 138:
   `test_live_bidi` (subscribe→async `log.entryAdded`, `session.status`,
   `evaluate` 6*7→42 + Promise→42, network intercept/provideResponse/
   setCacheBehavior) and `test_live_bidi_auth` (`network.authRequired` →
   `continueWithAuth` → read the protected secret). Also verified through the
   raw C ABI (`tests/bidi_abi_smoke.c`: two concurrent commands correlate by id).
   NB the live test needs a chromedriver whose version MATCHES the local Chrome —
   the driver-manager's `resolve_driver("chrome")` gives it; a mismatched PATH
   chromedriver makes newSession hang.
4. ✅ **Widened — 9 bindings verified GREEN live vs real Chrome
   (2026-09-03):** Python (ctypes), Go (cgo), Ruby (Fiddle), Rust (extern "C"),
   Nim (importc), Dart (dart:ffi) — verified on the ChromeOS box vs Chrome 138 —
   plus the JVM family Kotlin, Groovy, Clojure (all three ride the one Java
   Panama binding, reaching the Java `BiDi` class directly via JVM interop with
   NO binding-side FFI) — verified on catchyos vs Chrome 152. Each runs the same
   core BiDi flow (bidiAvailable → subscribe→async `log.entryAdded` → command
   `session.status` → topContext → `evaluate` 6*7→42); several also run the full
   network-interception suite (Go + Ruby the authRequired→continueWithAuth flow).
   All 11 own-FFI bindings bind the 22 `bidi_*` verbs and ship a `BiDi` wrapper +
   `.bidi` accessor; java/zig/lua/erlang have the tests written and pass through
   the C ABI smoke but need their aeb/fixture harness to run here (zig wants
   SEL_CHROMEDRIVER_URL + a specific content-server fixture). REMAINING: scala
   (Java-Panama family, FFI-only test today — add a live BiDi test);
   elixir/gleam/lfe (over the Erlang NIF, which already has all 22 — add wrapper
   + test); haskell/julia/crystal/fsharp (need the 22 bidi FFI decls too).

Nothing above changes the W3C engine or any existing binding.
