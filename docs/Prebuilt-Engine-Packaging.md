# Packaging against the prebuilt engine (fetch, don't compile)

Every binding's package (`gem` / `jar` / `wheel` / …) bundles the pure-Aether
engine `libselenium_core` — one pure, reentrant shared library
(`.so`/`.dylib`/`.dll`), not an install/service/framework. Normally the packaging
node **compiles** that engine from its Aether source, which needs the engine
source graph on the module path. This page is the other way: **fetch** the
prebuilt engine from the GitHub release and package that.

It's a choice about where the engine `.so` comes from, not a way to avoid the
toolchain: `aeb` still runs the packaging node and still uses an `ae` compiler
(your own, or one it fetches into its own cache) to build that node. What fetching
skips is compiling the *engine* from source — so you need no engine source tree,
just `aeb` + network. Some prefer it (a reproducible release artifact, nothing to
compile); it's an arbitrary, per-person call.

The mechanism is aeb's `--overrideDep` (aeb 0.313+, read-redirect in 0.314+) plus
one fetch node, [`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae).

## The one command

```sh
aeb ruby/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae
```

`--overrideDep <real>=<substitute>` relabels every `dep("<real>")` edge to the
substitute node. So the gem's `dep("selenium_core/.build.ae")` +
`dep_artifact(…, "shared_lib")` transparently resolve to the FETCH node instead
of the build node — no change to `ruby/.package.ae` or the gemspec. The fetch
node downloads the prebuilt engine for this platform from the release, verifies
its published `.sha256`, caches it, and publishes the same `shared_lib` /
`shared_library` / `shared_library_deps_including_transitive` edges the builder
would — so it is a drop-in producer. The gem's `copy.file` then stages the
FETCHED `.so` into `lib/selenium/native/` and `ruby.gem()` bundles it.

Result: `target/package/ruby/dist/selenium-webdriver-<v>.gem`, containing
`lib/selenium/native/libselenium_core.so` — the release engine, not a locally
built one. Verified: with no engine present and no `SELENIUM_CORE_LIB`, the
override build produces a gem whose bundled `.so` is byte-for-byte the release
artifact (its sha matches the release's published `libselenium_core-<tag>-linux-x86_64.so.sha256`).

## What the fetch node does

[`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)
is a substitute producer for the engine builder. It shells the shared
[`scripts/fetch-engine.sh`](../scripts/fetch-engine.sh) (download + `.sha256`
verify + cache under `$XDG_CACHE_HOME/selaenium/<tag>/`, the same cache the
runtime and link-time bindings use), stages the `.so` with native `std.fs`, and
`publish_artifact`s the engine edges. The release tag it fetches is the single
source of truth in the repo-root `SELENIUM_CORE_VERSION` file (currently `v0.9.0`),
which `scripts/fetch-engine.sh` and every binding read (overridable via `TAG=`) —
edit that one file, keeping it in step with the `AETHER_REF` engine cut, when
re-gluing to a newer engine.

## Which dep to override, per binding

The substitute must match the edge that binding's `.package.ae` actually deps:

| Binding | `.package.ae` deps | override target |
|---------|-------------------|-----------------|
| ruby (gem) | `selenium_core/.build.ae` (one platform `.so`) | `selenium_core/.getFromGitHubReleases.ae` ✅ |
| python (wheel), dart, php, lua | `selenium_core/.build.ae` | `selenium_core/.getFromGitHubReleases.ae` (same single-platform node) |
| java (jar) | `selenium_core/.crossbuild.ae` (6-platform natives) | a *crossbuild* fetch node — fetches all 6 platform libs from the release. **Not yet built** (follow-up). |

Ruby is the reference and is verified end to end. Any binding whose package deps
the single-platform `selenium_core/.build.ae` works with the same
`.getFromGitHubReleases.ae` substitute today. The multi-platform jar needs its own
fetch-all-6 node — tracked as a follow-up.

## A note on verifying an override actually took

For a binding whose build finds the engine several ways (e.g. rust's `build.rs`:
`SELENIUM_CORE_LIB` → bundled `native/` → fetch cache → monorepo), a *green build*
under `--overrideDep` does **not** by itself prove the override path was used — a
fallback (often the fetch cache, which the fetch node repopulates) can satisfy the
build regardless. The real proof is at the artifact layer: the substitute node's
published `shared_lib`, and — for a package — that the shipped `.so` is the release
artifact by checksum. The Ruby verification above checks the checksum, which is
unambiguous. See
[`asks/aeb-overridedep-does-not-redirect-dep-artifact-reads.md`](../asks/aeb-overridedep-does-not-redirect-dep-artifact-reads.md)
for the caveat in full.
