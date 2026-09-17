# selenium (Swift)

Selenium WebDriver for Swift — a thin FFI binding over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The binding carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. Swift calls the engine's flat C ABI (`aether_sel_embed_*`)
directly through the `CSeleniumCore` module map — no glue `.c`, no second copy
of the marshalling rules — with only Foundation's `JSONSerialization` doing the
(de)serialization on the seam.

Unlike the dynamically-loaded bindings (ruby/python/…), Swift **links the engine
at build time**, so the engine `.so` must be present when you `swift build` — it
is not fetched at run time. `Package.swift` also emits an rpath so the built
product finds it later with no `LD_LIBRARY_PATH`.

> **Name note.** This package's library product is named `Selenium`. It is not
> published to a public Swift index (no [Swift Package
> Index](https://swiftpackageindex.com) listing), so consume it from your shop's
> own source — a `.package(path:)` or `.package(url:)` dependency pointing at
> this repo. Your platform team makes the engine available (below).

## Using it (Swift app developer)

Add `Selenium` as a package dependency from wherever your shop provides it, then:

```swift
import Selenium

let driver = try WebDriver.headlessChrome(commandExecutor: "http://127.0.0.1:9515")
try driver.get("https://example.com")
print(try driver.title())
print(try driver.findElement(By.id("main")).text())
driver.quit()
```

`WebDriver.headlessChrome(commandExecutor:)` starts a headless-Chrome session
against a running chromedriver (or Grid) at that URL (the argument defaults to
`http://127.0.0.1:9515`); `WebDriver.chrome(...)`, `firefox`, `edge`, `safari`
and their `headless*` variants are there too, plus `WebDriver.localChrome(...)`,
which has the engine spawn its own chromedriver (no driver on PATH, no Grid).
Finds take a one-arg `By` locator (`By.id`, `By.css`, `By.xpath`, `By.className`,
…), matching Selenium 4.x. Calls that touch the remote end `throw` a typed
`WebDriverError` carrying the W3C error code (`-1` = transport); `quit()` is
best-effort and does not throw.

## Building it (the link-time story)

The engine `.so` directory is resolved in `Package.swift` **at
manifest-evaluation time** — it must be, because a relative `-L native` resolves
against whatever directory the linker runs in, which the moment the package is
consumed as a dependency is the **consumer's** directory, not ours (it builds in
place and then fails with `cannot find -lselenium_core` for every downstream
user). `#filePath` anchors the search to the manifest itself, so every copy of
the package computes its own location. The manifest searches, in the same order
as the link-time reference (`rust/build.rs`) — highest priority first:

1. `SELENIUM_CORE_LIB` — an explicit path to the `.so` (its parent dir is used)
2. the package's own bundled `native/` (a published package ships the `.so` there)
3. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
4. `../selenium_core/native` — the monorepo layout (this package next to core/)

Every candidate dir that actually holds the engine becomes a `-L` and
`-Xlinker -rpath` entry, so the linker takes the first that has
`libselenium_core` and the built product locates it at run time; if none exists
yet, bundled `native/` is emitted so the link error names a stable path. So a
dev with **no Aether toolchain** runs `scripts/fetch-engine.sh` once, then
`swift build`/`swift test` just works — no wrapper needed:

```sh
scripts/fetch-engine.sh        # once: download + cache the engine
swift build                    # then build/test normally
swift test
```

The engine release tag this package pins is `engineVersion` in `Package.swift`
(matching `scripts/fetch-engine.sh` and every other binding).

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the cache
`Package.swift` searches:

```sh
scripts/fetch-engine.sh        # download + verify + cache libselenium_core
```

Or set `SELENIUM_CORE_LIB=/abs/path/libselenium_core.so`. `TAG=vX.Y.Z` pins a
release, `FORCE=1` re-fetches. The fetch downloads from THIS project's GitHub
releases, verifies the `.sha256`, and caches under
`$XDG_CACHE_HOME/selaenium/<tag>/`. (The `aeb`/`ae` toolchain that builds the
engine from source is covered in the top-level README; consuming a fetched
engine needs none of it.)

## Layout

```
Package.swift                          resolves + links the engine .so, bakes the rpath
Sources/CSeleniumCore/                 the C ABI as a Swift-importable module
  include/selenium_core.h              the aether_sel_embed_* declarations
  include/module.modulemap             the module map exposing them to Swift
Sources/Selenium/Selenium.swift        the idiomatic surface: By, WebDriver /
                                       WebElement / ShadowRoot, Keys, Select,
                                       Actions, Wait, driver orchestration,
                                       WebDriver-BiDi
native/                                where a published package's engine .so is bundled
Tests/SeleniumTests/FfiTests.swift     no-browser FFI facts
Tests/SeleniumTests/SurfaceTests.swift no-browser ABI-surface facts
Tests/SeleniumTests/LiveTests.swift    live-Chrome + live-Firefox smoke (self-skips
                                       without a driver)
.tests.ae                              aeb node → stages the engine + `swift build`/`test`
```
