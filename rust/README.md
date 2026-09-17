# selenium (Rust)

Selenium WebDriver for Rust — a thin FFI crate over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The crate carries no protocol logic — the W3C command map,
routing, `By` normalization, error decode and the HTTP round trip all live in
that one library. Zero external crates (stdlib only).

Unlike the dynamically-loaded bindings (ruby/python/…), Rust **links the engine
at build time**, so the engine `.so` must be present when you `cargo build` — it
is not fetched at run time. `build.rs` also bakes an rpath so the built binary
finds it later with no `LD_LIBRARY_PATH`.

## Using it (Rust app developer)

Depend on `selenium` from wherever your shop provides it (a path/git dependency
or an internal registry). The crate's `build.rs` finds the engine `.so` at build
time in this order:

1. `SELENIUM_CORE_LIB` — an explicit path (its parent dir becomes the link search)
2. the crate's own bundled `native/` dir (a published crate ships the `.so` there)
3. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
4. `../selenium_core/native` — the monorepo layout

So a one-time `scripts/fetch-engine.sh` (below) populates (3), then `cargo build`
just works.

```rust
use selenium::{WebDriver, By};

let d = WebDriver::headless_chrome("http://127.0.0.1:9515")?;
d.get("https://example.com")?;
println!("{}", d.title()?);
println!("{}", d.find_element(By::id("main"))?.text()?);
d.quit()?;
```

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the cache
`build.rs` searches:

```sh
scripts/fetch-engine.sh        # download + verify + cache libselenium_core
```

Or set `SELENIUM_CORE_LIB=/abs/path/libselenium_core.so` (a `scripts/fetch-engine.sh
--path` prints the cache path). `TAG=vX.Y.Z` pins a release, `FORCE=1` re-fetches.
The fetch downloads from THIS project's GitHub releases, verifies the `.sha256`,
and caches under `$XDG_CACHE_HOME/selaenium/<tag>/`.

## Shipping a self-contained crate (platform / DevOps)

To ship a crate that carries its own engine (so a consumer needs no fetch), stage
the engine into the crate's `native/` at build time — grab the prebuilt engine,
or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb rust/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb rust/.package.ae
```

Same result either way, engine bytes identical. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow.

## Layout

```
src/lib.rs             the FFI binding + idiomatic WebDriver / WebElement / By surface
src/json.rs            the JSON value type used across the surface
build.rs               resolves + links the engine .so, bakes the rpath
tests/live_test.rs     live-Chrome smoke (self-skips without chromedriver)
.package.ae            aeb node → stages the engine into native/
.tests.ae              aeb node → cargo test with the engine linked
.example.ae            aeb node → builds a consumer crate clean + drives Chrome
```
