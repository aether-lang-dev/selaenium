# C++ binding (selenium-aether-cpp)

Header-only C++ client over the shared pure-Aether engine (`libselenium_core`).
`include/selenium.hpp` wraps the C binding's `sel_*` API (from `../c`) in a C++
surface (`WebDriver`, `By`, `WebDriverError`, …). No Selenium protocol logic
lives in C++ — it all goes through the engine's `aether_sel_embed_*` C ABI.

## Layout

- `include/selenium.hpp` — the header-only C++ API over `../c/include/selenium.h`.
- `test/selenium_test.cpp` — the FFI + live test. Pure helpers +
  transport-error→exception always run; live headless Chrome / Firefox legs
  self-skip when a driver can't be resolved. Exit 0 = pass.

The C client's `selenium.c` is compiled AS C (via `c/.objects.ae`, published as
`c_objects`) and linked in — never recompiled by the C++ compiler, whose name
mangling would break its `extern "C"` symbols. `cpp/.tests.ae` pulls that object
in through cpp's dep-object collection.

## Building against the engine

The engine `.so`/`.dylib` is LINKED at BUILD time. `cpp/.tests.ae` resolves
which engine to link, mirroring `rust/build.rs`'s `resolve_dir()` order (and
identical to `c/.build.ae`), and passes it to the linker by ABSOLUTE path plus
an `-Wl,-rpath` so the built binary finds it at RUN time with no
`LD_LIBRARY_PATH`. Resolution order:

1. `SELENIUM_CORE_LIB` — an explicit path to the `.so` (dev/CI escape hatch);
2. `cpp/native/libselenium_core.<ext>` — the bundled slot a published package
   ships the `.so` in (not present in the monorepo checkout);
3. the shared fetch cache `scripts/fetch-engine.sh` populates —
   `$XDG_CACHE_HOME/selaenium/v0.8.0/libselenium_core.<ext>` (`~/.cache` on
   Linux, `~/Library/Caches` on macOS);
4. the aeb-built engine artifact (`selenium_core/.build.ae`'s `shared_lib`).

In the monorepo, `aeb cpp/.tests.ae` builds the engine and runs the FFI + live
test. If you ran `scripts/fetch-engine.sh` first, the aeb build LINKS that
fetched `.so` (step 3) instead of the freshly rebuilt artifact.

### Fetch-only dev (NO Aether toolchain)

A dev who only ran `scripts/fetch-engine.sh` has the engine in the shared
per-user cache but no toolchain — so they do NOT run `aeb`. Build directly with
`g++` (compile the C client AS C first, then link it, the C++ test, and the
engine). `g++` takes the engine path straight on the command line, so this needs
no special env var:

```sh
# once: populate the cache from GitHub releases (no toolchain needed)
scripts/fetch-engine.sh

# then, from the repo root, build + run the C++ test against the fetched engine:
LIB=$(scripts/fetch-engine.sh --path); LIBDIR=$(dirname "$LIB")
gcc -Ic/include -c c/src/selenium.c -o selenium.o                    # C client, AS C
g++ -std=c++17 -Icpp/include -Ic/include cpp/test/selenium_test.cpp \
    selenium.o "$LIB" -Wl,-rpath,"$LIBDIR" -o selenium_test
./selenium_test
```

`$LIB` is an absolute path, so `SELENIUM_CORE_LIB=$(scripts/fetch-engine.sh
--path)` is the same value — either works. To build your own program, `#include
<selenium.hpp>` and link `selenium.o` (the C client compiled as C) + `"$LIB"`
the same way, with `-Icpp/include -Ic/include`.

## Engine version pin

The fetch-cache tag is pinned to **`v0.8.0`** in `cpp/.tests.ae`
(`ENGINE_VERSION()`), matching `scripts/fetch-engine.sh`'s default `TAG`,
`c/.build.ae`, and `rust/build.rs`'s `ENGINE_VERSION`. Keep them in lockstep
when the engine release tag bumps.

## Testing

- Pure-helper + transport-error facts need only the engine `.so`.
- Live legs drive real headless Chrome + Firefox and self-skip when the driver
  is absent.
- In-repo: `aeb cpp/.tests.ae`. Fetch-only: the `g++` recipe above.
