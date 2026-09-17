# selenium (D)

Selenium WebDriver for D — a thin `extern(C)` binding over the shared pure-Aether
WebDriver engine (`libselenium_core`), in the `selenium` module.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The binding carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. Uses only the D standard library (`std.json` for structured
results); every ABI `char*` is copied into a GC'd `string` and freed via
`aether_sel_embed_free_string`.

Like the other link-time bindings (rust/nim/…), D **links the engine at build
time**: `dmd` compiles the `selenium` module alongside your program and links the
engine `.so` (forwarded as `-L-L<dir> -L-lselenium_core`), so the `.so` must be
present when you build — it is not fetched at run time. A baked `-L-rpath` means
the built binary finds it later with no `LD_LIBRARY_PATH`.

## Using it (D app developer)

There is no package registry for D here — you consume the module in place
(`dmd` reads `src/selenium/package.d` and links the staged `native/` engine).
`chrome(...)` / `headlessChrome(...)` are free functions returning a `WebDriver`;
`By` is a struct of factory methods mirroring Java's `By`:

```d
import selenium;

auto d = headlessChrome("http://127.0.0.1:9515");
scope(exit) d.quit();

d.get("https://example.com");
writeln(d.title());
writeln(d.findElement(By.id("main")).text());
```

`WebDriver` is a class whose destructor also calls `quit()`; `scope(exit)`
makes the intent explicit. Any failing call throws a `WebDriverException` (with an
`int code` mirroring the engine's W3C error code — `-1` for transport — and an
`ErrorKind kind`). `By` mirrors Selenium's locators
(`By.id`, `By.name`, `By.className`, `By.cssSelector`, `By.tagName`,
`By.linkText`, `By.partialLinkText`, `By.xpath`). Structured results
(`executeScript`, attributes) come back as `std.json.JSONValue`.

## Getting the engine + building (no Aether toolchain)

There is no runtime fetch — you compile against the module and link the engine
`.so` at build time. Fetch the prebuilt engine for this platform once, then build
with plain `dmd`, forwarding the engine dir + rpath to the linker with `-L`:

```sh
# once: populate the shared per-user cache from this project's GitHub releases
scripts/fetch-engine.sh
LIB=$(scripts/fetch-engine.sh --path); LIBDIR=$(dirname "$LIB")

# then compile-and-run the FFI test against the fetched engine:
dmd -Id/src -Jselenium_core/console -run d/tests/ffi_test.d \
    -L-L"$LIBDIR" -L-lselenium_core -L-rpath -L"$LIBDIR"
```

`scripts/fetch-engine.sh` downloads from THIS project's GitHub releases, verifies
the `.sha256`, and caches under `$XDG_CACHE_HOME/selaenium/<tag>/`; `TAG=vX.Y.Z`
pins a release, `FORCE=1` re-fetches. To build your own program, compile
`src/selenium/package.d` in (or `-Id/src` and `import selenium`) and link the
same way. The `-J` string-import path is needed because the module string-imports
the runner console page (`console.html`); a packaged module (below) ships it
inside `src/selenium/` so `-Jd/src/selenium` suffices.

With the Aether toolchain present, `aeb d/.tests.ae` builds the engine (staged
into `selenium_core/native/`) and runs the FFI + live test instead; if you ran
`scripts/fetch-engine.sh` first, that build links the fetched `.so`. The
`aeb`/`ae` toolchain is covered in the top-level README — the `dmd` path above
needs none of it.

## Shipping a self-contained module (platform / DevOps)

`aeb d/.package.ae` stages the engine `.so` into `d/native/` and ships the
console pages inside `src/selenium/`, then publishes the module dir on the
`package_dir` edge (consumed by `d/.example.ae`, which recompiles the module
clean and drives Chrome). Grab the prebuilt engine instead of building it with
`--overrideDep`:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb d/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb d/.package.ae
```

Same result either way, engine bytes identical. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow.

## Layout

```
src/selenium/package.d    the extern(C) binding + WebDriver / WebElement / By / … surface
src/selenium/console.html the runner console page (string-imported via -J)
tests/ffi_test.d          FFI + convenience-tier facts (no browser; always run)
tests/live_test.d         live-Chrome smoke (self-skips exit 0 without chromedriver)
.package.ae               aeb node → stages the engine into native/, ships the console pages
.tests.ae                 aeb node → dmd compiles the module + links the engine, runs the tests
.example.ae               aeb node → recompiles the module clean + drives Chrome
```
