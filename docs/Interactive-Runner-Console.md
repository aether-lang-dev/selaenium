# Interactive Runner & Console

The **runner** is selaenium's interactive layer: a small shell language for
driving and *step-debugging* a live WebDriver session, surfaced from several
"comfy" front-ends. Its whole point is that the language and the debug model live
**once, in the Aether engine**, and every front-end is a thin host that ships a
line down the control lane and renders the reply/events that come back up.

Informed by webautoma's **SAM** ("Step-Aside Mode") console
([github.com/markel1974/webautoma](https://github.com/markel1974/webautoma),
Apache-2.0) — a design homage, not a code fork; credited in
[`../NOTICE`](../NOTICE) ("Portions copyright Marcello Russo").

## The layers (all engine-side, in `selenium_core/`)

| File | Role |
|------|------|
| `shell.ae` | the "wee shell language" — `shell_eval(session, line)` parses a terse line (`open <url>`, `click <sel>`, `text <sel>`, `type <sel> <text>`, `scroll <dx> <dy>`, `scrollTo <sel>`, `eval <js>`, `trace on`, …) and dispatches through the same command catalog every binding uses. Immediate execution. |
| `runner.ae` | the interactive **debug controller** over the shell — an indexed command *history* with a **cursor**, driven by control requests on the runner lane: `eval`, `mode run\|step`, `step`, `continue`, `inspect`, and the **SAM step-aside** verbs `list` / `jump` / `prev` / `next` / `redo`. Replies are id-correlated; `paused` / `command-finished` events are emitted. |
| `bidi_demux.ae` | the named-channel demux — multiplexes the runner control lane (so replies/events don't collide with a browser BiDi lane). |
| `iframe_bridge.ae` | the **SUT-adjacent** transport: the console runs as an iframe *beside* the page under test, but commands route DOWN to the driving client and back UP over `executeScript` — in-page UI, out-of-page execution. |
| `runner_server.ae` | the **out-of-process** transport: the runner lane over a WebSocket, so a host in another process drives a session with the same JSON. |
| `repl.ae` + `repl.build.ae` | the reference **terminal REPL**, a native Aether program (`selaenium-repl`). |

### The step-aside (SAM) model

`runner.ae` records every `eval`'d line into an indexed history with a `cursor`
(the next line to run). `step`/`continue` advance the cursor; `list` shows the
sequence with the cursor marked; `jump`/`prev`/`next` move it without executing;
`redo` re-runs the last-executed line. This is what lets a human step *back* and
re-run, not just forward — the essence of SAM.

## The front-end hosts

All three speak the **identical** runner JSON — a front-end is just "a textbox
that speaks the runner lane":

- **Terminal REPL** — `repl.ae` → `selaenium-repl`. Reads stdin, one line per
  command; meta verbs are `:step :continue :mode :inspect :events :list :jump <n>
  :prev :next :redo :quit`.
- **SUT-adjacent iframe console** — `console/console.html` (over `iframe_bridge.ae`).
- **Out-of-process dashboard** — `console/dashboard.html` (a WebSocket client of
  `runner_server.ae`). A VS Code extension, Tauri webview, or DAP adapter would
  each be another WebSocket client of the same endpoint.

### Why the REPL is written in Aether (not a binding language)

The reference REPL is an **Aether program** that calls the engine's
`shell`/`runner`/`driver` modules directly, rather than a host written in one
binding's language. That keeps the reference host thinnest (logic once, in the
engine) and, crucially, **toolchain-free** — it builds and runs with just the
Aether toolchain, no `dmd`/`node`/etc. (An earlier D reference REPL was migrated
into `repl.ae` for exactly this reason.) Each language binding still exposes the
runner as client surface (e.g. Rust/Python/D `.runner()`); the REPL simply no
longer depends on any one of them.

## Testing

### Unit (pure, no browser) — `selenium_core/tests/`

`runner.ae` and `iframe_bridge.ae` split the impure I/O (executeScript / sockets)
away from a **pure control-flow core**, so the state machine is unit-tested with
fed-in JSON and no browser:

- `runner_probe.ae` — run vs step mode, the history+cursor, reply correlation by
  id over the runner lane, `paused`/`command-finished` events, and every SAM
  verb (`list` count/cursor, `jump`, `prev`, clamp-past-end, `redo`).
- `iframe_bridge_probe.ae` — `bridge_process` correlation: reply/event tagging,
  id correlation, batch handling, the double-encoded outbox shape, and a SAM
  `list` request round-tripping through the bridge as a tagged reply.

Run them via the engine test harness:

```sh
aeb selenium_core/tests/.tests.ae
```

### Live browser — the REPL end to end

The terminal REPL is the host that can be driven end to end against a real
browser without any binding toolchain. Build it, then drive it in batch mode:

```sh
aeb selenium_core/repl.build.ae          # -> target/build/selenium_core/bin/selaenium-repl

# plain drive: open a page, read the title, find + read an element, quit
printf 'open data:text/html,<title>ReplLive</title><h1 id=z>go</h1>\ntitle\ntext #z\n:quit\n' \
  | ./target/build/selenium_core/bin/selaenium-repl --browser chrome

# SAM step-aside: queue in step mode, list the sequence, step, list again, continue
printf ':mode step\nopen data:text/html,<title>SAM</title><h1 id=z>hi</h1>\ntext #z\n:list\n:step\n:list\n:continue\n:quit\n' \
  | ./target/build/selenium_core/bin/selaenium-repl --browser chrome
```

`selaenium-repl` resolves and launches a driver itself (`driver.resolve_driver`
→ `launch` → `newSession`) unless you pass `--url <driverOrGridUrl>`.

**Verified (2026-09-18, ae 0.681, ChromeDriver 138 + Google Chrome, Linux
x86_64):**
- Plain drive: `title` printed `ReplLive`, `text #z` printed `go`,
  `command-finished` events fired per line, exit 0 with a clean quit + driver
  stop.
- SAM sequence: `:mode step` queued both lines (`paused pending:1` → `pending:2`);
  `:list` showed `cursor:0, count:2` with both indexed lines; `:step` ran index 0
  and re-paused (`pending:1`); the second `:list` showed `cursor:1`; `:continue`
  drained the rest (`continued:1`, back to run mode). Exit 0.

Every SAM verb behaved as the unit probes assert — confirmed against a live
session, not just fed JSON. (A `--url` pointed at a dead endpoint prints
`newSession failed: connection failed` and exits 0 — the arg-parse/open/teardown
path with no hang.)

### Front-end JS

`console.html` and `dashboard.html` are single-file, dependency-free, and
served/injected as-is; their scripts are validated with `node --check`. They
speak the same runner JSON the REPL is proven against, so the protocol is shared;
a live in-browser round-trip is the remaining nice-to-have.
