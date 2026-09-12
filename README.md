# Selenium WebDriver — Aether core

The core of Selenium WebDriver, ported to [Aether](https://github.com/aether-lang-dev)
as **one pure-Aether engine + thin per-language bindings**, built with
[`aeb`](https://github.com/aether-lang-dev/aeb) instead of Bazel. Same shape as
[`servirtium-vcr`](https://github.com/servirtium/servirtium-vcr) and
[`html-sanitizer`](https://github.com/…/html-sanitizer): the protocol logic
lives once, every language re-glues to it over a C ABI.

## Building it

The engine and bindings build with `aeb`, which needs the Aether toolchain
(`ae`) — and `aeb`'s installer needs an `ae` to target, so they install in that
order. aeb's [`get.sh`](https://github.com/aether-lang-dev/aeb/blob/main/get.sh)
ensures both from a bare clone: binary-first per platform (source fallback), and
it fetches the pinned Aether via Aether's own `get.sh`. Aether compiles to C, so
the only prerequisites for a source fallback are a C compiler and GNU make. Pins
live in [`ci/versions.env`](ci/versions.env) — keep the one-liner's numbers in
step with it.

One line installs a pinned `ae` (>= `AE_PIN`) THEN a pinned `aeb`, into
`~/.local` (no sudo; `PREFIX=` to override):

```sh
curl -fsSL https://raw.githubusercontent.com/aether-lang-dev/aeb/main/get.sh \
  | AE_PIN=0.650.0 AEB_REF=v0.307 sh
```

`get.sh` is also a sourceable library — a CI step can source it (set
`AEBGET_SOURCE_ONLY=1` so sourcing only *defines* the functions) then drive it:

```bash
AEBGET_SOURCE_ONLY=1 . <(curl -fsSL https://raw.githubusercontent.com/aether-lang-dev/aeb/main/get.sh)
AE_PIN=0.650.0 AEB_REF=v0.307 aeb_bootstrap
```

Then build the engine (the one thing every binding needs) and, for a given
language, its binding + tests:

```sh
aeb selenium_core/.build.ae        # the pure-Aether engine -> libselenium_core.so
aeb selenium_core/.build.ae python/.tests.ae   # + a binding (needs that language's toolchain)
```

## The one rule

**Bindings carry no protocol logic.** The command catalog, the W3C
command→(method, path) route table, path templating, By/capabilities
normalization, the W3C error-envelope decode, and the HTTP round-trip to the
driver/Grid all live in `selenium_core/selenium_core.ae`. A binding opens a session,
issues commands by name with JSON params, reads back the result value or a typed
error, and closes. Anything smarter than marshalling belongs in `selenium_core/`.

## Bindings

**Twenty-eight** language bindings drive the byte-identical
`libselenium_core.so` (one `.tests.ae` node each). Classic Selenium shipped five
official clients (Java, Python, Ruby, JavaScript, .NET), each a full
reimplementation of the protocol. Here all five are re-glued as thin FFI layers
over the shared engine — and twenty-three more come along, several of them
essentially free, because a runtime family only has to be bridged once:

| Family | Bridged once as | Languages riding it |
|--------|-----------------|---------------------|
| BEAM   | one Erlang NIF (`selenium_nif`) | Erlang, Elixir, Gleam, LFE |
| JVM    | one Panama FFM jar              | Java, Kotlin, Clojure, Groovy, Scala |
| .NET   | one P/Invoke assembly           | C#, F# |

### Carried over from classic (5 — now thin FFI bindings)

| Language          | FFI mechanism                        |
|-------------------|--------------------------------------|
| Java              | Panama FFM (`java.lang.foreign`)     |
| Python            | ctypes (runtime load)                |
| Ruby              | Fiddle (runtime load)                |
| JavaScript (Node) | koffi / N-API (runtime load)         |
| .NET (C#)         | P/Invoke                             |

### New languages (23 — not in classic Selenium)

| Language | FFI mechanism                          |
|----------|----------------------------------------|
| C        | the C ABI directly (header + link)     |
| C++      | header-only wrapper over the C ABI     |
| Go       | cgo (link-time)                        |
| Rust     | `extern "C"` + `build.rs` (link-time)  |
| Dart     | `dart:ffi`                             |
| Swift    | C interop via a module map             |
| Crystal  | `@[Link]` + `lib` (link-time)          |
| Nim      | `importc` (link-time)                  |
| Zig      | `@extern` (link-time)                  |
| D        | `extern(C)` + dlopen                   |
| Haskell  | `foreign import ccall` (link-time)     |
| Julia    | `ccall`                                |
| Lua      | Lua 5.4 C extension                    |
| PHP      | PHP FFI (`FFI\CData`)                  |
| Erlang   | Erlang NIF                             |
| Elixir   | rides the Erlang NIF (BEAM)            |
| Gleam    | rides the Erlang NIF (BEAM)            |
| LFE      | rides the Erlang NIF (BEAM)            |
| Kotlin   | JVM interop over the Java FFM jar      |
| Clojure  | JVM interop over the Java FFM jar      |
| Groovy   | JVM interop over the Java FFM jar      |
| Scala    | JVM interop over the Java FFM jar      |
| F#       | .NET interop over the P/Invoke assembly |

Nineteen distinct FFI mechanisms in all — the BEAM four share the NIF, the JVM
five share the jar, and the two .NET languages share the assembly, so one engine
reaches twenty-eight languages.

## Layout

```
selenium_core/
  selenium_core.ae   the engine: route table, path templating, By, error map,
                     capabilities, and the std.http.client round-trip
  embed.ae           the flat C ABI (aether_sel_embed_*), handle-based
  _embed_strdup.c    the ~15-line caller-owned-string bridge (the only C)
  .build.ae          aeb node -> selenium_core/native/libselenium_core.so
selenium_core/tests/
  probe.ae           pure-Aether engine probe (no browser, no FFI)
  .tests.ae          aeb node that builds + runs the probe
python/
  selenium/          the Python binding, at the MAINSTREAM import paths
    _native.py       library loader + ctypes prototypes (1:1 with embed.ae)
    _webdriver.py    the one implementation: WebDriver, WebElement, ShadowRoot,
                     Timeouts, By, errors
    webdriver/       selenium.webdriver.{common,remote,chrome,support}.* — the
                     Selenium 4.x module tree, re-exporting from _webdriver
    common/          selenium.common.exceptions
  test/
    test_ffi.py         no-browser FFI test (loads the .so, marshals, error path)
    test_abi_surface.py no-browser parity facts (the mainstream surface, no .so)
    test_live_chrome.py live headless Chrome: smoke, atoms, BiDi, shadow DOM,
                        virtual authenticator, timeouts
    test_live_surface.py live surface coverage (cookies/windows/actions/...)
  setup.py           wheel packaging; bundles native/*.so via package_data
  .package.ae        aeb node → builds the wheel with the engine .so inside
  .example.ae        aeb node → installs the wheel into a clean site + runs it
  example/
    consumer_example.py  runs from the INSTALLED package (ffi/discovery/live)
go/
  selenium.go        the Go binding (cgo over the .so — link-time)
  ffi_test.go        no-browser FFI test (Route/ErrorCode/Locator, transport err)
  live_test.go       live headless-Chrome end-to-end smoke test
  native/            bundled .so (cgo rpath self-locates ../selenium_core/native or here)
  .package.ae        aeb node → stages the engine .so into go/native/
  .example.ae        aeb node → a consumer module with NO selenium_core/ sibling go-runs it
  example/           the standalone consumer program (go.mod + main.go)
ruby/
  lib/selenium-webdriver.rb       the require entry point (mainstream gem name)
  lib/selenium/native.rb          Fiddle loader + prototypes (1:1 with embed.ae)
  lib/selenium/webdriver.rb       the surface: Driver, Element, By, Select, Wait
  selenium-webdriver.gemspec      gem packaging; bundles lib/**/* incl. native/*.so
                                  — NO runtime gem dependencies (stdlib only)
  spec/*.rb                       minitest suites (ffi / facade / convenience /
                                  surface / live Chrome)
  .tests.ae / .package.ae / .example.ae   aeb nodes
  example/consumer_example.rb     runs from the INSTALLED gem (ffi/discovery/live)
javascript/
  index.js                        the require entry point
  lib/native.js                   koffi loader + prototypes (1:1 with embed.ae)
  lib/webdriver.js                the surface — async/Promise-returning, matching
                                  mainstream selenium-webdriver (see note)
  package.json                    npm packaging; bundles native/ + lib/; koffi dep
  test/{abi,ffi,live}_test.js     node:test suites (surface parity / no-browser /
                                  live+surface)
  test/content_server.js          out-of-process content server for the live test
  .tests.ae / .package.ae / .example.ae   aeb nodes
  example/consumer_example.js     runs from the INSTALLED package (ffi/discovery/live)
java/
  src/main/java/org/openqa/selenium/**  Panama FFM binding at the MAINSTREAM
                                    package: WebDriver, WebElement, By, Keys,
                                    Cookie, Actions, support.ui.{Select,
                                    WebDriverWait,ExpectedConditions}, print.*,
                                    plus Native + a dependency-free Json
  src/test/java/**                  JUnit 5: FfiTest, LiveTest, AbiSurfaceTest
  .tests.ae / .package.ae / .example.ae   aeb nodes (plain javac + jar, no Maven)
  example/ConsumerExample.java      runs from the INSTALLED jar (ffi/discovery/live)
dotnet/
  SeleniumCore/*.cs                 P/Invoke binding: NativeMethods, NativeLoader,
                                    WebDriver, WebElement, By, WebDriverError
  SeleniumCore/SeleniumCore.csproj  class lib; packs the .so as a runtime asset
  SeleniumCore.Tests/Program.cs     console harness (no xunit): ffi + live+surface
  .tests.ae / .package.ae / .example.ae   aeb nodes (dotnet build/pack; net8.0)
  example/                          NuGet consumer app (Program.cs + Consumer.csproj)
rust/
  src/lib.rs                        extern "C" binding + WebDriver/WebElement/By
  src/json.rs                       hand-rolled JSON (no serde → fully offline)
  build.rs                          links the .so + publishes native_dir metadata
  Cargo.toml                        links = "selenium_core"; zero dependencies
  tests/{ffi_test,live_test}.rs     cargo tests (no-browser + live+surface)
  .tests.ae / .package.ae / .example.ae   aeb nodes
  example/                          consumer crate (path dep + rpath-propagating build.rs)
```

## Selenium 4.x parity

The engine is *ahead* of classic Selenium in protocol coverage and *behind* it in
binding ergonomics — those are separate axes, so they are measured separately.

**Protocol (the engine).** The route table in `selenium_core/selenium_core.ae`
carries the full W3C command set plus the extensions Selenium 4 ships: shadow
root, print-to-PDF, computed role/label, WebAuthn virtual authenticators, FedCM,
the Grid download endpoints, and `se:` log/file extensions. Nothing in the W3C
spec is missing.

**Surface (the bindings).** Measured by diffing the binding's public API against
the real Selenium 4.44 packages (`pip install selenium==4.44`; `selenium-api` +
`selenium-support` jars read with `javap`):

| Binding | Public names present | Notes |
|---------|---------------------|-------|
| Python  | 312 / 362 (86%) | `WebElement`, `Keys`, `ActionChains`, `Select`, `SwitchTo`, `Alert`, `WebDriverWait` and `selenium.common.exceptions` are at 100%; `ChromeOptions` 97% |
| Java    | 191 / 198 (96%) | `WebDriver`, `WebElement`, `Select`, `WebDriverWait` and `ExpectedConditions` are at 100% |

**Still behind, and deliberately so.** The remaining gaps are mostly things a
W3C-pure engine has no business emulating, or that upstream has deprecated:

- **CDP** (`execute_cdp_cmd`, `start_devtools`, the generated `devtools/vNNN/`
  trees — ~250 modules of upstream's wheel). BiDi is the supported path here.
- **Pinned scripts** (`pin_script` / `unpin` / `get_pinned_scripts`, and Java's
  `JavascriptExecutor.pin`) — deprecated upstream.
- **Driver lifecycle internals** (`start_session`, `start_client`, `stop_client`,
  `Service`, `SeleniumManager`): this engine owns driver resolution and launch
  itself, through `ensure_driver` / `resolve_driver` on the C ABI.
- **`mobile` / `orientation`**: legacy JSON-Wire-Protocol, not W3C.

Genuinely missing and worth doing: the BiDi *module* accessors Python exposes
(`driver.network`, `driver.script`, `driver.browsing_context`, …) over the BiDi
that already works; `file_detector` for local-file upload to a remote Grid (the
engine already routes `uploadFile`); and the FedCM dialog wrapper (the engine
already routes all eight FedCM commands). Until those land, every one of them is
reachable through the public generic hatch — `driver.execute("<command>", params)`
in Python, `execute(...)` in Java — which goes through the same route table, so
no functionality is actually locked away.

## Two test layers, and what each proves

- **`.tests.ae`** (per binding): the binding works against the source tree with
  the engine `.so` handed in via `SELENIUM_CORE_LIB`. Proves the *binding*.
- **`.package.ae` + `.example.ae`** (per binding): the distributable — a wheel /
  a Go module — with the engine `.so` **bundled inside**, installed into a clean
  environment (no source tree on the path, `SELENIUM_CORE_LIB` unset), then run.
  Proves a naive `pip install` / `go get` actually works. Both drive real
  headless Chrome from the *installed* artifact.

## The C ABI (`aether_sel_embed_*`)

Handle-based: N independent sessions per process. `open(base_url)` returns an
opaque handle; `execute(h, name, params_json)` runs one command, returning 0 on
success, a W3C error code on a protocol error, or -1 on transport failure;
drain the result via `last_value` (JSON payload), `last_error_code`,
`last_error`, `last_status`, `session_id`. Pure helpers `by_locator`, `route`,
`error_code` are also exported so a binding shares the ONE normalization path.
Returned `char*` are caller-owned — free with `free_string`.

## Build & test

```
aeb selenium_core/.build.ae        # -> selenium_core/native/libselenium_core.so
aeb selenium_core/tests/.tests.ae  # pure-Aether engine probe (fast, no browser)

# Python binding (needs the .so via SELENIUM_CORE_LIB during dev):
SELENIUM_CORE_LIB="$PWD/selenium_core/native/libselenium_core.so" python3 python/test/test_ffi.py
SELENIUM_CORE_LIB="$PWD/selenium_core/native/libselenium_core.so" python3 python/test/test_live_chrome.py
```

## Status — end-to-end green ✅

Needs **Aether ≥ 0.638** — the floor recorded in [`ci/versions.env`](ci/versions.env),
which pins `ae` 0.650.0 and `aeb` v0.300. 0.638 is where `std.http.ws_connect`
(the BiDi WebSocket client) and the single-file-module fix that this repo's
`aether.toml` depends on both land. Building with an older `aeb` than the pin
fails early with `unresolved import 'cache'`.

- **Engine** (`selenium_core/selenium_core.ae`): full W3C command map, path templating,
  By normalization, W3C error decode, HTTP round-trip. ✅ builds, ✅ 31/31 probes.
- **ABI** (`selenium_core/embed.ae`) + C bridge: ✅ builds to `libselenium_core.so`,
  49 exports — the command seam plus driver orchestration (`resolve_driver` /
  `ensure_driver` / `stop_driver`), the atoms (`is_displayed`, `get_attribute`,
  `find_relative`) and the full BiDi surface (`bidi_*`, including network
  interception).
- **Python binding** (ctypes, runtime load): ✅ FFI marshalling + error path
  (`test_ffi.py`, 7 cases), ✅ surface parity (`test_abi_surface.py`, 43 cases),
  ✅ **live headless Chrome** (`test_live_chrome.py`, `test_live_surface.py`) —
  smoke, atoms, BiDi, shadow DOM, virtual authenticator, timeouts. 59 tests.
- **Go binding** (cgo, link-time): ✅ FFI (`ffi_test.go`, 5 cases), ✅ **live
  headless Chrome** (`live_test.go`).
- **Ruby binding** (Fiddle, runtime load): ✅ FFI (`spec/ffi_test.rb`, 5 cases),
  ✅ facade + convenience surface, ✅ **live headless Chrome** (`spec/live_test.rb`,
  `spec/surface_test.rb`). Stdlib only — no runtime *or test* gem dependencies,
  so it runs on a bare Ruby ≥ 3.4 (where `base64` and `webrick` are no longer
  default gems).
- **Node binding** (koffi / N-API, runtime load): ✅ surface parity
  (`test/abi_test.js`), ✅ FFI (`test/ffi_test.js`), ✅ **live headless Chrome +
  surface** (`test/live_test.js`). 29 tests. The public API is **async**
  (Promise-returning), matching mainstream `selenium-webdriver`; the underlying
  FFI round-trip still blocks the event loop while it runs, so the live test runs
  its content server out-of-process — an in-process server could not answer while
  an `await driver.get()` sits inside that blocking call.
- **Java binding** (Panama FFM — `java.lang.foreign`, no JNI/C shim): ✅ FFI,
  ✅ surface parity (`AbiSurfaceTest`), ✅ **live headless Chrome + surface**.
  46 JUnit 5 tests, at the real `org.openqa.selenium` package names. Pure `javac` (no Maven); a tiny dependency-free JSON
  codec keeps it library-free. Needs a JDK ≥ 22 and `--enable-native-access`.
- **.NET binding** (P/Invoke — `System.Runtime.InteropServices`): ✅ FFI
  (7 checks), ✅ **live headless Chrome + surface**. Uses `System.Text.Json`; a
  `[ModuleInitializer]` `DllImportResolver` handles library discovery. net8.0.
- **Rust binding** (link-time `extern "C"` + `build.rs`): ✅ FFI (5 cases), ✅
  **live headless Chrome + surface**. Zero external crates — a hand-rolled JSON
  module + a std-only content server keep it fully offline. A consumer's rpath is
  propagated across the crate edge via `links` + `DEP_SELENIUM_CORE_NATIVE_DIR`.
- **Dart binding** (dart:ffi, runtime load): ✅ FFI (5 cases), ✅ **live headless
  Chrome + surface**. Synchronous (FFI blocks the isolate), so the live test runs
  its content server out-of-process; the consumer self-locates its bundled `.so`
  via `Isolate.resolvePackageUri`.
- **BEAM family** (Erlang / Elixir / Gleam): one shared C NIF (`selenium_nif`)
  that Erlang owns and Elixir + Gleam load over the BEAM — the SAME compiled
  module, no second C source (exactly as the JVM family would layer over one jar).
  - **Erlang** (NIF): ✅ FFI + **live headless Chrome + surface** — live-verified.
  - **Elixir** (defdelegate to the NIF): authored; ✅ verify on a box with Elixir.
  - **Gleam** (`@external` to the NIF): authored; ✅ verify on a box with Gleam.
- **Nim binding** (importc + link-time): ✅ FFI + **live headless Chrome +
  surface**. std/json; `{.passL.}` links the engine with rpath.
- **Zig binding** (`@extern` + link-time, Zig 0.16): ✅ FFI + **live headless
  Chrome + surface**. std.json; build.zig links + rpaths the engine.
- **D binding** (`extern(C)` + link-time, dmd): ✅ FFI + **live headless Chrome +
  surface**. std.json; the `d` aeb SDK module (`dmd -run`) links + rpaths the engine.
- **Lua binding** (Lua 5.4 C extension): ✅ FFI + **live headless Chrome +
  surface**. A real C extension (Lua has no stdlib FFI) that dlopen's the engine;
  hand-rolled JSON. Builds a bundled 5.4 host on boxes whose interpreter is 5.3.
- **JVM family** (Kotlin, Clojure): consume the ONE Java FFM jar over seamless
  JVM interop — **no second FFI, no second `.so`** (one Java jar backs the whole
  JVM family, exactly as one Erlang NIF backs the BEAM family).
  - **Kotlin**: ✅ FFI + **live headless Chrome + surface** — live-verified.
    Needs Kotlin ≥ 1.9 (a modern kotlinc; Debian's 1.3 can't read JDK-22+ FFM
    bytecode). Adds a `headlessChrome { }` builder + element extensions.
  - **Clojure**: ✅ FFI + **live headless Chrome + surface** — live-verified.
    Adds a `with-chrome` macro + keyword `by`.
  - **Groovy**: a `withHeadlessChrome { }` closure form. Authored here; verified
    on a box with a modern Groovy (≥ 4) + JDK ≥ 22 — Debian's 2.4/JVM17 can't
    read the FFM binding, so it skips green here.
- **Haskell binding** (`foreign import ccall` + link-time): FFI + live surface.
  Dependency-light (base + bytestring; params/values as JSON strings). Authored
  here; verified on a box with GHC (skips green without it).
- Twenty-eight languages across nineteen FFI mechanisms all drive the
  byte-identical `libselenium_core.so` — see the Bindings table above for the
  per-language mechanism and the three runtime families (BEAM / JVM / .NET) that
  are each bridged only once.
- **Consumer install**: ✅ the packaged wheel / Go module / gem / jar / NuGet
  stands alone with the `.so` bundled inside — clean-env install, no source tree,
  no env var — and drives real headless Chrome from the installed artifact
  (`*/.example.ae`).
- **Live browser**: ✅ a real headless Chrome session driven
  entirely through the pure-Aether core. The whole pipeline: {Python ctypes | Go
  cgo | Ruby Fiddle} → libselenium_core.so → std.http.client → chromedriver →
  Chrome.
  - **Smoke**: newSession, get, find_element (By.ID + By.CLASS_NAME→CSS), click,
    send_keys, get_property, execute_script, typed NoSuchElement error, quit.
  - **Surface** (against a local HTTP server for a real cookie/nav origin):
    timeouts, back/forward history, cookies (add/get/get-one/delete), window
    handles + set/get rect, execute_script return shapes (scalar/array/object/
    args), W3C actions (a real pointer-click), and screenshots (valid PNG).
    Exhaustive in Python; a representative subset in Go and Ruby.

Two engine bugs found and fixed via the live test (both browser-only, invisible
to the offline probe until then): a dangling borrowed `base_url` FFI string in
the heap-boxed session struct (fixed with an owned copy), and a wrong JSON type
code in the error-envelope check (`== 4` ARRAY instead of `== 3` STRING) that
silently swallowed every WebDriver error as success — now pinned by the
`response_error_code` probe cases.

## Upstream siblings

`../aether` (the language), `../aeb` (the build runner), `../servirtium-vcr` and
`../html-sanitizer` (the one-engine-many-bindings layout this repo copies).
