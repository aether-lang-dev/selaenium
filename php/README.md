# selaenium/selenium-webdriver (PHP)

Selenium WebDriver for PHP — a thin FFI wrapper over the shared pure-Aether
WebDriver engine (`libselenium_core`), in the `SeleniumCore` namespace.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` you `dlopen` (N independent sessions per process). It is
**not** an installation, a service, or a framework: no installer, no daemon, no
config, no special directories. The package carries no protocol logic — the W3C
command map, routing, `By` normalization, error decode and the HTTP round trip
all live in that one library. Requires PHP ≥ 8.1 with `ext-ffi`; no third-party
Composer runtime dependencies.

## Using it (PHP app developer)

`composer require selaenium/selenium-webdriver` from wherever your shop publishes
it (a private Composer repository — Satis / Packagist-private / a path repo), then
fetch the engine once (see below) and:

```php
use SeleniumCore\WebDriver;
use SeleniumCore\By;

$d = WebDriver::headlessChrome('http://127.0.0.1:9515');
$d->get('https://example.com');
echo $d->title(), "\n";
echo $d->findElement(By::ID, 'main')->text(), "\n";
$d->quit();
```

The engine is a single shared library the package `dlopen`s via `ext-ffi` — no
C-extension compile on install, no framework, no config. To point at a specific
engine, ahead of any discovery: `WebDriver::configureNativeLib('/abs/path/libselenium_core.so')`,
or the `SELENIUM_CORE_LIB` env var.

## Getting the engine

The PHP binding is consumed as a Composer package (no separate build step to
produce it). What a consumer does need is the engine `.so` present. Fetch the
prebuilt one for this platform:

```sh
composer fetch-engine          # or: php bin/fetch-engine
```

This downloads the prebuilt engine from THIS project's GitHub releases, verifies
its `.sha256`, and caches it under `$XDG_CACHE_HOME/selaenium/<tag>/` where the
FFI loader finds it. It is **never triggered implicitly** — nothing phones home
on autoload; you run it deliberately. `--tag=vX.Y.Z` pins a release, `--force`
re-fetches. Loader search order: explicit (`configureNativeLib`) →
`SELENIUM_CORE_LIB` → the bundled `native/` → the fetch cache → bare name.

Platform teams that vendor the engine into the package (so the shipped Composer
package is self-contained) stage it into `native/` at publish time; the fetch
above is the per-developer path. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the sealed-at-build model and the `--overrideDep` fetch node used by the other
bindings' package builds.

## Layout

```
src/WebDriver.php       the idiomatic WebDriver / WebElement / By surface
src/Native.php          the FFI binding over the aether_sel_embed_* C ABI
src/EngineFetcher.php   download + verify + cache the prebuilt engine
bin/fetch-engine        composer fetch-engine CLI
composer.json           PSR-4 autoload (SeleniumCore\) + the fetch-engine script
.tests.ae               aeb node → the binding test suite (phpunit)
```
