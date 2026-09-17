# selenium-webdriver (Ruby)

Selenium WebDriver for Ruby — a thin Fiddle wrapper over the shared pure-Aether
WebDriver engine (`libselenium_core`). The gem carries no protocol logic: the
W3C command map, routing, `By` normalization, error decode and the HTTP round
trip all live in the engine. Ruby ≥ 3.0, no runtime gem dependencies (stdlib
Fiddle + json only).

## Use it (as a Ruby dev)

> **Name note.** This gem is named `selenium-webdriver` on purpose — it is a
> drop-in, ABI-matched replacement for the mainstream Selenium-Ruby gem (upgrade
> by changing only the source). It is **NOT published to rubygems.org**, so a
> bare `gem install selenium-webdriver` installs the *classic* Selenium team's
> gem, not this one. Install THIS gem from its built `.gem` file:

```sh
# build the gem (see "Build the gem" below), then install it locally:
gem install --local target/package/ruby/dist/selenium-webdriver-*.gem
```

```ruby
# then fetch the prebuilt engine once (no Aether toolchain):
require 'selenium-webdriver'
Selenium::WebDriver.fetch_engine!     # download + verify + cache libselenium_core
```

The gem deliberately ships no engine and needs no Aether toolchain to install.
`fetch_engine!` downloads the prebuilt `libselenium_core` for your platform from
THIS project's GitHub releases, verifies its published `.sha256`, and caches it
(`$XDG_CACHE_HOME/selaenium/<tag>/`); every later `require 'selenium-webdriver'`
loads it automatically. It takes `tag:` (pin an engine release) and `force:`
(re-fetch). If the engine isn't present, the first driver call raises a
`LoadError` telling you to run it.

> Working in the source tree instead of an installed gem? The Rakefile there
> wraps the same call: `rake selenium:fetch_engine` (env `TAG=` / `FORCE=`) and
> `rake selenium:engine_path`. The Rakefile is a dev convenience and is **not**
> shipped in the gem — an installed consumer uses `Selenium::WebDriver.fetch_engine!`.

(The repo's top-level README also has a one-line installer that builds + installs
from source.)

```ruby
require 'selenium-webdriver'

driver = Selenium::WebDriver.for(:chrome)          # or headless_chrome(url) / firefox / edge
driver.get('https://example.com')
puts driver.title
puts driver.find_element(Selenium::WebDriver::By::ID, 'main').text
driver.quit
```

The engine can also be pinned explicitly, ahead of any discovery:
`Selenium::WebDriver.configure_native_lib('/abs/path/libselenium_core.so')`, or
via the `SELENIUM_CORE_LIB` env var.

## Build the gem (as a packager)

The gem bundles the engine `.so` under `lib/selenium/native/`. There are two ways
to get it there.

**With the Aether toolchain** — build the engine from source:

```sh
aeb ruby/.package.ae
```

**Without any Aether toolchain** — fetch the prebuilt engine from the release and
bundle that, via aeb's `--overrideDep` (aeb 0.314+):

```sh
aeb ruby/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae
```

This relabels the gem's engine-build dependency to the fetch node
([`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)),
which downloads + `.sha256`-verifies + stages the prebuilt engine — no compiler,
no `ae`. Either way the result is `target/package/ruby/dist/selenium-webdriver-<v>.gem`
with the engine inside. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the full flow, the per-binding override targets, and the checksum caveat.

## Layout

```
lib/selenium-webdriver.rb   the public API + VERSION / ENGINE_VERSION + fetch_engine!
lib/selenium/native.rb      the raw Fiddle binding over the aether_sel_embed_* C ABI
lib/selenium/engine_fetcher.rb  download + verify + cache the prebuilt engine
lib/selenium/webdriver.rb   the idiomatic WebDriver / WebElement surface
Rakefile                    rake selenium:fetch_engine / :engine_path
.package.ae                 aeb node → builds the gem with the engine bundled
.tests.ae                   aeb node → the binding test suite
.example.ae                 aeb node → installs the built gem clean + drives Chrome
```
