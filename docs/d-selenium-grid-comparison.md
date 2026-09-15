# Grid server: selaenium vs. cetio/d-selenium

Two projects that both include Grid-*server* code alongside a WebDriver client:
selaenium (this repo) and [cetio/d-selenium](https://github.com/cetio/selenium),
a standalone native-D WebDriver client + Grid package. Both are Apache-2.0.

This note compares the two **Grid-server** implementations. It is descriptive:
they make different scope and design choices, and this records what each is and
where each draws its lines — not a ranking. (A separate axis, the *client*
libraries, is not covered here.)

## At a glance

| Aspect | selaenium `grid/` | d-selenium `source/selenium/grid/` |
| --- | --- | --- |
| Size | ~330 lines (`hub.ae` + `hubcore.ae`) | ~820 lines across `hub.d`, `node.d`, `model.d`, `http.d` |
| Language / runtime | Aether, compiled into the same engine as the client | D, part of the `selenium:grid` dub subpackage |
| Stated scope | Standalone mode (router + node + local drivers in one process) | Grid models, hub/node scaffolding, and in-process HTTP routing |
| Distributed Grid | Deliberately out of scope (see `docs/Grid.md`) | Modelled — Node registers with a Hub; slot/stereotype/registry types present |
| Live HTTP endpoint | Yes — a running server that accepts newSession and proxies sessions | The package README states it provides "models and routing primitives, not a live HTTP server or a complete session distributor" |
| Session tracking | Stateless: routing facts are encoded into the session id | A hub-side node registry + session-ownership model |
| Node abstraction | None (single process; no separate node) | Explicit `Node` with slots, capability stereotypes, hub address, registration secret |

## selaenium's Grid server

`grid/hub.ae` (+ the pure `grid/hubcore.ae`) is a standalone-mode hub: a W3C HTTP
endpoint that accepts `POST /session`, provisions a driver for the requested
browser via the engine's driver manager, forwards the newSession, and proxies
every subsequent session-scoped request to the driver that owns that session —
router, node and local drivers in one process (the job the
`selenium/standalone-chromium` container does, without the container).

Design characteristics:

- **Standalone only.** A separate Router / Distributor / SessionQueue /
  SessionMap over an event bus, with remote Nodes registering, is explicitly not
  implemented; `docs/Grid.md` states this as a drawn line rather than a TODO.
- **Stateless routing.** There is no shared session map. The facts a later
  request needs — which driver process owns a session, on which port — are
  encoded into the session id the hub returns (`encode_session_id`:
  `<pid>-<port>-<driver session id>`), and decoded from the request path as pure
  string work. This is a deliberate response to Aether's concurrency model
  (actors rather than mutexes) and `std.http`'s worker-pool dispatch: with no
  shared mutable state, requests never contend and the hub needs no lock.
- **Known limitations** (documented in `docs/Grid.md`): an abandoned session
  (client never calls quit) leaves its driver running, because nothing tracks it
  to time out; there is no slot limit (every newSession launches a driver); one
  browser per session, with no capability matching beyond browser name.
- **Shared engine.** The hub is built from the same engine as the client and
  reuses the same driver-manager and HTTP conventions (the `OK <status> <body>` /
  `ERR <message>` tagged shape the engine's own round-trip uses).

## d-selenium's Grid server

`source/selenium/grid/` models the pieces of a distributed Grid as D types:

- **`model.d`** — `Stereotype` (a capability template), `Slot` (a stereotype +
  at most one session), `NodeInfo` (a node's status in the Grid `/status` node
  shape), and session data models for the wire envelope.
- **`node.d`** — a `Node` that hosts WebDriver slots, advertises them to a hub,
  carries a `hubAddress` to register with and an optional registration secret,
  and owns a route table of node endpoints.
- **`hub.d`** — a `Hub` with a request router, a node registry, and a
  session-ownership map; its `/status` reports readiness based on whether nodes
  have registered.
- **`http.d`** — an in-process router (path patterns binding parameters, e.g.
  `/se/grid/distributor/node/<nodeId>/drain`).

Design characteristics:

- **Distributed vocabulary.** The Node/Slot/stereotype/registration/registry
  concepts are the building blocks of a distributed Grid, present as types.
- **Scaffolding, per its own README.** The package "currently provides models
  and routing primitives, not a live HTTP server or a complete session
  distributor" — i.e. the modelling and routing surface exists; wiring it into a
  running distributed server is future work.
- **Stateful shape.** A hub-side node registry and session-ownership map (the
  natural shape for tracking multiple registered nodes and their slots).

## Where the lines fall

The two servers occupy different points on the same map:

- **Scope.** d-selenium models the *distributed* Grid shape (nodes registering
  with a hub, slots, stereotypes); selaenium implements the *standalone* shape
  (one process) and explicitly excludes the distributed machinery.
- **State.** d-selenium tracks nodes and sessions in hub-side structures;
  selaenium avoids shared state entirely by encoding routing into the session id.
- **Runtime state.** selaenium's hub is a running endpoint that provisions and
  proxies live sessions today; d-selenium's Grid is described by its README as
  models + routing primitives rather than a live server.
- **Growth path.** For selaenium, "more" means building the distributed pieces
  its `docs/Grid.md` defers (Router / Distributor / SessionQueue / SessionMap /
  remote-node registration) — a well-specified but large, different piece of
  work. d-selenium already carries the type-level model for parts of that shape.

## Not covered here

The client libraries (protocol coverage, BiDi, relative locators, etc.) are a
separate comparison. selaenium is a Grid **client** as well, verified live
against a real Selenium Grid — including a pinned Selenium 4.3.0 hub — via
`grid/run-grid-test.sh`.
