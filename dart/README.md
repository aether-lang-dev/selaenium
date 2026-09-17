# selenium (Dart)

Selenium WebDriver for Dart — a thin `dart:ffi` wrapper over the shared
pure-Aether WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` you `dlopen` (N independent sessions per process). It is
**not** an installation, a service, or a framework: no installer, no daemon, no
config, no special directories. The package carries no protocol logic — the W3C
command map, routing, `By` normalization, error decode and the HTTP round trip
all live in that one library.

> **Name note.** This package is named `selenium` and is **not published to
> pub.dev**. Consume it from your shop's private source (a path/git dependency, or
> an internal pub server); your platform team makes the engine available (below).

## Using it (Dart app developer)

Depend on `selenium` from wherever your shop provides it, then:

```dart
import 'package:selenium/selenium.dart';

void main() {
  final driver = WebDriver.headlessChrome('http://127.0.0.1:9515');
  driver.get('https://example.com');
  print(driver.title);
  print(driver.findElement(By.id('main')).text);
  driver.quit();
}
```

The engine is a single shared library the package `dlopen`s — nothing to install,
compile, or configure at consume time. To point at a specific engine, set the
`SELENIUM_CORE_LIB` env var to its absolute path before the first driver call.

## Making the engine available (platform / DevOps)

Unlike a gem/wheel, a Dart package is consumed as source; the engine `.so` is
staged into the package's `native/` (where the `dart:ffi` loader finds it) and
the package dir is what you provide downstream. The team that owns the Aether
tooling stages it once — grab the prebuilt engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb dart/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb dart/.package.ae
```

Same staged package either way, engine bytes identical — (a) downloads it, (b)
compiles it. An arbitrary choice; the `aeb`/`ae` toolchain is covered in the
top-level README, and consuming the package needs none of it.

## Fetch the engine instead of compiling it (`--overrideDep`)

Step (a) above relabels the package's engine dependency to the fetch node
([`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)),
which downloads + `.sha256`-verifies + stages the prebuilt engine `.so` from the
release rather than compiling it. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the full flow and the per-binding override targets.

## Alternative: fetch the engine at run time (escape hatch)

When the package's `native/` has no engine (a fresh checkout, say), fetch it once:

```sh
dart run selenium:fetch_engine        # download + verify + cache libselenium_core
```

It is **never triggered implicitly** — the loader raises rather than silently
phoning home; you run it deliberately. It downloads the prebuilt engine for your
platform from THIS project's GitHub releases — the SAME release + asset + `.sha256`
the `.getFromGitHubReleases.ae` build node fetches, cached under
`$XDG_CACHE_HOME/selaenium/<tag>/`. `--tag` pins a release, `--force` re-fetches,
`--path` prints the cache location. Loader search order: explicit path (set via
`Native.configure`, internal) → `SELENIUM_CORE_LIB` → the package's `native/` →
the fetch cache → bare name.

## Layout

```
lib/selenium.dart          the public export surface
lib/src/native.dart        the dart:ffi binding over the aether_sel_embed_* C ABI
lib/src/webdriver.dart     the idiomatic WebDriver / WebElement surface
lib/src/engine_fetcher.dart   download + verify + cache the prebuilt engine
bin/fetch_engine.dart      dart run selenium:fetch_engine
.package.ae                aeb node → stages the engine into native/
.tests.ae                  aeb node → the binding test suite
.example.ae                aeb node → consumes the package clean + drives Chrome
```
