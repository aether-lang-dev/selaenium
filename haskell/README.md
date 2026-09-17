# selenium (Haskell)

Selenium WebDriver for Haskell — a thin FFI binding over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The binding carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library, reached through `Selenium.Native`. The `Selenium` module
just marshals strings across the boundary, so it stays dependency-light (`base`
+ `bytestring` only). Command params are passed as JSON strings and results come
back as the raw JSON of the response `value`.

Unlike the dynamically-loaded bindings (ruby/python/…), Haskell **links the
engine at build time**, so the engine `.so` must be present when you build — it
is not fetched at run time. An rpath is passed at link time so the built binary
finds it later with no `LD_LIBRARY_PATH`.

> **Name note.** This package is named `selenium` (`selenium.cabal`). It is **not
> published to [Hackage](https://hackage.haskell.org)**, so consume it from your
> shop's own source — a local package, a `source-repository-package` stanza, or
> an internal package server. Your platform team makes the engine available
> (below).

## Using it (Haskell app developer)

Depend on the `selenium` package from wherever your shop provides it. The
surface is `IO`-monadic — a `WebDriver` is an opaque session handle threaded
explicitly through each call, and `findElement` returns the opaque W3C element
id string that the element-scoped verbs (`elementText`, `elementClick`, …) take
as their first argument:

```haskell
import Selenium

main :: IO ()
main = do
  d <- headlessChrome "http://127.0.0.1:9515"
  get d "https://example.com"
  putStrLn =<< title d
  hdr <- findElement d (byId "main")
  putStrLn =<< elementText d hdr
  quit d
```

`headlessChrome :: String -> IO WebDriver` starts a headless-Chrome session
against a running chromedriver (or Grid) at that URL. The general form is
`chrome :: String -> String -> IO WebDriver` — a command-executor URL plus an
`alwaysMatch` capabilities object as a JSON string; `firefox`, `edge`, `safari`
and the `headless*` variants follow the same shape. Finds take a one-arg
`Locator` from the `by*` smart constructors (`byId`, `byCss`, `byXpath`,
`byClassName`, …), matching Selenium 4.x. Protocol errors throw a
`WebDriverError` carrying the engine's W3C code (`-1` = transport).

## Building it (the link-time story)

`selenium.cabal` only **names** the library (`extra-libraries: selenium_core`);
it does not know where the `.so` is. cabal 9.x rejects a bare relative
`extra-lib-dirs` at the register step and won't expand `${pkgroot}`, so the
engine's **absolute** dir must be supplied on the command line
(`--extra-lib-dirs=<abs dir>` plus an rpath ghc option).

That is what **`bin/cabal-build`** does: it is a drop-in `cabal` wrapper
(forwards all args to `cabal build`/`test`) that resolves the engine dir,
searching in order — highest priority first:

1. `SELENIUM_CORE_LIB` — an explicit path to the `.so` (its parent dir is used)
2. the binding's own bundled `native/` (a published package ships the `.so` there)
3. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
4. `../selenium_core/native` — the monorepo layout (this binding next to core/)

It passes the resolved dir as `--extra-lib-dirs` (the link `-L`), an rpath ghc
linker option (so the built binary/tests locate the `.so` at run time), and
exports `SELENIUM_CORE_LIB` for any run leg. If no engine is found it fails with
a clear message listing the dirs it searched.

So a dev with **no Aether toolchain** runs `scripts/fetch-engine.sh` once, then
builds through the wrapper:

```sh
scripts/fetch-engine.sh              # once: download + cache the engine
haskell/bin/cabal-build build        # then build normally
haskell/bin/cabal-build test         # (forwards all args to cabal)
```

The engine release tag this binding pins is `ENGINE_VERSION` in `bin/cabal-build`
and noted in `selenium.cabal` (matching `scripts/fetch-engine.sh` and every other
binding).

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the cache the
wrapper searches:

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
src/Selenium.hs        the idiomatic surface: By / Locator smart constructors,
                       session lifecycle, navigation, elements, ShadowRoot,
                       script, windows, frames, alerts, cookies, Actions verbs,
                       waits, Select, driver orchestration, WebDriver-BiDi
src/Selenium/Native.hs the raw FFI imports over the aether_sel_embed_* C ABI
selenium.cabal         names the library (extra-libraries: selenium_core)
bin/cabal-build        `cabal` wrapper: resolves the engine dir, adds the link flags
native/                where a published package's engine .so is bundled
test/Live.hs           FFI + live-Chrome + live-Firefox surface test
content_server.py      out-of-process fixture server for the live test
.tests.ae              aeb node → stages the engine + runs the binding test suite
```
