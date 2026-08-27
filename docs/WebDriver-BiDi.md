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

Spec: the W3C WebDriver-BiDi specification (Simon was pointing us at the hosted
spec — **TODO: paste the exact URL he gave**; it's the normative reference for
the command/event catalog and framing).

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

## The C ABI extension (`aether_sel_embed_bidi_*`)

Minimal, mirroring the handle-based W3C ABI, all strings caller-owned:

```
aether_sel_embed_bidi_open(ws_url) -> handle        // or open from an existing session
aether_sel_embed_bidi_command(h, method, params_json) -> int   // 0 ok / -1 err
aether_sel_embed_bidi_last_result(h) -> char*        // reply `result` JSON
aether_sel_embed_bidi_subscribe(h, events_json) -> int
aether_sel_embed_bidi_next_event(h, timeout_ms) -> char*   // "" if none
aether_sel_embed_bidi_close(h)
```

Append-only; the existing W3C exports are unchanged.

## Scope — what BiDi gives us that W3C can't

Worth stating so review can prioritise. BiDi's value (not reachable over classic
W3C): **network interception** (`network.*`), **console/JS log capture**
(`log.entryAdded`), **real event streams** (DOM mutations, dialog handling),
`script.*` with proper realms/preload scripts, and low-latency
`browsingContext` events. First useful modules after the plumbing lands:
`session`, `browsingContext`, `log`, then `network` and `script`.

## Rollout

1. **This note reviewed** (Simon on the event model + scope). ← we are here
2. `selenium_bidi.ae` + the ABI, driven by the proven probe, one module deep
   (`session` + `browsingContext` + `log.entryAdded`).
3. One binding wired (Python — ctypes, already the reference), with a live test.
4. Widen module-by-module; other bindings follow the Python shape.

Nothing above changes the W3C engine or any existing binding.
