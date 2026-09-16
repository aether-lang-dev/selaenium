# aeb: always-build the native artifact + conditionally GENERATE the consumer manifest (+ `--overrideDep`)

**From:** selaenium, 2026-09-16. **Status:** feature request — a cross-cutting
aeb capability, not a selaenium one-off. Grounded in a concrete gap (Gleam), but
the fix is general across every aeb language whose consumers use a native package
manager.

## The problem, stated generally

An aeb binding is consumed two ways:

1. **Via aeb** — the `.tests.ae` / `.package.ae` node carries the real dependency
   edges (`dep("erlang/.build.ae")`, `dep_artifact(…, "erl_libs")`,
   `env("ERL_LIBS", …)`, `-L`/rpath, staged `.so`, …). Everything resolves.
2. **Via the binding's OWN package manager, with no aeb** — a plain dev does
   `gleam add` / `mix deps.get` / `cargo add` / `gem install` / `npm i` and gets
   ONLY what the checked-in manifest (`gleam.toml`, `mix.exs`, `Cargo.toml`,
   `*.gemspec`, `package.json`, …) declares.

The native/engine edge that makes the binding actually work often lives ONLY in
the aeb node, NOT in the consumer manifest — because a native manifest frequently
can't express it (a NIF built from C, a prebuilt engine `.so`, an rpath). So a
plain consumer gets a manifest that compiles and then fails at the first real
call.

**Gleam is the sharpest instance.** `gleam/gleam.toml`'s `[dependencies]` is just
`gleam_stdlib` — ZERO references to the engine or the `selenium_nif` NIF it calls
via `@external(erlang, "selenium_nif", …)`. The NIF (`.beam` + `priv/selenium_nif.so`,
which links `libselenium_core`) is produced ONLY by the aeb `erlang.nif()` node
and wired in ONLY by `gleam/.tests.ae`'s `dep("erlang/.build.ae")` +
`env("ERL_LIBS", …)`. A `gleam add selenium` consumer with no aeb hits
`erlang:nif_error(not_loaded)` on the first call. (Surveyed the matrix: gleam's
manifest has 0 engine-refs; most others now have some, largely from the
engine-fetch work — but the principle is the same wherever the manifest is
incomplete.)

The INTENDED consumer is the plain-language dev in their own repo WITHOUT aeb. So
the checked-in manifest must be complete for them.

## What we'd like from aeb (two mechanisms)

### 1. Conditionally GENERATE the consumer manifest as a build step

aeb should be able to emit/augment the consumer manifest (`gleam.toml`, etc.) as
part of a package build — CONDITIONALLY (only when producing a consumer package),
filling in the native/engine edge the checked-in manifest deliberately leaves
lean. Today aeb only WRAPS the manifest (the gleam SDK runs `gleam deps download`
from `source_dir` so the on-disk `gleam.toml` resolves; it never writes one). We
want a declarative "generate the consumer manifest with these extra edges" node
so the same source of truth (the aeb graph) that knows the NIF/engine dependency
can express it into the artifact a Hex/pub/crates consumer receives.

Shape (illustrative — you design the real grammar):

    gleam.package() {
        // the native edge aeb knows but gleam.toml can't state by hand:
        generate_manifest() {
            depends_native("selenium_nif")     // -> emitted into the shipped gleam.toml / rebar
            engine_from(fetch_cache_or_prebuilt) // how the consumer obtains libselenium_core
        }
    }

### 2. `--overrideDep=dep("<node>")=/path/to/artifact`

Let a build point a dep edge at a PREBUILT artifact instead of rebuilding it:

    aeb gleam/.package.ae --overrideDep='dep("erlang/.build.ae")=/path/to/selenium_nif'

So generating the consumer manifest (mechanism 1) can reference a real,
already-built artifact path, and CI / a release job can supply a prebuilt NIF or
engine `.so` rather than rebuilding the whole dependency subtree. Today
`dep_artifact()` resolves only via `_read_dep_artifact` reading the dep's target
dir — there is no flag/env to redirect it. This is the lever that makes a
generated manifest point at something that exists.

## Why "always build the native artifact"

The native artifact (the NIF `.so`, the engine `.so`) must ALWAYS be produced by
the build so the generated manifest / a fetch step has something real to point
at. aeb's `erlang.nif()` already always builds `selenium_nif`; the ask is to make
that guarantee a general, declared property so mechanism 1 can rely on it across
languages.

## Scope (who builds what)

- **aeb (this ask):** the generate-consumer-manifest node grammar + `--overrideDep`
  resolution + the always-build-native guarantee. General, not selaenium-specific.
- **selaenium (follow-up, ours):** per-binding `.package.ae` nodes that USE the
  above to emit complete consumer manifests + wire the BEAM-family NIF fetch
  (gleam/elixir/erlang share one NIF), plus consumer-install proofs
  (`.example.ae`) that build the plain-language path with no aeb, catching the
  `not_loaded` cliff.

Non-urgent — the aeb-driven build + test path is fully green today; this closes
the plain-consumer (no-aeb) DX gap, with Gleam as the first target.
