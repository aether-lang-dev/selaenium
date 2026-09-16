# C binding (selenium-aether-c)

Thin C client over the shared pure-Aether engine (`libselenium_core`). No
Selenium protocol logic lives in C — `src/selenium.c` opens a session and issues
commands by name over the `aether_sel_embed_*` C ABI, exposing a small `sel_*`
API declared in `include/selenium.h`.

## Layout

- `include/selenium.h` — the public `sel_*` API.
- `src/selenium.c` — the client: `sel_*` wrappers over the engine's
  `aether_sel_embed_*` C ABI. Compiled to an object by `c/.objects.ae` and
  published as `c_objects` so a dependent links it WITHOUT recompiling (its
  `extern "C"` symbols must not be C++-mangled — the C++ binding reuses it).
- `test/selenium_test.c` — the FFI + live test. No-browser facts always run; the
  live headless Chrome / Firefox legs self-skip when a driver can't be resolved.
  Exit 0 = pass.

## Building against the engine

The engine `.so`/`.dylib` is LINKED at BUILD time. `c/.build.ae` resolves which
engine to link, mirroring `rust/build.rs`'s `resolve_dir()` order, and passes it
to the linker by ABSOLUTE path plus an `-Wl,-rpath` so the built binary finds it
at RUN time with no `LD_LIBRARY_PATH`. Resolution order:

1. `SELENIUM_CORE_LIB` — an explicit path to the `.so` (dev/CI escape hatch);
2. `c/native/libselenium_core.<ext>` — the bundled slot a published package
   ships the `.so` in (not present in the monorepo checkout);
3. the shared fetch cache `scripts/fetch-engine.sh` populates —
   `$XDG_CACHE_HOME/selaenium/v0.8.0/libselenium_core.<ext>` (`~/.cache` on
   Linux, `~/Library/Caches` on macOS);
4. the aeb-built engine artifact (`selenium_core/.build.ae`'s `shared_lib`).

In the monorepo, `aeb c/.tests.ae` builds the engine and runs the FFI + live
test. If you ran `scripts/fetch-engine.sh` first, the aeb build LINKS that
fetched `.so` (step 3) instead of the freshly rebuilt artifact.

### Fetch-only dev (NO Aether toolchain)

A dev who only ran `scripts/fetch-engine.sh` has the engine in the shared
per-user cache but no toolchain — so they do NOT run `aeb` (aeb needs `aetherc`).
Build directly with `gcc`. Unlike Go's `#cgo LDFLAGS`, `gcc` takes the engine
path straight on the command line, so this needs no special env var:

```sh
# once: populate the cache from GitHub releases (no toolchain needed)
scripts/fetch-engine.sh

# then, from the repo root, build + run the C test against the fetched engine:
LIB=$(scripts/fetch-engine.sh --path); LIBDIR=$(dirname "$LIB")
gcc -Ic/include -c c/src/selenium.c -o selenium.o
gcc -Ic/include c/test/selenium_test.c selenium.o "$LIB" -Wl,-rpath,"$LIBDIR" -o selenium_test
./selenium_test
```

`$LIB` here is an absolute path (`scripts/fetch-engine.sh --path` prints it), so
`SELENIUM_CORE_LIB=$(scripts/fetch-engine.sh --path)` is just the same value —
either works. To build your own program instead of the test, link
`src/selenium.c` (or the shipped `c_objects`) + `"$LIB"` the same way and add
`-Ic/include`.

## Engine version pin

The fetch-cache tag is pinned to **`v0.8.0`** in `c/.build.ae`
(`ENGINE_VERSION()`), matching `scripts/fetch-engine.sh`'s default `TAG` and
`rust/build.rs`'s `ENGINE_VERSION`. Keep all three in lockstep when the engine
release tag bumps.

## Testing

- FFI/no-browser facts need only the engine `.so`.
- Live legs drive real headless Chrome + Firefox and self-skip when the driver
  is absent.
- In-repo: `aeb c/.tests.ae`. Fetch-only: the `gcc` recipe above.
