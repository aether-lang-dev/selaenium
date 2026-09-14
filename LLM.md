# Notes to self (LLM assisting on selaenium)

Not a CLAUDE.md — `AGENTS.md` holds the rules. This is the map: short,
opinionated, written for a future LLM picking up mid-task. Re-read at the start
of every session. **The code is the source of truth; this exists so your first
attempt lands clean.** Modelled on the sibling `../servirtium-vcr/LLM.md`, which
is worth reading too — it is the same design, further along, and its
"Gotchas / hard-won" list has repeatedly applied here verbatim.

## What this is, in one paragraph

W3C WebDriver, reimplemented **once** in pure Aether and re-glued to every
language over a C ABI. The engine is `selenium_core/selenium_core.ae` (route
table, path templating, By/capabilities normalization, W3C error decode, the
`std.http.client` round-trip), plus `atoms.ae` (the shared JS atoms for commands
with no W3C endpoint), `driver.ae` + `drivermgr/` (resolve/launch/stop a
driver — this repo's Selenium-Manager), `selenium_bidi.ae` + `bidi_demux.ae`
(WebDriver-BiDi over a WebSocket), and `embed.ae` (the flat C ABI,
`aether_sel_embed_*`). It compiles to `libselenium_core.so`. Every
`<lang>/` directory is a thin FFI shim over that one artifact. The only C is
`selenium_core/_embed_strdup.c` — two functions, 12 lines of actual code: the
caller-owned-string bridge (`sel_embed_dup` / `sel_embed_free`). It cannot be
Aether because `std.mem` is access-only with no allocation primitive, and the
bindings free returned pointers with C `free()`.

`grid/` is the newer half: `hub.ae` is a **standalone Grid hub** — we are a Grid
client *and* now a Grid server. See `docs/Grid.md`.

## The one rule

**Bindings carry no protocol logic.** The command catalog, the route table, path
templating, By normalization, the error map, the HTTP round-trip — all engine.
A binding opens a session, issues commands by name with JSON params, reads back
a value or a typed error, and closes. If you are about to parse a locator or
build a path in a binding, stop: that is the engine's job.

The live consequence you will hit: `By.id("x")` in a binding does **not**
pre-rewrite to CSS. It carries `{using: "id"}` and the ENGINE rewrites it to
`*[id="x"]`. Mainstream selenium-webdriver rewrites in the binding; we
deliberately do not, because that would be a second normalization path. Wire
traffic is identical. A test asserting `By.id(...)` yields CSS is testing the
wrong layer.

## Adding a language

No tutorial, by design — the existing bindings **are** the spec. The README's
Bindings tables are the registry (trust them over any count written in prose;
`.presubmit.ae` and `docs/Architecture.md` both carry stale counts at the time
of writing). Copy the nearest binding by FFI mechanism:

- **Runtime load**: `python/` ctypes, `ruby/` Fiddle, `javascript/` koffi,
  `dotnet/` P/Invoke, `php/` FFI, `dart/` dart:ffi, `julia/` ccall, `d/` dlopen.
- **Link time**: `go/` cgo, `rust/` extern "C" + build.rs, `nim/` importc,
  `zig/` @extern, `crystal/` `@[Link]`, `haskell/` ccall, `swift/` C interop via
  a module map, `c/` the ABI directly, `cpp/` header-only over `c/`.
- **C extension**: `lua/` (Lua 5.4 C API).
- **Families — bridged ONCE, then ridden for free**:
  - BEAM: `erlang/` owns the NIF; `elixir/`, `gleam/`, `lfe/` load that SAME
    compiled module. No second C source.
  - JVM: `java/` owns the Panama FFM jar; `kotlin/`, `clojure/`, `groovy/`,
    `scala/` are ordinary JVM interop over it. No second FFI.
  - .NET: `dotnet/` owns the P/Invoke assembly; `fsharp/` rides it.

Then: bind the ABI, write the no-browser FFI test, write the live test (which
self-skips when no driver resolves), and **add a `.example.ae`** (below).

## The C ABI (`aether_sel_embed_*`)

49 exports. Handle-based, N sessions per process. `open(base_url)` → handle;
`execute(h, name, params_json)` → 0 / a W3C error code / -1 for transport
failure; drain via `last_value` / `last_error_code` / `last_error` /
`last_status` / `session_id`. Pure helpers `by_locator`, `route`, `error_code`,
`build_request` are exported so bindings share the one normalization path.
Beyond the command seam: driver orchestration (`resolve_driver`,
`ensure_driver`, `launch_driver`, `stop_driver`, `driver_url`, `driver_pid`),
the atoms (`is_displayed`, `get_attribute`, `execute_atom`, `find_relative`),
and the whole BiDi surface (`bidi_*`, including network interception).

Returned `char*` are **caller-owned** — free with `free_string`. `rust/` and
`python/selenium/_native.py` are the cleanest 1:1 references for the full
symbol table.

## Build / test (aeb)

`aeb` is the build runner; there is no Bazel, no Make. Pins live in
`ci/versions.env` — **that file is SOURCED by `ci/toolchain.sh`**, so it must
stay valid shell.

```sh
aeb selenium_core/.build.ae        # the engine -> libselenium_core.so
aeb <lang>/.tests.ae               # one binding (source tree)
aeb <lang>/.example.ae             # one binding (the published artifact)
aeb .presubmit.ae                  # everything
ci/run.sh --strict                 # presubmit + honest coverage; CI should use --strict
ci/coverage.sh                     # "what could this box actually test?"
```

The engine `.so` is handed to bindings via `SELENIUM_CORE_LIB`.

**`.presubmit.ae` takes well over an hour.** Do not wrap it in a short
`timeout`; you will kill it and mistake that for a hang or a slow run. (Done
twice in one session. Both times I reported a result I did not have.)

## Consumer-install proofs

`docs/Consumer-Install.md` is the full story. The short version: `.tests.ae`
runs against the SOURCE tree and therefore **cannot see a packaging break**.
`.example.ae` builds the distributable, installs it clean with
`SELENIUM_CORE_LIB` unset, and drives real Chrome from it. When these were first
run (2026-09-13) four of eleven were broken — including a Python wheel that
shipped no engine `.so` at all — while every corresponding `.tests.ae` was
green. They are now part of `.presubmit.ae`. `swift/` still has none, and swift
is exactly where a consumer-only bug was found by hand.

## Selenium 4.x parity — what "done" means

Two separate axes, measured separately (README has the numbers):

- **Protocol (engine)**: ahead. The route table carries the W3C set plus
  Selenium 4's extensions — shadow root, print, computed role/label, WebAuthn,
  FedCM, Grid downloads, `se:` log/file.
- **Surface (bindings)**: behind, and that is where the work is. Measure by
  diffing against the real thing — `pip install selenium==4.44` and introspect,
  or `javap` the `selenium-api` / `selenium-support` jars. Do not guess.

Deliberately NOT ported: CDP and the generated `devtools/vNNN/` trees (BiDi is
the path), pinned scripts (deprecated upstream), `mobile`/`orientation`
(pre-W3C), and driver-lifecycle internals (`Service`, `SeleniumManager`) because
the engine owns those.

Anything not yet given an ergonomic binding surface is still reachable through
the public generic hatch — `driver.execute("<command>", params)`. Verified live
against Chrome for the WebAuthn and log-type commands.

## Gotchas / hard-won

- **A green node may not have run.** aeb before v0.308 reported `tests PASSED`
  for a node whose compiler was absent (`| tee` ate the exit code). Fixed
  upstream, but `ci/coverage.sh` still exists because it answers a different
  question: *could this box test X at all*. `prereq()` under-states — probe by
  **running** the tool, not with `command -v`: `swift` was on PATH and unable to
  execute (missing `libncurses.so.6`).
- **A relative path in a package manifest works in-tree and fails for every
  consumer.** `swift/Package.swift` had `-L native`, resolved against the
  LINKER's cwd — ours only while we build it ourselves. Absolute, computed at
  manifest-evaluation time (`#filePath`), is the fix. `crystal` (`__DIR__`),
  `nim` (`currentSourcePath`) and `zig` (`b.pathFromRoot`) already do this.
  servirtium-vcr hit the identical bug and records that its `.tests.ae` stayed
  green throughout.
- **Renames rot the packaging lists, silently.** The Python package became
  `selenium` but `.package.ae` still staged the `.so` into `selenium_core/native/`
  → the wheel shipped no engine. The npm package became `selenium-webdriver` but
  the consumer still `require`d `selenium-core`. The Rust crate gained four
  modules the staging list never learned about. **When you rename or add a
  module, grep the `.package.ae` / `.example.ae` / `example/` triple.**
- **Ruby must be stdlib-only, and the stdlib keeps shrinking.** `base64` left
  the default gems in 3.4 and `webrick` in 3.0; minitest 6 dropped `mock.rb`
  entirely (so `Object#stub` is gone). Use `[x].pack('m0')` / `.unpack1('m')`,
  a plain `TCPServer`, and a real subclass instead of a stub. The gemspec
  promises no runtime dependencies — keep that true for the tests too.
- **The JS surface is async.** `864ffb1` moved it to mainstream
  selenium-webdriver's shape: `getTitle()`, `getText()`, promise-returning
  `get()`. `abi_test.js` pins that. The underlying FFI still BLOCKS the event
  loop, which is why the live test's content server runs out-of-process — an
  in-process one cannot answer while an `await d.get()` is inside its blocking
  round-trip.
- **Chrome / chromedriver version skew is the usual cause of a live-test
  failure.** `~/.cache/selenium` accumulates drivers; a 153 driver against a
  152 browser fails with a clear message that is easy to miss inside a wall of
  BEAM/erlang binary noise.
- **Live tests leak browsers, and that is how you OOM the box.** A test whose
  session is never quit leaves chromedriver + Chrome alive. 28 of them plus a
  pile of background waiters exhausted memory in one session. After a live run:
  `pkill -f 'cache/selenium'`. This is also how a "hang" happens: orphans inherit
  the test's stdout pipe and hold the write end open, so whoever is reading it
  (aeb) blocks forever on a test that finished in seconds. That was `aeb
  d/.tests.ae` for a while — the cause was the D binding's `quit()` not issuing
  the W3C `DELETE /session`, so **check teardown before blaming the runner**.
- **`ci/versions.env` is sourced.** When editing it programmatically, note that
  `AETHER_REF=` appears inside the header comment BEFORE the real assignment —
  slicing on the first match mangles the file into invalid shell. (Done. Caught
  by trying to source it.)
- **The engine normalizes; the binding does not.** See "The one rule". Tests
  that assert otherwise are testing the wrong layer.
- **A block setter called at node level silently does nothing.**
  `python.pip("pytest")` at the top of a `bldr.build()` writes onto the GRAPH
  ctx, not `install()`'s block, so the dep vanishes and the venv gets only base
  pip — the suite then fails with "No module named pytest" and sends you looking
  at aeb. Correct grammar is `python.install() { pip("pytest") }`. Same family as
  ruby's `bundle()`. aeb v0.310 hard-errors on the misuse; before that it is
  silent. To audit: cross-check every top-level `<sdk>.<fn>(` in a node against
  `builder <fn>(` in `~/.local/share/aeb/lib/<sdk>/module.ae` — allowing for
  builders that take arguments, e.g. `kotlin_test(test_class)`.

## Open, known-broken

Keep this list honest — delete an entry when it is fixed, not before.

- **`aeb aether/.tests.ae` fails at the LINK step.** The five
  `aether_pure_tls_client_*` entry points are emitted non-static into every TU
  that transitively imports `std.http.client`, so the two TUs aeb links collide.
  305 definitions are shared between those TUs and only these five clash; the
  rest are static. Filed as
  `../aether/asks/pure-tls-client-defined-non-static-in-every-tu.md`. **Not
  worked around here** — there is no honest selaenium-side fix, and
  restructuring the repo to dodge a codegen bug would only hide it.
- **`aeb scala/.tests.ae` fails.** `scala.scalac_test` compiles with an EMPTY
  compiler classpath, so `java -cp '' dotty.tools.dotc.Main` cannot find its own
  main class. The `scalac` on PATH is fine and unused — aeb runs the resolved
  jars on the JDK. Filed as `../aeb/asks/scalac-test-compiler-classpath-empty.md`;
  aeb main (`0959a64`, unreleased) makes it fail with a message naming the real
  cause instead. Removing the `env()` is NOT a fix: a JVM-family binding needs
  `SELENIUM_CORE_LIB` to find the engine at run time.
- **`swift/` has no `.example.ae`**, and swift is exactly where a consumer-only
  bug was found by hand (a relative `-L` in `Package.swift`). Worth adding.
  Swift on this box also needs `libncurses.so.6` and `libxml2.so.2`, sonames
  Arch does not ship.

Fixed since this file was written, kept as a record of what the symptoms looked
like: the D binding's `quit()` never issued the W3C `DELETE /session` (leaked
~14 processes a run, and the orphans wedged `aeb d/.tests.ae` for as long as you
let it run — it now finishes in 17s); `core.stdc.stdlib.exit()` in the D test
skipped every `scope(exit)`, which hid that; crystal's trailing `while`;
`aether/webdriver.ae`'s typed struct-pointer parameter; and `python.pip()` being
called at node level (ours, not aeb's — see the gotcha above).

## The `asks/` convention

Upstream bugs in `ae` / `aeb` get written up in `asks/` as a markdown file:
symptom with real output, cause, workaround, suggested fix. Mark one **FIXED**
in place with the upstream commit when it lands — do not delete it, so the
symptom stays searchable. Two filed this way were fixed in aeb v0.308/v0.309.

## Repo geography

```
selenium_core/   the engine + the C ABI + drivermgr + BiDi + atoms
selenium_core/tests/  pure-Aether probes (no browser, no FFI)
grid/            the standalone Grid hub (hub.ae) + hubcore.ae (pure) + tests
<lang>/          one thin binding each — see the README tables
ci/              versions.env (pins, SOURCED) · toolchain.sh · run.sh · coverage.sh
asks/            upstream ae/aeb bugs, with FIXED markers
docs/            Architecture · Grid · Consumer-Install · Atoms · BiDi · ...
target/          aeb output; target/.aeb/logs/<node>.log is where the REAL
                 error usually is when a node fails opaquely
```

Siblings: `../aether` (the language), `../aeb` (the build runner — its
`CHANGELOG.md` is how you find out what a bump actually changed), and
`../servirtium-vcr` (same design, further along; read its `LLM.md`).
