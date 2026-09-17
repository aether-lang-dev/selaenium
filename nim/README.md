# selenium (Nim)

Selenium WebDriver for Nim — a thin `importc` binding over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The package carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. No third-party Nim deps (`requires "nim >= 1.6.0"` and
`std/json` only), so `nimble install` stays offline.

Like the other link-time bindings (rust/go/zig), Nim **links the engine at build
time** (Nim compiles and links by default, like Go/cgo and Rust) — so the engine
`.so` must be present when you compile, not just at run time. The compile-time
`{.passL.}` in `selenium.nim` also bakes an rpath so a built binary finds the
`.so` later with no `LD_LIBRARY_PATH`.

> **Name note.** This package is named `selenium` in `selenium.nimble` on
> purpose — it mirrors the mainstream Selenium API in Nim idiom. Mainstream
> Selenium ships no Nim binding, so there is no classic `selenium` Nim package
> to collide with; you consume this one from wherever your shop provides it (a
> path/git dependency or an internal nimble registry), not a public index.

## Using it (Nim app developer)

Depend on `selenium` from wherever your shop provides it, then compile against
it. At COMPILE time, `selenium.nim`'s `linkFlags()` searches for the engine `.so`
in this order (each candidate is added to the link path AND baked as rpath),
mirroring `rust/build.rs`:

1. `SELENIUM_CORE_LIB` — an explicit path (its parent dir when a full `.so` path is given)
2. the package's own bundled `native/` dir (a published package ships the `.so` there)
3. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
4. `../../selenium_core/native` — the monorepo layout

So a one-time `scripts/fetch-engine.sh` (below) populates (3), then a normal
`nim c` just works.

```nim
import selenium

let d = headlessChrome("http://127.0.0.1:9515")
defer: d.quit()

d.get("https://example.com")
echo d.title()

echo d.findElement(By.id("main")).text()
```

The factories are `chrome` / `headlessChrome`, `firefox` / `headlessFirefox`,
`edge` / `headlessEdge`, `safari`, and `localChrome` (which spawns its own
chromedriver via the engine — no driver on PATH, no Grid). `chrome`/`firefox`/…
take an optional `options: JsonNode` plus `caPath`/`insecure` for TLS trust.
Locators come from the `By` factory: `By.id`, `By.name`, `By.cssSelector`,
`By.className`, `By.tagName`, `By.linkText`, `By.partialLinkText`, `By.xpath`.

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the cache
`linkFlags()` searches (`$XDG_CACHE_HOME/selaenium/<tag>/`, `~/.cache` on Linux /
`~/Library/Caches` on macOS):

```sh
scripts/fetch-engine.sh        # download + verify + cache libselenium_core
```

Or set `SELENIUM_CORE_LIB=/abs/path/libselenium_core.so`
(`scripts/fetch-engine.sh --path` prints the cache path). `TAG=vX.Y.Z` pins a
release, `FORCE=1` re-fetches. The fetch downloads from THIS project's GitHub
releases and verifies the `.sha256` sidecar. The engine-version pin
`const EngineVersion = "v0.8.0"` in `selenium.nim` is the gh-release tag whose
cache is searched — keep it in lockstep with `scripts/fetch-engine.sh` and
`rust/build.rs`.

## Shipping a self-contained package (platform / DevOps)

To ship a package that carries its own engine (so a consumer needs no fetch),
stage the engine into the package's `native/` at build time — grab the prebuilt
engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb nim/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb nim/.package.ae
```

Same result either way, engine bytes identical. `.package.ae` copies the `.so`
into `nim/native/` and publishes the package dir. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow. (The `aeb`/`ae` toolchain is covered in the
top-level README; a consumer of the packaged module needs none of it.)

## Layout

```
src/selenium.nim       the importc binding + idiomatic WebDriver / WebElement / By surface
selenium.nimble        the package manifest (name, version, `nimble test` task)
native/                the bundled engine .so slot a published package ships ({.passL.} -L native)
tests/tffi.nim         no-browser FFI facts (route/errorCode/locator)
tests/tlive.nim        live-Chrome smoke + surface (needs --threads:on; self-skips without chromedriver)
.package.ae            aeb node → stages the engine into native/ + publishes the package dir
.tests.ae              aeb node → nim c -r the test suite with the engine linked
.example.ae            aeb node → compiles a consumer clean against the packaged module + drives Chrome
```
