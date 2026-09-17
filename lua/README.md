# selenium (Lua)

Selenium WebDriver for Lua — a thin C-extension wrapper (`selenium_core_native`)
over the shared pure-Aether WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` the C extension `dlopen`s (N independent sessions per
process). It is **not** an installation, a service, or a framework: no installer,
no daemon, no config, no special directories. The Lua module carries no protocol
logic — the W3C command map, routing, `By` normalization, error decode and the
HTTP round trip all live in that one library. Targets Lua 5.4.

## Using it (Lua app developer)

`require` the module and drive:

```lua
local s = require("selenium")

local d = s.headless_chrome("http://127.0.0.1:9515")
d:get("https://example.com")
print(d:title())
print(d:find_element(s.By.id("main")):text())
d:quit()
```

The engine is a single shared library the extension `dlopen`s — nothing to
install, compile, or configure at consume time. To point at a specific engine,
ahead of any discovery: `s.configure_native_lib("/abs/path/libselenium_core.so")`,
or the `SELENIUM_CORE_LIB` env var.

## Getting the engine

Fetch the prebuilt engine for this platform once — it caches where the extension
looks:

```sh
lua bin/fetch_engine.lua        # download + verify + cache libselenium_core
```

`--tag vX.Y.Z` pins a release, `--force` re-fetches, `--path` prints the cache
location. It downloads from THIS project's GitHub releases, verifies the
`.sha256`, and caches under `$XDG_CACHE_HOME/selaenium/<tag>/`. Never triggered
implicitly. Loader search order: explicit (`configure_native_lib`) →
`SELENIUM_CORE_LIB` → the bundled `native/` → the fetch cache → bare name.

## Building the packaged module (platform / DevOps)

The team that owns the Aether tooling stages the engine into the module's
`native/` — grab the prebuilt engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb lua/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb lua/.package.ae
```

Same result either way, engine bytes identical. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow.

## Layout

```
src/selenium.lua           the idiomatic WebDriver / By surface (pure Lua)
src/selenium_core.c        the C extension: dlopen's the engine, binds the C ABI
src/engine_fetcher.lua     download + verify + cache the prebuilt engine
bin/fetch_engine.lua       lua bin/fetch_engine.lua
.package.ae                aeb node → builds the extension + stages the engine
.tests.ae                  aeb node → the binding test suite
```
