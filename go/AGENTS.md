# Go binding (selenium-aether-go)

Thin cgo binding over the shared pure-Aether engine (`libselenium_core`). No
Selenium protocol logic lives in Go — it opens a session and issues commands by
name over the `aether_sel_embed_*` C ABI (see `selenium.go`).

## Building against the engine

The engine `.so`/`.dylib`/`.dll` is linked at BUILD time by the `#cgo LDFLAGS:`
line in `selenium.go`. That directive can only search two `${SRCDIR}`-relative
dirs (cgo expands `${SRCDIR}` but NOT `$HOME`/`$XDG_CACHE_HOME`):

- `${SRCDIR}/native/` — the bundled slot a published module ships the `.so` in;
- `${SRCDIR}/../selenium_core/native/` — the monorepo layout (this module next
  to `selenium_core/`).

In the monorepo, `aeb go/.tests.ae` (or `go/.package.ae`) stages the freshly
built engine into those dirs, so `go test`/`go build` just work.

### Fetch-only dev (NO Aether toolchain)

A dev who only ran `scripts/fetch-engine.sh` has the engine in the shared
per-user cache — `$XDG_CACHE_HOME/selaenium/v0.8.0/libselenium_core.<ext>`
(`~/.cache` on Linux, `~/Library/Caches` on macOS) — but nothing in the two
`${SRCDIR}` dirs above. Because a `#cgo LDFLAGS` directive cannot expand
`$XDG_CACHE_HOME`, the cache dir cannot be named statically; feed it in at build
time via the **`CGO_LDFLAGS` environment variable** (cgo APPENDS it to the
static directive):

```sh
# once: populate the cache from GitHub releases (no toolchain needed)
scripts/fetch-engine.sh

# then, from go/, build/test against the fetched engine:
CACHE=$(dirname "$(scripts/fetch-engine.sh --path)")
export CGO_LDFLAGS="-L$CACHE -Wl,-rpath,$CACHE"
go test ./...        # or: go build ./...  /  go vet ./...
```

The `-Wl,-rpath` half lets the built test/binary find the `.so` at RUN time with
no `LD_LIBRARY_PATH`.

Equivalent alternative — drop the fetched `.so` into the bundled slot so the
static `-L${SRCDIR}/native` directive links it (no `CGO_LDFLAGS` needed):

```sh
ln -sf "$(scripts/fetch-engine.sh --path)" go/native/libselenium_core.so
go test ./...
```

Note: `SELENIUM_CORE_LIB` alone is NOT sufficient for the Go BUILD — unlike
`rust/build.rs`, a `#cgo LDFLAGS` directive cannot read it to add a search dir.
It remains the cross-binding escape hatch for RUNTIME resolution and is honored
by `EngineDir`/`EnginePath` in `enginepath.go`; for a fetch-only `go build`,
export `CGO_LDFLAGS` as above (you can point it at `SELENIUM_CORE_LIB`'s dir).

## enginepath.go

`enginepath.go` exposes the engine-version pin and the runtime path resolver,
mirroring `rust/build.rs`'s `resolve_dir()` order
(`SELENIUM_CORE_LIB` → bundled `native/` → fetch cache → monorepo sibling):

- `const EngineVersion = "v0.8.0"` — the gh-release tag whose cache is searched
  (matches `scripts/fetch-engine.sh`'s default `TAG` and `rust/build.rs`).
- `CacheDir()` / `CachedEnginePath()` — the shared per-user cache dir/file
  (identical to `scripts/fetch-engine.sh --path`).
- `EngineDir()` / `EnginePath()` — resolve the engine dir/file for runtime
  dlopen/rpath and tests.
- `CgoLdflags()` — the `-L… -Wl,-rpath,…` string to export as `CGO_LDFLAGS`.

Keep `EngineVersion` in lockstep with `scripts/fetch-engine.sh` and
`rust/build.rs` when the engine release tag bumps.

## Testing

- Unit/FFI tests (`ffi_test.go`, `enginepath_test.go`, `surface_test.go`,
  `convenience_test.go`) need only the engine `.so`, no browser.
- Live tests (`live_test.go`, `*_live_test.go`) drive real headless Chrome and
  self-skip cleanly when `chromedriver` is absent.
- In-repo: `aeb go/.tests.ae`. Fetch-only: the `CGO_LDFLAGS` recipe above.
