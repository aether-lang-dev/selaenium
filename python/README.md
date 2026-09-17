# selenium (Python)

Selenium WebDriver for Python — a thin `ctypes` wrapper over the shared
pure-Aether WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` you `dlopen` (N independent sessions per process). It is
**not** an installation, a service, or a framework: no installer, no daemon, no
config, no special directories. The package carries no protocol logic — the W3C
command map, routing, `By` normalization, error decode and the HTTP round trip
all live in that one library. The recommended model is to **seal the engine into
the wheel at build time** (below) so the artifact you ship is complete and
hermetic. Python ≥ 3.8, stdlib only (`ctypes` + `json` + `urllib`).

> **Name note.** This distribution is named `selenium` on purpose — it is a
> drop-in, ABI-matched replacement for the mainstream Selenium-Python package
> (your app code is identical to upstream). It is **NOT published to PyPI**, so a
> bare `pip install selenium` installs the *classic* Selenium team's package, not
> this one — your platform team builds and publishes this one in-house (below).

## Using it (Python app developer)

You consume it like any other package — from wherever your shop publishes it (a
private index: a devpi / Artifactory / CodeArtifact server, or a `--find-links`
wheelhouse), since it is not on PyPI. Your platform/DevOps team builds and
publishes it in-house (next section); you just:

```python
# requirements.txt / pyproject:  selenium   (from your internal index), then:
from selenium import webdriver
from selenium.webdriver.common.by import By

driver = webdriver.Chrome()                 # engine launches its own chromedriver
driver.get("https://example.com")
print(driver.title)
print(driver.find_element(By.ID, "main").text)
driver.quit()
```

The engine ships sealed inside the wheel (`selenium/native/`), so there is
nothing to install, compile, or configure — no `aeb`, no `ae`, no compiler. It's
a normal wheel (no C-extension build on `pip install`, no third-party runtime
deps) that `dlopen`s its bundled `.so`. To point at a different engine, ahead of
any discovery: `selenium.webdriver.configure_native_lib("/abs/path/libselenium_core.so")`,
or the `SELENIUM_CORE_LIB` env var.

## Building & publishing the wheel (platform / DevOps)

The team that owns the Aether tooling builds the wheel once — with the engine
sealed in — and pushes it to the shop's internal index. App developers never
touch `aeb`/`ae`.

**1. Build the wheel** (with the `aeb` build tool). It bundles the engine `.so`
into `selenium/native/`. Two options — grab the prebuilt engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb python/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb python/.package.ae
```

Same wheel either way (`target/package/python/dist/selenium-<v>-*.whl`) with the
same engine bytes inside — (a) downloads it, (b) compiles it. An arbitrary
choice; pick whichever suits your pipeline. (The `aeb`/`ae` toolchain is covered
in the top-level README; the produced wheel needs none of it to consume.)

**2. Publish it to your internal index**, e.g.

```sh
twine upload --repository-url https://pypi.your-shop.internal \
    target/package/python/dist/selenium-*.whl
# or `pip install <path>.whl` for a one-off / CI cache.
```

From there it's a normal private package: app developers add `selenium` from that
index and `import` it (above), engine and all.

## Fetch the engine instead of compiling it (`--overrideDep`)

Step 1(a) above relabels the wheel's engine dependency to the fetch node
([`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)),
which downloads + `.sha256`-verifies + stages the prebuilt engine `.so` from the
release rather than compiling it — so there's no engine source to build. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the full flow, the per-binding override targets, and the checksum caveat.

## Alternative: fetch the engine at run time (escape hatch)

The normal flow seals the engine into the wheel at build time (step 1), so
nothing fetches at run time and the installed artifact is complete and hermetic.
This is the fallback for the exception: a wheel that somehow shipped WITHOUT its
engine (a stripped wheel, or one built with `native/` empty).

```sh
python -m selenium.fetch_engine        # download + verify + cache libselenium_core
```

It is **never triggered implicitly** — the loader raises an error rather than
silently phoning home; you run it deliberately. Prefer rebuilding/resealing the
wheel over relying on it. It downloads the prebuilt engine for your platform from
THIS project's GitHub releases — the SAME release + asset + `.sha256` the
`.getFromGitHubReleases.ae` build node fetches, cached under
`$XDG_CACHE_HOME/selaenium/<tag>/`. `--tag` pins a release, `--force` re-fetches,
`--path` prints the cache location; `selenium.webdriver.fetch_engine(...)` is the
importable form. Loader search order: explicit (`configure_native_lib`) →
`SELENIUM_CORE_LIB` → the wheel's bundled `native/` → the fetch cache → bare name
— the sealed bundle wins, which is why a properly built wheel never needs this.

## Layout

```
selenium/_native.py       the raw ctypes binding over the aether_sel_embed_* C ABI
selenium/_webdriver.py    the idiomatic WebDriver / WebElement surface
selenium/engine_fetcher.py   download + verify + cache the prebuilt engine
selenium/fetch_engine.py  python -m selenium.fetch_engine CLI
setup.py                  wheel packaging; ships selenium/native/* via package_data
.package.ae               aeb node → builds the wheel with the engine bundled
.tests.ae                 aeb node → the binding test suite
.example.ae               aeb node → installs the built wheel clean + drives Chrome
```
