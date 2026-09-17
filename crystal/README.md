# selenium (Crystal)

Selenium WebDriver for Crystal — a thin FFI binding over the shared pure-Aether
WebDriver engine (`libselenium_core`), bound directly through a Crystal `lib`
block.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The binding carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. Crystal binds the engine's flat C ABI (`aether_sel_embed_*`)
directly via a `lib` block — no glue, no second copy of the marshalling rules —
so the binding stays dependency-light (`json` from stdlib).

Unlike the dynamically-loaded bindings (ruby/python/…), Crystal **links the
engine at build time**, so the engine `.so` must be present when you build — it
is not fetched at run time. The `@[Link]` in `src/selenium.cr` also bakes an
rpath so the built binary finds it later with no `LD_LIBRARY_PATH`.

> **Name note.** This binding's shard is named `selenium`. There is no published
> shard (it is **not on [shards.info](https://shards.info)**), so consume it from
> your shop's own source — a `git`/`path` dependency in your `shard.yml`. Your
> platform team makes the engine available (below).

## Using it (Crystal app developer)

Depend on the `selenium` shard from wherever your shop provides it, then:

```crystal
require "selenium"

driver = Selenium::WebDriver.headless_chrome("http://127.0.0.1:9515")
driver.get("https://example.com")
puts driver.title
puts driver.find_element(Selenium::By.id("main")).text
driver.quit
```

`Selenium::WebDriver.headless_chrome(command_executor)` starts a headless-Chrome
session against a running chromedriver (or Grid) at that URL; `chrome`, `firefox`,
`edge`, `safari` and their `headless_*` variants are there too, plus
`local_chrome`, which has the engine spawn its own chromedriver (no driver on
PATH, no Grid). Finds take a one-arg `By` locator (`Selenium::By.id`, `.css_selector`,
`.xpath`, `.class_name`, …), matching Selenium 4.x.

## Building it (the link-time story)

Crystal's `@[Link(ldflags:)]` must be a **string literal** — it rejects a `{{…}}`
macro expression and `#{env(...)}` interpolation — so `src/selenium.cr` can only
bake in dirs it computes from `#{__DIR__}`: the binding's own bundled `native/`
(a published shard would ship the `.so` there) and the monorepo
`../selenium_core/native`. The other two search locations from the link-time
reference (`rust/build.rs`) — an explicit `SELENIUM_CORE_LIB` and the shared
fetch cache — depend on runtime env a literal cannot express, so they reach the
linker through `CRYSTAL_LIBRARY_PATH` and an rpath link flag.

That is what **`bin/crystal-build`** does: it is a drop-in `crystal` wrapper
(forwards all args to `crystal build`/`spec`/`run`) that resolves the engine dir
and contributes those two locations, giving the full build-time search order —
highest priority first:

1. `SELENIUM_CORE_LIB` — an explicit path to the `.so` (its parent dir is used)
2. the binding's own bundled `native/` (baked into the `@[Link]` dirs)
3. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
4. `../selenium_core/native` — the monorepo layout (baked in)

So a dev with **no Aether toolchain** runs `scripts/fetch-engine.sh` once, then
builds through the wrapper:

```sh
scripts/fetch-engine.sh                        # once: download + cache the engine
crystal/bin/crystal-build spec spec/ffi_spec.cr   # then build/run normally
```

Plain `crystal build` still works when the engine is in the bundled `native/` or
the monorepo dir (locations 2 and 4, which are baked into the literal); the
wrapper is what adds locations 1 and 3. The engine release tag is the repo-root
`SELENIUM_CORE_VERSION` file (the single source of truth every binding reads);
`src/selenium.cr` keeps a `SELENIUM_CORE_VERSION` literal guarded by
`spec/version_spec.cr`, which fails if it drifts from that file.

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
src/selenium.cr        the LibSel FFI `lib` block + idiomatic Selenium surface
                       (By, Keys, WebDriver / WebElement / ShadowRoot, Actions,
                       Wait, Select, driver orchestration, WebDriver-BiDi)
bin/crystal-build      `crystal` wrapper: resolves the engine dir, adds -L/-rpath
native/                where a published shard's engine .so is bundled
spec/ffi_spec.cr       no-browser FFI facts (route / error_code / locator marshalling)
spec/surface_spec.cr   no-browser ABI-surface facts (Keys, By, Actions wire shape)
spec/live_spec.cr      live-Chrome + live-Firefox smoke (self-skips without a driver)
.tests.ae              aeb node → stages the engine into native/ + runs `crystal spec`
```
