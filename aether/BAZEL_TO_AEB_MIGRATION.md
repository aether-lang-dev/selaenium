# Killing Bazel, replacing with idiomatic aeb — scoping

Goal (per the directive): **no Bazel in our branch; the whole build is aeb.**

This document scopes that honestly before any BUILD files are touched. The
`aether/` bindings tree is already 100% aeb; this is about the **classic
Selenium tree** (java/, py/, rb/, javascript/, dotnet/, rust/, common/, …) that
we inherited from upstream on the `classic-selenium` base of `main`.

## What Bazel actually is in this repo (measured)

| Thing | Count | Notes |
|---|---:|---|
| `BUILD.bazel` files | 307 | java 180, third_party 61, rb 18, javascript 16, common 13, dotnet 10, rust 3, py 2, cpp 2 |
| Custom `.bzl` (Starlark) macros | 75 | NOT third_party — our own build logic |
| `load()` statements | 562 | the dependency web between them |
| External rule sets (`bazel_dep`) | 27 | rules_java, rules_ruby, rules_python, rules_dotnet, rules_closure, aspect_rules_{js,ts,jest,esbuild}, rules_jvm_external (Maven), rules_oci, rules_pkg, protobuf, LLVM, … |
| `MODULE.bazel` | 20 KB | the dependency + toolchain graph, with patched external rules |

Top rule usages: `closure_js_library` ×227 (the JS atoms via Closure Compiler),
`java_library` ×108, `java_test_suite` ×64, `java_selenium_test_suite` ×34,
`java_export` ×22 (Maven publishing), `rb_library`/`py_library` ×27 each,
`genrule` ×18, plus `js_run_binary`, `py_wheel`, OCI images, etc.

The load-bearing custom macros (the real work, none of which is a thin wrapper):

- **Protocol codegen**: `generate_devtools` (CDP), `generate_bidi`,
  `generate_bidi_protocol` — generate client code from the W3C BiDi + CDP specs,
  per language. Java, Python, .NET, JS each have their own.
- **JavaScript atoms**: 227 `closure_js_library` targets compiled with the
  Google Closure Compiler into the shared atoms every binding embeds.
- **Publishing**: `java_export` → Maven Central, `nuget_pack`/`nuget_push` →
  NuGet, `py_wheel` → PyPI, Ruby gem, npm.
- **Selenium Manager**: the Rust binary (`common/selenium_manager.bzl`), driver
  downloads (`common/private/drivers.bzl`), Debian/dmg/pkg archives.
- **Grid**: the Java server assembly + `java_selenium_test_suite` (browser
  matrix), OCI images (`rules_oci`).
- **Docs**: sphinx (py), docfx (.NET), javadoc.

## The honest gap against aeb

aeb has broad language SDK coverage (`lib/{java,ruby,python,dotnet,rust,maven,
pnpm,ts,go,…}`), and its DAG/incremental-cache/affected-target machinery is
solid. But this repo uses Bazel for things aeb has **no equivalent** for today:

1. **Closure Compiler (`closure_js_library`, ×227).** aeb has `ts`/`pnpm`, not a
   Closure atoms pipeline. This is the single biggest surface and it is
   security/correctness-sensitive (the atoms are the shared browser-automation
   JS every binding runs).
2. **Spec-driven protocol codegen** (BiDi/CDP → per-language clients). These are
   bespoke Starlark generators; aeb has no codegen SDK for them. (aeb *can* shell
   to a generator via `regen(...)`, so this is portable but not free.)
3. **Publishing to Maven/NuGet/PyPI/RubyGems/npm** with the exact coordinates,
   signing, and metadata `java_export`/`nuget_push`/`py_wheel` produce. aeb's
   `maven` SDK resolves *consumption*; the *publish* side is TODO in aeb (per its
   own scope table).
4. **Hermetic toolchains + pinned external deps.** Bazel pins every compiler and
   transitive dep (MODULE.bazel + lockfiles) and is reproducible. aeb
   deliberately uses whatever is on PATH (a documented, intentional divergence).
   A migration trades reproducibility for PATH-selection — a real behaviour
   change, not just a syntax swap.
5. **No Bazel to diff against.** There is no `bazel`/`bazelisk` on this box
   (`.bazelversion` pins 9.1.0 but nothing runs it), so a migration cannot be
   validated against a Bazel baseline here — only against the real toolchains.

## Why "translate 307 BUILD files" is the wrong mental model

Most of the value is in the 75 custom macros, not the BUILD files. A faithful
migration is really "reimplement 75 pieces of build logic (codegen, Closure,
publishing, packaging) as aeb SDKs or scripts," several of which need **new aeb
features we'd drive upstream** (the directive explicitly allows this). The BUILD
files then become thin `.build.ae` leaves over those SDKs.

## Recommended path — incremental, per-language, lowest-risk-first

Big-bang is off the table (307 files, no baseline to diff, security-sensitive
atoms). Instead, **migrate one language tree at a time, leaf-first**, keeping
Bazel working for the rest until each is proven. Ordered by tractability:

1. **Python** (2 BUILD files, aeb has a python SDK). *But* it pulls
   `generate_bidi`/`generate_devtools` (codegen) + `py_wheel` (publish). Do the
   codegen as an aeb `regen`-shelled generator; wheel via `setup.py`/`build`
   (like the `aether/python` consumer layer already does). **First milestone:
   `aeb py/.build.ae` produces the same wheel Bazel does, byte-comparable.**
2. **Ruby** (18 files) — `rb_library` → aeb `ruby` SDK; gem build already proven
   in `aether/ruby`.
3. **Rust / Selenium Manager** (3 files) — aeb `rust` SDK; a self-contained cargo
   crate, the cleanest corner.
4. **.NET** (10 files) — aeb `dotnet` SDK; NuGet publish is the gap.
5. **JavaScript** (16 files + 227 closure targets) — **the hard one.** Needs a
   Closure atoms story in aeb. Likely the last, possibly its own multi-week
   effort or an accepted scope reduction (ship prebuilt atoms).
6. **Java** (180 files) — **the biggest.** `java_export` (Maven), the Grid
   assembly, the browser test matrix, javadoc. Do it in sub-trees
   (client → remote → grid), not at once.
7. **common/ + third_party/ + MODULE.bazel** — deleted only when nothing else
   loads them. `MODULE.bazel` is the last thing to go (it is the whole external
   dependency graph); touching it early breaks everything.

Each step: land the aeb build for that tree, prove it produces the same
artifacts, delete that tree's BUILD.bazel/.bzl, THEN move on. Bazel and aeb
coexist during the transition (aeb ignores BUILD.bazel; Bazel ignores .build.ae).

## What I need from you before writing code

- **Scope of "done".** Is the bar (a) *build + test parity* per language, or
  also (b) *publish parity* (Maven/NuGet/PyPI signing)? (b) is a large multiplier.
- **Atoms.** For the JS Closure atoms — reimplement the Closure pipeline in aeb,
  or accept shipping prebuilt atoms (checked-in generated JS)?
- **Reproducibility.** Accept aeb's PATH-selected toolchains (the documented
  divergence), or is hermeticity a requirement (which aeb does not do today)?
- **Order.** Agree with "Python first as the pathfinder," or start elsewhere?

## Python tree — concrete findings (traced 2026-08-26)

Decisions locked: **build+test parity** (no publish); **Python first**; the JS
Closure atoms get a **feature request to the aeb sibling**, not a local hack.

The Python package is **NOT source-complete** — three code generators run at
build time and their output is never committed (`git ls-files
py/.../devtools/` → 0). Reproducing them is the core of the Python migration.
All three generators are **plain Python scripts** (`py/generate.py`,
`py/generate_bidi.py`, `py/generate_bidi_protocol.py`), which aeb can shell to
via `regen(...)` — the mechanism is easy. The inputs are the issue:

1. **DevTools / CDP client** (`generate_devtools`): `python generate.py
   <browser_protocol.pdl> <js_protocol.pdl> <outdir>`, once per
   `BROWSER_VERSIONS` (v150/v151/v152). Inputs are **checked in**
   (`common/devtools/chromium/vNNN/*.pdl`). ✅ Fully local, straightforward.
2. **BiDi client** (`generate_bidi`): needs **web-fetched CDDL specs** from
   w3c/webref at a pinned commit (`webdriver_bidi_all_cddl`, `permissions_…`,
   `prefetch_…`, `ua_client_hints_…`, `web_bluetooth_…`) plus local enhancement
   scripts. ⚠️ Network inputs (Bazel's `http_file`); no bazel cache on this box.
3. **Internal `_bidi` protocol** (`generate_bidi_protocol`): generates from
   `//javascript/selenium-webdriver:create-bidi-src_schema` — a **schema built by
   the JavaScript tree's** BiDi generator. ⚠️ Cross-tree dependency: Python's
   build is not self-contained; it needs a JS-tree codegen artifact.

**Consequence for the pathfinder choice:** "Python first" is entangled — (2)
needs a spec-fetch story and (3) drags in the javascript/ tree. That is more
than the smallest self-contained corner promised. Two ways forward:

- **P-A (vendor the specs):** pin + check in the fetched CDDL specs and the
  JS-produced BiDi schema as committed inputs (a `scripts/update_cddl`-style
  repin already exists on the Bazel side), so `aeb py/.build.ae` runs fully
  offline against in-tree inputs. Cleanest for a PATH-based, non-hermetic aeb
  build; decouples Python from the JS tree for the build.
- **P-B (migrate a truly self-contained corner first):** do **Rust / Selenium
  Manager** as the actual pathfinder (a standalone cargo crate, 3 BUILD files,
  no codegen, no cross-tree deps — aeb `rust` SDK already proven in
  `aether/rust`), then return to Python with the codegen story worked out.

## Rust / Selenium Manager pathfinder — DONE (build+test parity under aeb)

Landed 2026-08-26. Selenium Manager now builds and tests under aeb, no Bazel:

- `rust/.build.ae` → `rust.cargo_project_existing(b) { binary_name("selenium-manager") }`
  builds the binary against the **existing** Cargo.toml/Cargo.lock (never
  regenerates), and publishes it on the `cargo_binary` artifact edge. Verified:
  `selenium-manager 0.4.48-nightly` runs.
- `rust/.tests.ae` → `rust.cargo_test_existing(b) { extra("--lib") }` runs the
  library unit tests — **45 passed** — matching the old Bazel `:unit` target
  (`--lib` = lib unit tests only, not the browser/network integration tests
  under `rust/tests/`).

**aeb feature driven upstream:** the rust SDK's `cargo_build_cmd`/`cargo_test_cmd`
already *read* an `"extra"` option but had no **setter** for it — so `--lib`
couldn't be passed. Added an `extra(args)` setter to `aeb/lib/rust/module.ae`
(mirrors `jobs`/`features`). This is exactly the "drive aeb feature development"
the directive calls for. (Committed to the aeb repo separately; the installed
SDK at `~/.local/share/aeb/lib` was patched to match.)

### The deletion-order rule this surfaced (important)

You **cannot delete a tree's BUILD.bazel until every Bazel target that depends
on it is also off Bazel** — else the remaining Bazel build breaks. `//rust:*` is
consumed by `//common/manager` (the manager binary) and `//py` (srcs), so
**rust's BUILD files stay until common/manager + py are migrated (or Bazel is
gone entirely).** aeb building the tree and *deleting* its Bazel files are two
separate milestones; the deletion is bottom-up (leaves with no Bazel dependents
first). Concretely: aeb `.build.ae`/`.tests.ae` land NOW and coexist with Bazel;
the `rm BUILD.bazel` happens at the end, per reverse-dependency order.

## Recommendation

Start with **Python as a pathfinder** (smallest tree that still exercises the
hard shared problems: codegen + packaging). It will surface exactly which aeb
features are missing, at a scale we can finish and validate, before committing to
the java/ and javascript/ mountains. I would NOT touch `MODULE.bazel` or delete
any BUILD file until at least one language tree fully builds + tests under aeb.
