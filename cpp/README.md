# selenium (C++)

Selenium WebDriver for C++ — a header-only RAII layer over the C client
([`../c/include/selenium.h`](../c/include/selenium.h)) and, through it, the
shared pure-Aether WebDriver engine (`libselenium_core`).
[`include/selenium.hpp`](include/selenium.hpp) owns the handle lifetimes
(`WebDriver` / `WebElement` / `ShadowRoot` / `DriverProcess` free on
destruction), turns error codes into a `WebDriverError` exception, and returns
`std::string`.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The C++ client carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. C++17, no third-party dependency (no JSON library —
structured results, e.g. `executeScript`, come back as JSON text you can feed to
any JSON library).

Like the other link-time bindings (rust/…), C++ **links the engine at build
time**: you `#include <selenium.hpp>`, compile the one C translation unit
(`../c/src/selenium.c`) alongside your program, and link the engine `.so`, so
the `.so` must be present when you build — it is not fetched at run time.
Linking with `-Wl,-rpath` to the engine's directory bakes the path in, so the
built binary finds it later with no `LD_LIBRARY_PATH`.

## Using it (C++ app developer)

There is no package registry for C++ here — you consume the client by including
the header and linking the engine `.so`. Because it wraps the C client, the one
C translation unit `../c/src/selenium.c` must be **compiled as C** (its
`extern "C"` symbols must not be C++-mangled) and linked in — never recompiled
by the C++ compiler.

```cpp
#include <selenium.hpp>
#include <iostream>

using namespace selenium;

int main() {
    // Resolve + launch a driver (downloads it if needed); it stops on scope exit.
    DriverProcess proc = DriverProcess::ensure("chrome");
    WebDriver d = WebDriver::headlessChrome(proc.url());

    d.get("https://example.com");
    std::cout << d.title() << "\n";
    std::cout << d.findElement(By::css("h1")).text() << "\n";

    return 0;  // d quits + closes, proc stops, elements free — all via RAII
}
```

`WebDriver`, `WebElement`, `ShadowRoot` and `DriverProcess` are move-only and
release their handles on destruction (the `WebDriver` destructor sends `quit`).
Any failing call throws `WebDriverError` (whose `code` mirrors the engine's W3C
error code: `0` = success, `-1` = transport). `By` mirrors Selenium's locators
(`By::id`, `By::name`, `By::className`, `By::css` / `By::cssSelector`,
`By::tagName`, `By::linkText`, `By::partialLinkText`, `By::xpath`).

## Getting the engine + building (no Aether toolchain)

There is no runtime fetch — you compile against the header and link the engine
`.so` at build time. Fetch the prebuilt engine for this platform once, then
build with plain `g++` (compile the C client **as C** first, then link it, your
C++ TU, and the engine). `g++` takes the engine path straight on the command
line, so no special env var is needed:

```sh
# once: populate the shared per-user cache from this project's GitHub releases
scripts/fetch-engine.sh

# then, from the repo root, build + run the C++ test against the fetched engine:
LIB=$(scripts/fetch-engine.sh --path); LIBDIR=$(dirname "$LIB")
gcc -Ic/include -c c/src/selenium.c -o selenium.o                    # C client, AS C
g++ -std=c++17 -Icpp/include -Ic/include cpp/test/selenium_test.cpp \
    selenium.o "$LIB" -Wl,-rpath,"$LIBDIR" -o selenium_test
./selenium_test
```

`$LIB` is an absolute path (so `SELENIUM_CORE_LIB=$(scripts/fetch-engine.sh
--path)` is the same value — either works). To build your own program instead
of the test, `#include <selenium.hpp>` and link `selenium.o` (the C client
compiled as C) + `"$LIB"` the same way, with `-Icpp/include -Ic/include`.
`scripts/fetch-engine.sh` downloads from THIS project's GitHub releases,
verifies the `.sha256`, and caches under `$XDG_CACHE_HOME/selaenium/<tag>/`;
`TAG=vX.Y.Z` pins a release, `FORCE=1` re-fetches.

With the Aether toolchain present, `aeb cpp/.tests.ae` builds the engine
(pulling the C client's `c_objects`) and runs the FFI + live test instead; if
you ran `scripts/fetch-engine.sh` first, that build links the fetched `.so`. The
`aeb`/`ae` toolchain is covered in the top-level README — the `g++` path above
needs none of it.

The engine resolution order (mirroring `rust/build.rs`, identical to
`c/.build.ae`) is: `SELENIUM_CORE_LIB` → the bundled
`cpp/native/libselenium_core.<ext>` slot (a published package ships the `.so`
there) → the shared fetch cache → the aeb-built engine artifact. See
[`AGENTS.md`](AGENTS.md) for the full resolution order and the engine version
pin, and [`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md)
for the prebuilt-engine flow.

## API surface (verified against `include/selenium.hpp`)

- `WebDriver` factories: `chrome`, `headlessChrome`, `firefox`,
  `headlessFirefox`, `edge`, `headlessEdge`, `safari` (each takes the driver/Grid
  URL; the non-headless ones take optional `optionsJson`).
- `WebDriver`: `sessionId`, `get`, `title`, `currentUrl`, `pageSource`, `back`,
  `forward`, `refresh`, `findElement`, `executeScript`, `execute`.
- `WebElement`: `id`, `click`, `clear`, `sendKeys`, `text`, `tagName`,
  `getAttribute`, `ariaRole`, `accessibleName`, `isDisplayed`, `isEnabled`,
  `isSelected`, `findElement`, `shadowRoot`.
- `ShadowRoot`: `findElement`.
- `DriverProcess`: `ensure`, `launch`, `url`, `pid`, `stop`.
- `By`: `id`, `name`, `className`, `css` / `cssSelector`, `tagName`, `linkText`,
  `partialLinkText`, `xpath`.
- Free helpers: `route`, `errorCode`, `locator`, `resolveDriver`.

## Layout

```
include/selenium.hpp    the header-only RAII C++ API over ../c/include/selenium.h
test/selenium_test.cpp  FFI + live test (pure helpers + transport-error facts always run; live legs self-skip)
.tests.ae               aeb node → builds the engine, pulls the C client's c_objects, runs the test
```
