# selenium-webdriver (Node.js)

Selenium WebDriver for Node — a thin [koffi](https://koffi.dev) FFI binding over
the shared pure-Aether WebDriver engine (`libselenium_core`), presenting the
mainstream `selenium-webdriver` API (`Builder` / `By` / `until` / `Key` / …).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` the binding `dlopen`s through koffi (N independent sessions
per process). It is **not** an installation, a service, or a framework: no
installer, no daemon, no config, no special directories. This package is the Node
*face* — it carries no protocol logic; the W3C command catalog, route table, path
templating, `By` normalization, error decode and the HTTP round trip all live in
that one library.

> **Name note.** The package is named `selenium-webdriver` and the API is an
> ABI/name match to mainstream Selenium-JS (an unmodified `await`-style upstream
> script runs unchanged). It is **NOT published to npm**, so a bare
> `npm install selenium-webdriver` pulls the *classic* Selenium team's package,
> not this one — your platform team builds and publishes this one to your internal
> registry (below).

## Using it (Node app developer)

Install the tarball from your internal registry, then use the mainstream surface
— the public API is fully async (Promise-returning), so existing await-style code
works as-is even though the engine's FFI round trip blocks internally:

```js
const { Builder, By, until, Key } = require('selenium-webdriver')

const driver = new Builder().forBrowser('chrome').build() // engine launches chromedriver
try {
  await driver.get('https://example.com')
  console.log(await driver.getTitle())
  await driver.findElement(By.css('h1')).click()
  await driver.wait(until.titleContains('Example'), 5000)
} finally {
  await driver.quit()
}
```

The engine ships **inside** the package (in `native/`) and koffi loads it —
nothing to install, compile, or configure at consume time. To point at a specific
engine, ahead of any discovery, call
`require('selenium-webdriver').configureNativeLib('/abs/path/libselenium_core.so')`
before first use (it wins over everything else, and is a no-op once loaded), or
set the `SELENIUM_CORE_LIB` env var.

The top-level exports match upstream: `Builder`, `WebDriver`, `WebElement`,
`By`/`RelativeBy`/`locateWith`, `until`, `Key`/`Keys`, `Button`/`Actions`,
`Select`, `Capabilities`/`Browser`, the `manage()`/`navigate()`/`switchTo()`
facades, the `error` namespace (with legacy `...Exception` aliases for older
code), plus a binding-specific `BiDi` surface and the `DriverProcess` /
`ensureDriver` orchestration helpers.

## Building & publishing the tarball (platform / DevOps)

The `.package.ae` node bundles the engine `.so` into `native/` (whitelisted in
`package.json` `"files"`, so `npm pack` ships it) and packs the tarball, then
publishes the pkgout dir on the `tarball_dir` edge (consumed by
`javascript/.example.ae`, which installs the tarball clean and drives Chrome).
The native loader resolves the engine at first call: a `configureNativeLib()`
path → `SELENIUM_CORE_LIB` → the bundled `native/<lib>` → the bare library name.

Grab the prebuilt engine instead of building it with `--overrideDep`, then
publish to your internal registry:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb javascript/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb javascript/.package.ae

npm publish javascript/pkgout/*.tgz \
    --registry https://npm.your-shop.internal
```

Same engine bytes either way. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the `--overrideDep` fetch-node flow.

## Layout

```
index.js                 the top-level surface (Builder / By / until / Key / … re-exports)
index.d.ts               the TypeScript type surface
lib/webdriver.js         WebDriver / WebElement / ShadowRoot / Builder / BiDi over the engine
lib/native.js            the koffi binding + engine loader (SELENIUM_CORE_LIB → bundled native/)
lib/by.js                By / RelativeBy / locateWith locators
lib/until.js             the wait conditions
lib/input.js             Key / Button / Actions
lib/error.js             the WebDriverError hierarchy (+ upstream error namespace)
lib/select.js            the Select support helper
lib/capabilities.js      Capabilities / Browser
lib/logging.js           logging
.package.ae              aeb node → bundles the engine into native/, packs the npm tarball
.tests.ae                aeb node → the binding test suite
.example.ae              aeb node → installs the packed tarball clean + drives Chrome
```
