# aeb 0.313 `--overrideDep` relabels the build schedule but NOT `dep_artifact()` reads

**From:** selaenium, 2026-09-17. **Status:** bug/gap in the just-shipped
`--overrideDep` (aeb 0.313). The substitute node runs, but a consumer that reads
the substituted dep's published artifact by the ORIGINAL label gets nothing —
this is exactly the "artifact READ redirect" layer the design reply
(REPLY-generate-consumer-manifest-and-override-dep.md) said would ship first.

## Setup (works as far as scheduling)

selaenium authored `selenium_core/.getFromGitHubReleases.ae` — a fetch substitute
for the engine builder `selenium_core/.build.ae`. It downloads the prebuilt
engine, stages it, and publishes the SAME edges the real builder does
(`shared_lib` / `shared_library` / `shared_library_deps_including_transitive`).
Verified in isolation: running the node publishes all three artifacts pointing at
the staged `.so`, correct.

Ran a binding build with the override:

    aeb rust/.tests.ae \
      --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

The trampoline reports the relabel and the fetch node runs. `.build.ae` is
correctly dropped from the schedule.

## The bug

`rust/.tests.ae` does, like every consumer:

    dep("selenium_core/.build.ae")
    lib = dep_artifact("selenium_core/.build.ae", "shared_lib")
    env("SELENIUM_CORE_LIB", lib)

`dep_artifact()` → `_read_dep_artifact(ctx, "selenium_core/.build.ae", "shared_lib")`
(lib/bldr/module.ae:2255). That function resolves the dep_module to
`target/build/selenium_core/shared_lib` with **no AEB_OVERRIDE_DEP awareness** —
so it reads the DROPPED `.build.ae` node's location, which is empty (that node
didn't run). Result: `lib` is empty → `SELENIUM_CORE_LIB` empty → the build falls
through and the test binary fails at run time with:

    error while loading shared libraries: libselenium_core.so: cannot open shared
    object file: No such file or directory

Confirmed by inspection after an override build:
- `target/getFromGitHubReleases/selenium_core/shared_lib` → EXISTS (substitute
  published it correctly).
- `target/build/selenium_core/shared_lib` → MISSING (the label the consumer's
  `dep_artifact(...)` reads).

So `--overrideDep` relabels the build DAG (scheduling layer) but not the artifact
READ layer. A consumer reading `dep_artifact("<real>", key)` after an override
finds nothing.

## Fix

`_read_dep_artifact` should consult `AEB_OVERRIDE_DEP` and, when `dep_module`
matches a `<real>` entry, resolve the artifact under the `<sub>` node's target
dir instead — exactly the read-redirect the design reply proposed (mirroring how
`--veto-policy` threads an env into the out-of-process node binary). Then a
consumer's `dep_artifact("selenium_core/.build.ae", "shared_lib")` transparently
returns the substitute's published path, and existing `.tests.ae` /
`.package.ae` nodes need no change.

(The build-set PRUNE layer is separate and already effectively happens here — the
real node is dropped from the schedule; it's only the READ that misses.)

## Impact

Blocks the intended use of `--overrideDep`: supplying a prebuilt/fetched engine
to a binding build with no Aether toolchain. The selaenium
`.getFromGitHubReleases.ae` node is ready and correct; it just can't be consumed
until the read-redirect lands. Non-urgent — the normal (build-the-engine) path is
green.
