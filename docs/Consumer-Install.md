# Consumer-install proofs (`.example.ae`)

There are two test layers in this repo, and they answer different questions.

| Layer | Question | What it uses |
|-------|----------|--------------|
| `<lang>/.tests.ae` | Does the binding work? | the **source tree**, engine `.so` handed in via `SELENIUM_CORE_LIB` |
| `<lang>/.example.ae` | Does the thing we **publish** work? | the built wheel / gem / npm package / jar / crate / module, installed into a clean environment, with no source tree and `SELENIUM_CORE_LIB` **unset** |

Each `.example.ae` builds the distributable via the matching `.package.ae`,
installs it somewhere clean, asserts the engine `.so` actually shipped inside,
and then runs a consumer program against it in three modes: `ffi` (marshalling
works), `discovery` (the bundled `.so` is found with zero configuration), and
`live` (it drives real headless Chrome).

Eleven bindings have one: python, ruby, javascript, java, go, rust, dart, nim,
zig, lua, d. **swift does not — and should.**

## Why this layer is not optional

A `.tests.ae` cannot see a packaging bug, because it never packages anything.
Every one of these was green in `.tests.ae` while the published artifact was
broken:

- **The Python wheel shipped no engine at all.** `.package.ae` staged
  `libselenium_core.so` into `python/selenium_core/native/` — the package's
  pre-rename name — while `setup.py` ships `package_data` for `selenium`. The
  `.so` landed outside the package. Inspecting the built wheel: `.so entries:
  []`. `pip install` gave you a binding that could not work.
- **The packaged Rust crate could not compile.** The staging list named only
  `src/lib.rs` and `src/json.rs`; the crate had since gained `actions.rs`,
  `keys.rs`, `select.rs`, `wait.rs`. A consumer got
  `E0583: file not found for module 'wait'`.
- **The JavaScript consumer was two renames behind** — `require('selenium-core')`
  against a package now called `selenium-webdriver`, and the pre-async API
  (`By.ID`, `d.title`) — so the proof failed before proving anything.
- **swift/Package.swift linked with a relative `-L native`.** That resolves
  against the linker's working directory, which is ours only while we build the
  package ourselves; for a consumer it resolves against THEIR directory and the
  build dies with `cannot find -lselenium_core`. Found by hand, by reading the
  sibling `servirtium-vcr` repo's notes — it had the identical bug, and records
  that its own `swift/.tests.ae` stayed green throughout. selaenium has no
  `swift/.example.ae`, so nothing here would have caught it.

The common shape: **a rename or an addition in the source tree that the
packaging list did not follow.** Nothing in a source-tree test can notice.

## Running them

```sh
aeb python/.example.ae          # one binding
aeb .presubmit.ae               # all of them, with everything else
```

They are part of `.presubmit.ae`. They were previously omitted on the belief
that they still needed an aeb `consumer_example()` builder; they do not — all
eleven run under aeb v0.309.

## Adding one for a new binding

Copy the nearest existing node by packaging mechanism (`python/` for a
per-language package manager, `rust/` for a path-dep crate, `go/` for a module
with a bundled `native/`). The rules that matter:

1. **Assert the asset shipped** (`asset_glob(...)`) before running anything —
   a missing `.so` should fail as "the package is incomplete", not as some
   confusing downstream error.
2. **Install into a clean location** and unset `SELENIUM_CORE_LIB`, or the proof
   silently passes by finding the source tree.
3. **Stage every file the package needs**, and keep that list in step when
   modules are added — that is what broke rust.
4. **Any path in a package manifest must be absolute or self-locating**
   (`#filePath`, `__DIR__`, `currentSourcePath()`, `b.pathFromRoot()`), never
   relative to the working directory.
