# AGENTS.md — notes to self (agent/LLM working on selaenium)

The rules and the map, in one file: short, opinionated, written for an agent
picking up mid-task. Re-read at the start of every session. **The code is the
source of truth; this exists so your first attempt lands clean.** Loaded as this
repo's project instructions (`CLAUDE.md` is just `@AGENTS.md`). Modelled on the
sibling `../servirtium-vcr/LLM.md`, which is worth reading too — the same design,
further along, and its "Gotchas / hard-won" list has repeatedly applied here
verbatim. (This file was `LLM.md` until it replaced the stale Bazel-era
`AGENTS.md`; a few older docs may still say "LLM.md".)

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

**Desktop is not browser-only.** The same engine drives desktop applications
through any W3C desktop driver (WinAppDriver, Appium mac2, KDE's AT-SPI one):
desktop mode is decided from the caller's capabilities, By-normalization stops
rewriting id/name/class name to CSS, and the JS-atom commands
(isDisplayed/getAttribute/getText) route to real W3C endpoints because a
desktop driver has no JavaScript engine. No binding carries any of that. Proven
live against Kate (Linux) and Calculator (macOS) — see `docs/Desktop.md` and
`selenium_core/tests/{atspi,mac2}_live.ae`.

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
- **A live test that fails in a back-to-back sweep may just be contention.**
  Ten nodes in a row, each driving real browsers, is enough to make a
  `new session: recv timeout or I/O error` appear — `rust` did exactly that, then
  passed 6/6 run alone a minute later. Re-run the node on its own before calling
  it a regression, especially right after a toolchain bump where a real
  regression is what you are expecting to see.
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

### A non-answer is not a negative answer

The single most expensive class of bug in this repo's history, in five costumes:

- `cmd | tee` ate a runner's exit code, so nine aeb runners printed "tests PASSED"
  on a failing suite.
- A node whose toolchain was absent reported green, so a wall of skips read as
  coverage. (`ci/coverage.sh --strict` exists because of this.)
- A live test self-skipped on `SEL_*` env that nothing ever set, so 25
  assertions — the shadow-DOM ones — had never once run.
- A release watcher polled a rate-limited `api.github.com`, got 403, and recorded
  "not released yet" for the whole window.
- A release watcher polled the release TAG page, which returns 200 minutes
  before the binaries upload, and reported an uninstallable release as ready.

Every one is a NON-answer or a PROXY answer recorded as a definite answer, and
every one fails toward the good-looking outcome, so nothing prompts you to look
again. Two independent sessions made the identical wrong correction to the
fourth one (API -> tag page) within an hour, which is why it is written down.

When you write a check:

- Assert the property you actually depend on (is it INSTALLABLE), not a proxy
  that leads it (is it TAGGED).
- Make the probe prove it discriminates — run a control you know must fail. A
  probe that cannot produce a negative is not measuring anything.
- Treat "I could not tell" as its own outcome and say so. Never fold it into the
  negative branch.

### When the bug moves every time you look at it, suspect the compiler

The Grid `inuse` hunt burned six rounds of bisection because every probe we added
made the symptom vanish. A node POSTed `inuse:3`, the hub stored `0`, and:
adding a debug trace fixed it, adding a gate fixed it, dropping to `-O0` fixed it,
reordering a helper fixed it. That pattern reads as memory corruption or a stack
layout accident, and we chased both. It was neither.

gcc 16's interprocedural constant propagation had folded a live `int` parameter
to a constant. `registry__row(id, address, browsers, max, inuse, now_ms)` has two
call sites — `register()` passes a literal `0` for `inuse`, `_drop_and_add()`
passes a value parsed from the request body — and gcc propagated the literal into
the function body and discarded the live argument. One instruction:
`xorl %edi,%edi` where a correct build emits `movl %r12d,%edi`, the 5th SysV
integer argument. Every "fix" we added was a new caller or a new call, which
changed IPA-CP's lattice. The Heisenbug WAS the bug's signature.

What to take from it:

- **A silent sanitizer is evidence, not a gap.** ASAN and UBSAN both ran the
  program while it misbehaved and reported zero errors. That is not "the
  sanitizer missed it" — it is positive evidence against a memory error or UB,
  and it should have moved us to codegen several rounds earlier than it did.
- **Bisect the compiler, not just the source.** `gcc -Q --help=optimizers` diffs
  `-O1` against `-O2`; bisecting those ~50 flags took under an hour and named the
  pass. Then prove it both ways: remove the flag from `-O2` AND add it to a clean
  `-O1`. A one-directional result is still perturbation.
- **Get it to compile time.** The repro turned out to need no linking and no
  running — emit the C, preprocess once, `gcc -O2 -S`, read the asm. A
  compile-time reproducer is immune to the environment and is what an upstream
  compiler tracker will ask for.
- **Diff the binaries, not the source.** Disassembling broken vs fixed and
  comparing every function found the one that differed. It also killed our
  standing theory: `register_node_handler`, which we had assumed was the fragile
  frame, was byte-identical in both.
- **Neither build cache keys on the compiler.** `~/.aether/cache` and aeb's
  result cache both ignore the C compiler and its flags, so a flag change (or a
  gcc upgrade) silently keeps serving old objects. `rm -rf target/` is not
  enough. Clear `~/.aether/cache` or you will measure the cache.

Full writeup, flag matrix and the asm diff:
`asks/toolchain-gcc16-ipa-bit-cp-miscompiles-emitted-c.md`.

### An error message that recommends a route is a claim, and claims go stale

The JSONWP refusal in the engine told the reader to "drive it through
appium-windows-driver". True when written, and wrong within days: WinAppDriver
is unmaintained and its sessions fail outright on current Windows 11, so the
message confidently sent people down a dead end — and it only ever appears when
someone is *already* lost and most likely to trust it. It cost the sibling
proving Windows a debugging round.

The same stale pointer had also been copied into a test's SKIP message and a
build-node comment, so fixing the engine alone would have left two live traps.

- A message that names a tool, version, flag or URL has a shelf life. When the
  recommendation changes, **grep for it** — it is rarely in one place.
- Prefer naming the *property* you need over the product that currently has it
  ("a W3C endpoint", not "appium-windows-driver") when you are not certain the
  product will keep having it.
- **Keep the history, delete only the advice.** The comments explaining "this
  used to say X; X launches, listens, and then fails" are what stop the next
  reader re-deriving the dead route from the same upstream README we both did.
  Deleting them resets the trap.

### A probe that cannot produce a POSITIVE is not measuring anything either

The negative-polarity version of this is above. The positive one bit us at the
end of the same hunt, and it is sneakier, because a blind detector reports the
result you were hoping for.

A retest script checked whether gcc had stopped folding a parameter to zero:

    grep -qE 'xorl[ \t]+%edi, %edi'   # never matches a tab under GNU grep

Inside an ERE **bracket expression**, `\t` is not a tab — it is the set
{space, backslash, `t`}. The detector could not match, so every run printed
"clean". Worse, it worked when pasted into an interactive shell here, where
`grep` resolves to a `ugrep` shim that *does* interpret `\t`, and failed only
under `#!/bin/bash`. A detector that lies only under automation is the worst
kind. Use `[[:space:]]`, or a literal tab.

It was caught because a second, independent measurement disagreed: the asm check
said "fixed", the runtime leg still returned the wrong value. Keep two
independent measurements even when one looks sufficient — the disagreement is
the signal, and with only the asm check a non-existent fix would have shipped.

So, for any probe, in both directions:

- Before trusting a verdict, prove the probe **discriminates** — feed it a case
  that must trip it and a case that must not. Abort rather than report if it
  fails either. The retest script does this now.
- Be suspicious of a check that only ever returns one answer. "Clean every time"
  and "broken every time" are both consistent with a detector that is not
  looking.

## Open, known-broken

Keep this list honest — delete an entry when it is fixed, not before.

- **`swift/` has no `.example.ae`**, and swift is exactly where a consumer-only
  bug was found by hand (a relative `-L` in `Package.swift`). Worth adding.
  Swift on this box also needs `libncurses.so.6` and `libxml2.so.2`, sonames
  Arch does not ship.

Fixed since this file was written, kept as a record of what the symptoms looked
like: `aeb aether/.tests.ae` failing at the LINK step on the five non-static
`aether_pure_tls_client_*` entry points (it links AND passes now, 2026-09-19);
`aeb scala/.tests.ae` failing because `scalac_test` spliced the `env()` export
prefix into the compiler-classpath slot (fixed upstream in aeb `9a1c520`,
shipped in v0.311); the D binding's `quit()` never issued the W3C `DELETE /session` (leaked
~14 processes a run, and the orphans wedged `aeb d/.tests.ae` for as long as you
let it run — it now finishes in 17s); `core.stdc.stdlib.exit()` in the D test
skipped every `scope(exit)`, which hid that; crystal's trailing `while`;
`aether/webdriver.ae`'s typed struct-pointer parameter; and `python.pip()` being
called at node level (ours, not aeb's — see the gotcha above).

## The `asks/` convention

Upstream bugs in `ae` / `aeb` get written up as a markdown file: symptom with
real output, cause, workaround, suggested fix. Mark one **FIXED** in place with
the upstream commit when it lands — do not delete it, so the symptom stays
searchable. Two filed this way were fixed in aeb v0.308/v0.309.

**File it where the fix belongs** — `~/scm/aeb/asks/` or `~/scm/aether/asks/`,
both checked out alongside this repo — and keep a copy here under `asks/`,
prefixed `aeb-` / `aether-`, with a header naming the upstream path and whether
it is still open. Filing only locally means the people who can fix it never see
it. Note the upstream may DELETE an ask it considers satisfied (aeb `909bc88`
removed eight), so the local copy is also the durable record: when one is closed
wrongly, re-file under a new name rather than editing a deleted file.

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
