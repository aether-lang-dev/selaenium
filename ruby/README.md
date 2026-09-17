# selenium-webdriver (Ruby)

Selenium WebDriver for Ruby — a thin Fiddle wrapper over the shared pure-Aether
WebDriver engine (`libselenium_core`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` you `dlopen` (N independent sessions per process). It is
**not** an installation, a service, or a framework: no installer, no daemon, no
config, no special directories. The gem carries no protocol logic — the W3C
command map, routing, `By` normalization, error decode and the HTTP round trip
all live in that one library. The recommended model is to **seal the engine into
the gem at build time** (below) so the artifact you ship is complete and
hermetic. Ruby ≥ 3.0, no runtime gem dependencies (stdlib Fiddle + json only).

> **Name note.** This gem is named `selenium-webdriver` on purpose — it is a
> drop-in, ABI-matched replacement for the mainstream Selenium-Ruby gem (upgrade
> by changing only the source). It is **NOT published to rubygems.org**, so a
> bare `gem install selenium-webdriver` installs the *classic* Selenium team's
> gem, not this one — you build this one from the repo (below).

## Get started

There is no registry install; you build the gem (with the engine sealed in), then
install and use it — build → install → drive.

**1. Build the gem** (with the `aeb` build tool). It bundles the engine `.so`
into `lib/selenium/native/`. Two options — grab the prebuilt engine, or build it:

```sh
# (a) grab the prebuilt engine from the release (nothing to compile):
aeb ruby/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae

# (b) build the engine from source instead:
aeb ruby/.package.ae
```

Same gem either way (`target/package/ruby/dist/selenium-webdriver-<v>.gem`) with
the same engine bytes inside — (a) downloads it, (b) compiles it. An arbitrary
choice; pick whichever suits you. (The `aeb` tool and what building the engine
from source entails are covered elsewhere — see the top-level README; a Ruby
project only needs the resulting gem.)

**2. Install it for regular Ruby project use** (from the local `.gem` file, not
from rubygems.org) so any project can `require 'selenium-webdriver'`:

```sh
gem install --local target/package/ruby/dist/selenium-webdriver-*.gem
```

**3. Drive a browser.** The engine is already sealed into the gem (step 1 bundled
it), so there is nothing else to set up:

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

(The repo's top-level README also has a one-line installer that builds + installs
from source.)

## Fetch the engine instead of compiling it (`--overrideDep`)

Step 1(a) above relabels the gem's engine dependency to the fetch node
([`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)),
which downloads + `.sha256`-verifies + stages the prebuilt engine `.so` from the
release rather than compiling it — so there's no engine source to build. See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the full flow, the per-binding override targets, and the checksum caveat.

## Alternative: fetch the engine at run time (escape hatch)

The normal flow seals the engine into the gem at build time (step 1), so nothing
fetches at run time and the installed artifact is complete and hermetic. This is
the fallback for the exception: a gem that somehow shipped WITHOUT its engine (a
stripped gem, or one built with `native/` empty).

```ruby
require 'selenium-webdriver'
Selenium::WebDriver.fetch_engine!     # download + verify + cache libselenium_core
```

`fetch_engine!` is **never triggered implicitly** — the loader raises a
`LoadError` rather than silently phoning home; you call it deliberately. Prefer
rebuilding/resealing the gem over relying on it. When called, it downloads the
prebuilt engine for your platform from THIS project's GitHub releases — the SAME
release + asset + `.sha256` the `.getFromGitHubReleases.ae` build node fetches
(API path = stdlib `net/http`; build-node path shells `scripts/fetch-engine.sh`;
same URL, same checksum, same `$XDG_CACHE_HOME/selaenium/<tag>/` cache) — then a
later `require 'selenium-webdriver'` loads it. It takes `tag:` and `force:`.

Loader search order: explicit (`configure_native_lib`) → `SELENIUM_CORE_LIB` →
the gem's bundled `native/` → the fetch cache → bare name. The sealed bundle wins
over the fetch cache, which is why a properly built gem never needs this.

From the source tree (not an installed gem) the Rakefile wraps the same call:
`rake selenium:fetch_engine` (env `TAG=` / `FORCE=`) and `rake selenium:engine_path`.
The Rakefile is a dev convenience and is **not** shipped in the gem.

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
