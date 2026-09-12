# Grid

selaenium is a Grid **client** — point `openSession` at a hub URL and the engine
drives a session through it. That has always worked, and
`grid/run-grid-test.sh` proves it against a real Selenium Grid in a container.

selaenium is now also a Grid **server**, in standalone mode: `grid/hub.ae`
builds `selaenium-hub`, a W3C endpoint that provisions drivers and proxies
sessions to them. This note says what that is, what it deliberately is not, and
how it is held honest.

## What standalone mode means

Router, node and local drivers in ONE process — the job the
`selenium/standalone-chromium` container does:

```
client ──HTTP──> selaenium-hub ──HTTP──> chromedriver ──> Chrome
                 (provisions the driver on newSession,
                  proxies every later request to it)
```

```sh
aeb grid/.build.ae            # -> selaenium-hub
SEL_HUB_PORT=4444 selaenium-hub
```

Then any Selenium client — ours or anybody's — points at
`http://127.0.0.1:4444` and gets a session. The hub resolves and launches the
driver itself through the engine's existing driver manager
(`selenium_core/drivermgr`), so there is no driver to install: it detects the
browser, matches a driver, downloads and caches it, exactly as a local run does.

## What it is NOT

**Distributed Grid.** Real Selenium Grid splits into a Router, a Distributor, a
New Session Queue, a Session Map and remote Nodes that register over an event
bus, so that sessions spread across machines. None of that is here. This is one
process on one host.

That is a deliberate line, not an oversight. Standalone is the shape most people
actually run, it is what the reference container is, and it needs none of the
distributed machinery. Growing into distributed mode would mean implementing a
well-specified distributed system — a large piece of work, and a different one.

Also absent: session timeouts/reaping (see Known limitations), queueing when the
host is saturated, `/se/grid/*` introspection endpoints, and the Grid UI.

## Why the hub has no session map

`std.http` dispatches HTTP/1.1 handlers on a worker pool (`cores * 2`), so a
shared mutable session map would need a lock — and Aether's concurrency story is
actors, not mutexes.

Rather than guard shared state, the hub has none. The routing facts a later
request needs — *which driver process owns this session, on which port* — are
encoded into the session id the hub hands back:

```
hub session id  =  <driver pid>-<driver port>-<driver's own session id>
                   175533-42271-0fbf528793b26184161c7fd0c7f433d0
```

A session id is opaque to clients, so wrapping it is invisible. Every later
request then carries its own routing, decoding is pure string work on that
request's path, and two concurrent requests never touch shared state. The hub is
trivially safe under the worker pool, and there is no lock to get wrong.

`DELETE /session/<id>` decodes the pid back out and reaps the driver process.

## Known limitations

- **An abandoned session leaks its driver.** Nothing tracks sessions, so a client
  that never calls `quit` leaves chromedriver running until the host is cleaned
  up. Real Grid times those out. Fixing it properly means either a reaper with
  state (and then the locking question returns, so: an actor) or a
  driver-side idle timeout.
- **No slot limit.** Every `newSession` launches a driver; nothing refuses the
  hundredth concurrent request.
- **One browser per session.** Fine for standalone, but there is no matching of
  requested capabilities against a declared set of slots.

## How it is held honest

The hub is not graded against itself. `grid/run-grid-test.sh` takes a `--hub`
flag that swaps the reference Grid container for `selaenium-hub` and exports the
same `SEL_GRID_URL`, so the **identical** per-binding Grid legs
(`test_live_grid` in Python, `GridTest` in Ruby, `LiveTest#liveGrid` in Java)
run against either one:

```sh
grid/run-grid-test.sh       <cmd>   # against real Selenium Grid, in a container
grid/run-grid-test.sh --hub <cmd>   # against our hub, no container
```

Both produce the same result today. That is the contract: our hub is correct
insofar as clients cannot tell it from the reference implementation.

The routing logic itself — the session-id codec, capability reading, response
shaping — is pure and lives in `grid/hubcore.ae`, unit-tested with no browser,
no driver and no listening port by `grid/tests/hub_probe.ae` (`aeb
grid/.tests.ae`). That is where the malformed-session-id and
driver-ids-containing-dashes cases are pinned.
