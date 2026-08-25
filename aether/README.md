# Selenium WebDriver — Aether core

The core of Selenium WebDriver, ported to [Aether](https://github.com/aether-lang-dev)
as **one pure-Aether engine + thin per-language bindings**, built with
[`aeb`](https://github.com/aether-lang-dev/aeb) instead of Bazel. Same shape as
[`servirtium-vcr`](https://github.com/servirtium/servirtium-vcr) and
[`html-sanitizer`](https://github.com/…/html-sanitizer): the protocol logic
lives once, every language re-glues to it over a C ABI.

## The one rule

**Bindings carry no protocol logic.** The command catalog, the W3C
command→(method, path) route table, path templating, By/capabilities
normalization, the W3C error-envelope decode, and the HTTP round-trip to the
driver/Grid all live in `core/selenium_core.ae`. A binding opens a session,
issues commands by name with JSON params, reads back the result value or a typed
error, and closes. Anything smarter than marshalling belongs in `core/`.

## Layout

```
core/
  selenium_core.ae   the engine: route table, path templating, By, error map,
                     capabilities, and the std.http.client round-trip
  embed.ae           the flat C ABI (aether_sel_embed_*), handle-based
  _embed_strdup.c    the ~15-line caller-owned-string bridge (the only C)
  .build.ae          aeb node -> core/native/libselenium_core.so
core_tests/
  probe.ae           pure-Aether engine probe (no browser, no FFI)
  .tests.ae          aeb node that builds + runs the probe
python/
  selenium_core/     the Python binding (ctypes over the .so — runtime load)
    _native.py       library loader + ctypes prototypes (1:1 with embed.ae)
    _webdriver.py    the ergonomic surface: WebDriver, WebElement, By, errors
    __init__.py
  test/
    test_ffi.py         no-browser FFI test (loads the .so, marshals, error path)
    test_live_chrome.py live headless-Chrome end-to-end smoke test
  setup.py           wheel packaging; bundles native/*.so via package_data
  .package.ae        aeb node → builds the wheel with the engine .so inside
  .example.ae        aeb node → installs the wheel into a clean site + runs it
  example/
    consumer_example.py  runs from the INSTALLED package (ffi/discovery/live)
go/
  selenium.go        the Go binding (cgo over the .so — link-time)
  ffi_test.go        no-browser FFI test (Route/ErrorCode/Locator, transport err)
  live_test.go       live headless-Chrome end-to-end smoke test
  native/            bundled .so (cgo rpath self-locates ../core/native or here)
  .package.ae        aeb node → stages the engine .so into go/native/
  .example.ae        aeb node → a consumer module with NO core/ sibling go-runs it
  example/           the standalone consumer program (go.mod + main.go)
ruby/
  lib/selenium_core.rb            the require entry point
  lib/selenium_core/native.rb     Fiddle loader + prototypes (1:1 with embed.ae)
  lib/selenium_core/webdriver.rb  the ergonomic surface: WebDriver, WebElement, By
  selenium_core.gemspec           gem packaging; bundles lib/**/* incl. native/*.so
  spec/{ffi_test,live_test}.rb    minitest suites (no-browser + live Chrome)
  .tests.ae / .package.ae / .example.ae   aeb nodes
  example/consumer_example.rb     runs from the INSTALLED gem (ffi/discovery/live)
javascript/
  index.js                        the require entry point
  lib/native.js                   koffi loader + prototypes (1:1 with embed.ae)
  lib/webdriver.js                the ergonomic surface (synchronous; see note)
  package.json                    npm packaging; bundles native/ + lib/; koffi dep
  test/{ffi_test,live_test}.js    node:test suites (no-browser + live+surface)
  test/content_server.js          out-of-process content server for the live test
  .tests.ae / .package.ae / .example.ae   aeb nodes
  example/consumer_example.js     runs from the INSTALLED package (ffi/discovery/live)
java/
  src/org/seleniumhq/aether/*.java  Panama FFM binding: Native, Json (dep-free),
                                    WebDriver, WebElement, By, WebDriverError
  test/{TestFfi,TestLive}.java      JUnit-free main() harnesses (no-browser + live)
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
aeb core/.build.ae        # -> core/native/libselenium_core.so
aeb core_tests/.tests.ae  # pure-Aether engine probe (fast, no browser)

# Python binding (needs the .so via SELENIUM_CORE_LIB during dev):
SELENIUM_CORE_LIB="$PWD/core/native/libselenium_core.so" python3 python/test/test_ffi.py
SELENIUM_CORE_LIB="$PWD/core/native/libselenium_core.so" python3 python/test/test_live_chrome.py
```

## Status — end-to-end green ✅

Needs **Aether ≥ 0.558** (the `std.http.client` `Connection: close` framing fix;
without it the client hangs on chromedriver responses).

- **Engine** (`core/selenium_core.ae`): full W3C command map, path templating,
  By normalization, W3C error decode, HTTP round-trip. ✅ builds, ✅ 31/31 probes.
- **ABI** (`core/embed.ae`) + C bridge: ✅ builds to `libselenium_core.so`,
  13 exports.
- **Python binding** (ctypes, runtime load): ✅ FFI marshalling + error path
  (`test_ffi.py`, 7 cases), ✅ **live headless Chrome** (`test_live_chrome.py`).
- **Go binding** (cgo, link-time): ✅ FFI (`ffi_test.go`, 5 cases), ✅ **live
  headless Chrome** (`live_test.go`).
- **Ruby binding** (Fiddle, runtime load): ✅ FFI (`spec/ffi_test.rb`, 5 cases),
  ✅ **live headless Chrome** (`spec/live_test.rb`).
- **Node binding** (koffi / N-API, runtime load): ✅ FFI (`test/ffi_test.js`,
  5 cases), ✅ **live headless Chrome + surface** (`test/live_test.js`). The API
  is synchronous (the engine's FFI round-trip blocks) — the honest shape for a
  linked-in synchronous core; a note in `lib/webdriver.js` explains it, and the
  live test runs its content server out-of-process so a blocking `get()` can't
  freeze the server the browser fetches from.
- **Java binding** (Panama FFM — `java.lang.foreign`, no JNI/C shim): ✅ FFI
  (`test/TestFfi.java`, 7 checks), ✅ **live headless Chrome + surface**
  (`test/TestLive.java`). Pure `javac` (no Maven); a tiny dependency-free JSON
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
- Fifteen languages across eleven FFI mechanisms (ctypes / cgo / Fiddle / koffi /
  Panama FFM / P/Invoke / Rust extern-C / dart:ffi / Erlang NIF / Nim importc /
  Zig extern / Lua C-extension — the BEAM three share the NIF, the JVM family
  shares the Java jar) all drive the byte-identical `libselenium_core.so`.
  Thirteen are live-verified here; the two BEAM wrappers (Elixir, Gleam) are
  authored here and verified on a box with their compilers (catchyos).
- **Consumer install** (all three): ✅ the packaged wheel / Go module / gem
  stands alone with the `.so` bundled inside — clean-env install, no source tree,
  no env var — and drives real headless Chrome from the installed artifact
  (`*/.example.ae`).
- **Live browser** (all three bindings): ✅ a real headless Chrome session driven
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
