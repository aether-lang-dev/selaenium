# WebDriver-BiDi — design note

*Status: design, pre-implementation. The transport + protocol model are
**proven** (`selenium_core/bidi_probe.ae`, green live against Chrome 152); this
note is the plan for the committed engine layer, put up for review before the
build. BiDi/wire semantics are flagged high-risk in AGENTS.md, so this is
deliberately design-first.*

## What's already true

- The classic **W3C engine is complete** (143 routes, HTTP round-trip, 18
  bindings) — BiDi is additive, not a replacement.
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

Core operations, all pure Aether over `ws_send_text` / `ws_recv` / `ws_message`:

- `bidi_open(ws_url) -> BidiSession`  — `ws_connect`, ready to command
- `bidi_command(s, method, params_json) -> reply_json` — assign next id, send,
  read frames until the reply with that id arrives (buffering any events seen
  along the way — see below), return `result` or a typed BiDi error
- `bidi_subscribe(s, events[])` / `bidi_unsubscribe(...)`
- `bidi_next_event(s) -> event_json | ""` — hand the caller the next buffered
  or freshly-arrived event

The W3C engine is **untouched**. A binding that wants BiDi first does a normal
`newSession` (with `webSocketUrl:true` in caps), reads the `webSocketUrl`, and
calls `bidi_open` — the two channels coexist for the same browser session.

## The one real design question: async events over a synchronous FFI

This is the crux and the reason for the review. Our whole architecture is a
**synchronous C ABI** — a binding calls `execute(...)`, blocks, gets a result.
BiDi events arrive **whenever the browser feels like it**, interleaved with
command replies on the one socket. `ws_recv` is itself blocking. So:

- While `bidi_command` waits for its reply, **events can arrive first** on the
  same socket. They must be **buffered**, not dropped, so a later
  `bidi_next_event` can return them.
- A binding wanting *only* events (a listener loop) needs a call that blocks for
  the next event — but must not block forever if none comes.

**Proposed model — a drain/poll queue, no threads, no callbacks:**

1. `bidi_command` reads frames in a loop; a frame with our `id` is the reply
   (return it); any `{type:"event"}` frame seen meanwhile is **appended to an
   in-session event queue**.
2. `bidi_next_event(s, timeout_ms)`:
   - if the queue is non-empty, pop and return immediately;
   - else `ws_recv` with a bounded wait; a command reply that arrives here
     (shouldn't, if the binding is disciplined) is queued by id;
   - return `""` on timeout so the caller's loop stays responsive.

This keeps the FFI **synchronous and callback-free** — the binding drives an
event loop by *polling* `bidi_next_event` on its own thread/timer, exactly the
shape the ctypes/Fiddle/cgo bindings already handle for blocking calls. No
async ABI, no reentrancy, no engine-owned threads. The cost is that events are
delivered when the binding *asks*, not pushed — acceptable, and arguably
clearer, for a linked-in synchronous core.

**Questions for review (Simon especially):**
- Is a **poll/drain** model acceptable for BiDi events in a client, or do real
  consumers need push (a background reader thread surfacing events via a
  callback)? The latter is doable but drags threads across the FFI boundary and
  raises reentrancy — a real step up in complexity.
- `bidi_command` buffering events while awaiting a reply assumes a **single
  logical caller** on the socket. Is multiplexing concurrent commands from
  multiple binding threads a requirement, or can we say "one BiDi conversation
  per connection, open more connections for concurrency"?
- Timeout semantics: bound every `ws_recv`? BiDi has no per-command timeout in
  the spec; the client imposes one.

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
