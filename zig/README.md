# selenium (Zig)

Selenium WebDriver for Zig — a thin `extern "c"` binding over the shared
pure-Aether WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The package carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. No Zig dependencies (`build.zig.zon` has none and never
will) — just libc and the engine `.so`.

Like the other link-time bindings (rust/go/nim), Zig **links the engine at build
time**, so the engine `.so` must be present when you `zig build` — it is not
fetched at run time. `build.zig` also bakes an rpath (via `addRPath`) so the
built binary finds the `.so` later with no `LD_LIBRARY_PATH`.

> **Name note.** The `build.zig.zon` package is named `selenium_core` and its
> importable module is `selenium` (`@import("selenium")`). Zig has no central
> package index, so a consumer depends on this binding by path/URL — there is no
> public registry entry to collide with.

## Using it (Zig app developer)

Depend on the module and link the engine — a Zig module carries source, not link
flags, so the consumer's own `build.zig` links the engine `.so` (as this
binding's does; see `linkEngine`). `build.zig` finds the `.so` at build time in
this order (first hit wins), mirroring `rust/build.rs`:

1. `-Dengine=/abs/path/to/libselenium_core.so` (or its directory) — an explicit build option
2. `SELENIUM_CORE_LIB` — the same env var every other binding honors (a `.so` path or a dir)
3. the package's own `native/` dir (a distributable build stages the `.so` there)
4. the shared fetch cache (`$XDG_CACHE_HOME/selaenium/<tag>/`, see below)
5. `../selenium_core/native` — the monorepo layout

So a one-time `scripts/fetch-engine.sh` (below) populates (4), then `zig build`
just works.

APIs take a `std.mem.Allocator` and return `Error!T` (Zig has no exceptions);
owned slices returned to you must be freed with that allocator. Elements are
handles driven through the `WebDriver` (e.g. `d.elementText(&e)`):

```zig
const std = @import("std");
const sel = @import("selenium");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();

    var d = try sel.WebDriver.headlessChrome(a, "http://127.0.0.1:9515");
    defer d.deinit();

    try d.get("https://example.com");
    const title = try d.title();
    defer a.free(title);
    std.debug.print("{s}\n", .{title});

    var el = try d.findElement(sel.By.id("main"));
    defer el.deinit();
    const txt = try d.elementText(&el);
    defer a.free(txt);
    std.debug.print("{s}\n", .{txt});

    try d.quit();
}
```

The factories are `WebDriver.chrome(a, command_executor, options_json)`,
`WebDriver.headlessChrome(a, command_executor)`, `WebDriver.chromeTls(…, tls)`
for a private-CA / insecure Grid, and `WebDriver.localChrome(…)` (which spawns
its own chromedriver via the engine — no driver on PATH, no Grid). `options_json`
is the capabilities object as a JSON string (pass `"{}"` for defaults). Locators
come from the `By` factory: `By.id`, `By.name`, `By.cssSelector`, `By.className`,
`By.tagName`, `By.linkText`, `By.partialLinkText`, `By.xpath`.

Build targets: `zig build test` (FFI unit tests), `zig build live` (build + run
the live-Chrome surface test), `zig build example` (the consumer example). Pass
`-Dengine=/path/to/libselenium_core.so` to any of them to point at an explicit
engine.

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the cache
`build.zig` searches (`$XDG_CACHE_HOME/selaenium/<tag>/`, `~/.cache` on Linux /
`~/Library/Caches` on macOS):

```sh
scripts/fetch-engine.sh        # download + verify + cache libselenium_core
zig build test                 # links the fetched engine from the cache
```

Or point at it explicitly — `zig build -Dengine=$(scripts/fetch-engine.sh --path)`
or `SELENIUM_CORE_LIB=/abs/path/libselenium_core.so`. `scripts/fetch-engine.sh
--path` prints the cache path without fetching; `TAG=vX.Y.Z` pins a release,
`FORCE=1` re-fetches. The fetch downloads from THIS project's GitHub releases and
verifies the `.sha256` sidecar. The engine-version pin
`const SELENIUM_CORE_VERSION = "v0.8.0"` in `build.zig` is the gh-release tag whose
cache is searched — keep it in lockstep with `scripts/fetch-engine.sh` and
`rust/build.rs`.

## Shipping a self-contained package (platform / DevOps)

To ship a package that carries its own engine (so a consumer needs no fetch),
stage the engine into the package's `native/` at build time — grab the prebuilt
engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb zig/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb zig/.package.ae
```

Same result either way, engine bytes identical. `.package.ae` copies the `.so`
into `zig/native/` and publishes the package dir. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow. (The `aeb`/`ae` toolchain is covered in the
top-level README; a consumer of the packaged module needs none of it.)

## Layout

```
src/root.zig           the extern "c" binding + WebDriver / WebElement / By / Keys surface
build.zig              resolves + links the engine .so, bakes the rpath (engine search order)
build.zig.zon          the package manifest (name, version, minimum zig version)
native/                the bundled engine .so slot a distributable build ships
src/ffi_test.zig       no-browser FFI unit tests (`zig build test`)
src/live_main.zig      live-Chrome surface test executable (`zig build live`; self-skips without a driver)
example/main.zig       the consumer example (`zig build example`)
.package.ae            aeb node → stages the engine into native/ + publishes the package dir
.tests.ae              aeb node → zig build test (FFI units) against the monorepo engine
.example.ae            aeb node → builds a consumer clean against the packaged module + drives Chrome
```
