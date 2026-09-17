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
install and use it — build → install → drive. (Step 3 is a last-resort escape
hatch, not a normal step.)

**1. Build the gem.** It bundles the engine `.so` under `lib/selenium/native/`.
Pick ONE:

```sh
# (a) with the Aether toolchain — builds the engine from source:
aeb ruby/.package.ae

# (b) with NO Aether toolchain — fetches the prebuilt engine from the release
#     and bundles that (aeb 0.314+; see "No-toolchain build" below):
aeb ruby/.package.ae \
    --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae
```

Either produces `target/package/ruby/dist/selenium-webdriver-<v>.gem`.

**2. Install it for regular Ruby project use** (from the local `.gem` file, not
from rubygems.org) so any project can `require 'selenium-webdriver'`:

```sh
gem install --local target/package/ruby/dist/selenium-webdriver-*.gem
```

**3. Skip this — the engine is already sealed into the gem.** Step 1 bundled the
engine into `lib/selenium/native/`, and the loader finds that bundled copy, so go
straight to step 4. This is the point of sealing at build time: the artifact you
installed is complete, reviewable, and hermetic — nothing fetches at run time.

`Selenium::WebDriver.fetch_engine!` exists ONLY as a last-resort escape hatch for
a gem that somehow shipped WITHOUT its engine (a stripped gem, or one built with
`native/` empty). It is **not** part of the normal flow and is **never triggered
implicitly** — the loader raises a `LoadError` rather than silently phoning home;
you have to call it yourself. Prefer rebuilding/resealing the gem (step 1) over
relying on a runtime fetch. When you do call it, it downloads the prebuilt engine
for your platform from THIS project's GitHub releases — the SAME release + asset
+ `.sha256` the `.getFromGitHubReleases.ae` build node fetches (API path = stdlib
`net/http`; build-node path shells `scripts/fetch-engine.sh`; same URL, same
checksum, same `$XDG_CACHE_HOME/selaenium/<tag>/` cache), then a later `require`
loads it.

Loader search order: explicit (`configure_native_lib`) → `SELENIUM_CORE_LIB` →
the gem's bundled `native/` → the fetch cache → bare name. The sealed bundle wins
over the fetch cache, which is why a properly built gem never needs step 3.

**4. Drive a browser:**

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

> Working in the source tree instead of an installed gem? The Rakefile there
> wraps step 3: `rake selenium:fetch_engine` (env `TAG=` / `FORCE=`) and
> `rake selenium:engine_path`. The Rakefile is a dev convenience and is **not**
> shipped in the gem — an installed consumer uses `Selenium::WebDriver.fetch_engine!`.
> (The repo's top-level README also has a one-line installer that builds +
> installs from source.)

## No-toolchain build (`--overrideDep`)

Step 1(b) above relabels the gem's engine-build dependency to the fetch node
([`selenium_core/.getFromGitHubReleases.ae`](../selenium_core/.getFromGitHubReleases.ae)),
which downloads + `.sha256`-verifies + stages the prebuilt engine — so you cut a
gem with no compiler and no `ae`. See
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
