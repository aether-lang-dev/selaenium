# Selenium (Julia)

Selenium WebDriver for Julia — a thin `ccall` wrapper over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` reached by `ccall` (N independent sessions per process). It
is **not** an installation, a service, or a framework: no installer, no daemon,
no config, no special directories. The module carries no protocol logic — the W3C
command map, routing, `By` normalization, error decode and the HTTP round trip
all live in that one library.

## Using it (Julia app developer)

Add `Selenium` from wherever your shop provides it (a path/dev dependency or a
private registry), fetch the engine once (below), then:

```julia
using Selenium

d = headless_chrome("http://127.0.0.1:9515")
get(d, "https://example.com")
println(title(d))
println(text(find_element(d, By.id("main"))))
quit(d)
```

The API is function-style (`find_element(d, By.id(...))`, `text(el)`), and the
engine is a single shared library reached by `ccall` — nothing to install,
compile, or configure at consume time.

## Getting the engine

Fetch the prebuilt engine for this platform once:

```julia
using Selenium
Selenium.fetch_engine!()        # download + verify + cache libselenium_core
```

`fetch_engine!(; tag=..., force=false)` downloads the prebuilt engine from THIS
project's GitHub releases, verifies its `.sha256`, and caches it under
`$XDG_CACHE_HOME/selaenium/<tag>/`. Never triggered implicitly.

**Ordering note:** the engine path (`LIB`) is resolved **once**, at the first
`ccall`. So fetch the engine (or set `SELENIUM_CORE_LIB`) *before* your first
driver call — ideally right after `using Selenium`, before any session is
opened. Resolution order: `SELENIUM_CORE_LIB` (an explicit absolute path) → the
fetch cache → `libselenium_core` on the system loader path.

## Layout

```
src/Selenium.jl            the ccall binding + idiomatic WebDriver surface +
                           the EngineFetcher submodule (fetch_engine! / ENGINE_VERSION)
test/engine_fetcher_test.jl   offline + a SELENIUM_FETCH_LIVE=1 gated live fetch
test/runtests.jl           the binding test suite (FFI gated on SELENIUM_CORE_LIB)
```

Julia consumes the module as source (there is no separate package-build step);
the engine `.so` comes from the fetch above (or `SELENIUM_CORE_LIB`). See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
how the other bindings seal the engine into their built package via
`--overrideDep`.
