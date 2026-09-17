# selenium (Go)

Selenium WebDriver for Go — a thin cgo binding over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The package carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. No third-party Go modules (stdlib + cgo only).

Like the other link-time bindings (rust/nim/zig), Go **links the engine at
build time**, so the engine `.so` must be present when you `go build` — it is
not fetched at run time. The `#cgo LDFLAGS:` line in `selenium.go` also bakes an
rpath so the built binary finds the `.so` later with no `LD_LIBRARY_PATH`.

## Using it (Go app developer)

Import the module from wherever your shop provides it (the import path is
`github.com/seleniumhq/selenium-aether-go` — its own path, so it never collides
with any classic Selenium module). cgo finds the engine `.so` at build time via
two fixed `${SRCDIR}`-relative search dirs baked into `selenium.go`'s
`#cgo LDFLAGS:` directive:

1. the module's own bundled `native/` dir (a published module ships the `.so` there)
2. `../selenium_core/native` — the monorepo layout (this module next to `selenium_core/`)

A `#cgo LDFLAGS` directive can only expand `${SRCDIR}` — **not** `$HOME` or
`$XDG_CACHE_HOME` — so the shared fetch cache cannot be named there statically.
A fetch-only dev feeds the cache dir in at build time via the **`CGO_LDFLAGS`
environment variable**, which cgo *appends* to the static directive (see the
next section). `SELENIUM_CORE_LIB` alone is **not** enough for the Go build — a
`#cgo LDFLAGS` directive cannot read an env var to add a search dir (unlike
`rust/build.rs`); it remains the cross-binding escape hatch for RUNTIME
resolution, honored by `EngineDir`/`EnginePath` in `enginepath.go`.

```go
import selenium "github.com/seleniumhq/selenium-aether-go"

drv, err := selenium.NewHeadlessChrome("http://127.0.0.1:9515")
if err != nil {
	log.Fatal(err)
}
defer drv.Quit()

drv.Get("https://example.com")
title, _ := drv.Title()
fmt.Println(title)

el, _ := drv.FindElement(selenium.By.Id("main"))
txt, _ := el.Text()
fmt.Println(txt)
```

The factories are package-level: `NewChrome` / `NewHeadlessChrome`,
`NewFirefox` / `NewHeadlessFirefox`, `NewEdge` / `NewHeadlessEdge`, `NewSafari`,
`NewRemote(url, caps, opts...)`, and `NewLocalChrome(opts...)` (which spawns its
own chromedriver via the engine — no driver on PATH, no Grid). Options like
`selenium.Headless()`, `selenium.Capability(k, v)`, `selenium.WithCA(path)` and
`selenium.Insecure()` are passed as trailing varargs. Locators come from the
`selenium.By` factory: `By.Id`, `By.Name`, `By.CssSelector`, `By.ClassName`,
`By.TagName`, `By.LinkText`, `By.PartialLinkText`, `By.Xpath`.

## Getting the engine (before you build)

Fetch the prebuilt engine for this platform once — it lands in the shared cache
(`$XDG_CACHE_HOME/selaenium/<tag>/`, `~/.cache` on Linux / `~/Library/Caches` on
macOS):

```sh
scripts/fetch-engine.sh        # download + verify + cache libselenium_core
```

Then, because a `#cgo LDFLAGS` directive can't name the cache dir, export
`CGO_LDFLAGS` so `go build`/`go test` link and rpath from the cache (this
*augments* the static search dirs — the `-Wl,-rpath` half lets the built binary
find the `.so` at run time too):

```sh
CACHE=$(dirname "$(scripts/fetch-engine.sh --path)")
export CGO_LDFLAGS="-L$CACHE -Wl,-rpath,$CACHE"
go build ./...        # or: go test ./...  /  go vet ./...
```

`scripts/fetch-engine.sh --path` prints the cache path without fetching;
`TAG=vX.Y.Z` pins a release, `FORCE=1` re-fetches. The fetch downloads from THIS
project's GitHub releases and verifies the `.sha256` sidecar. Equivalent
alternative — drop the fetched `.so` into the bundled slot so the static
`-L${SRCDIR}/native` directive links it (no `CGO_LDFLAGS` needed):

```sh
ln -sf "$(scripts/fetch-engine.sh --path)" go/native/libselenium_core.so
```

The engine-version pin and the runtime resolver live in `enginepath.go`:
`const SeleniumCoreVersion = "v0.8.0"` (the gh-release tag whose cache is searched;
keep it in lockstep with `scripts/fetch-engine.sh` and `rust/build.rs`),
`CacheDir()` / `CachedEnginePath()` (the shared per-user cache dir/file, equal
to `fetch-engine.sh --path`), `EngineDir()` / `EnginePath()` (resolve the engine
for runtime dlopen/rpath and tests, in the order
`SELENIUM_CORE_LIB` → bundled `native/` → fetch cache → monorepo sibling), and
`CgoLdflags()` (the `-L… -Wl,-rpath,…` string to export as `CGO_LDFLAGS`).

## Shipping a self-contained module (platform / DevOps)

To ship a module that carries its own engine (so a consumer needs no fetch),
stage the engine into the module's `native/` at build time — grab the prebuilt
engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb go/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb go/.package.ae
```

Same result either way, engine bytes identical. `.package.ae` copies the `.so`
into `go/native/` (and stages `console.html`, which `selenium.go` `//go:embed`s
for the console bridge) and publishes the module dir. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow. (The `aeb`/`ae` toolchain is covered in the
top-level README; a consumer of the packaged module needs none of it.)

## Layout

```
selenium.go            the cgo binding + idiomatic WebDriver / WebElement / By surface
convenience.go         the convenience tier (waits, Select, chords, …) over that surface
enginepath.go          engine-version pin + runtime path resolver (CacheDir/EngineDir/CgoLdflags)
native/                the bundled engine .so slot a published module ships (cgo -L${SRCDIR}/native)
live_test.go           live-Chrome smoke (self-skips without chromedriver)
.package.ae            aeb node → stages the engine into native/ + publishes the module dir
.tests.ae              aeb node → go test with the engine linked
.example.ae            aeb node → installs the packaged module clean + drives Chrome
```
