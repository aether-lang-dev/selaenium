# selenium (Elixir) — idiomatic Elixir over the Erlang NIF

Selenium WebDriver for Elixir — a `Selenium` module (with `Selenium.By`) over
the shared BEAM NIF, results as `{:ok, value}` / `{:error, {code, message}}`.

Elixir adds **no engine of its own** — and no second NIF. The engine is one
pure, reentrant shared library — a single .so/.dylib/.dll … NOT an installation,
a service, or a framework: no installer, no daemon, no config, no special
directories. Elixir reaches it **through the host artifact — the Erlang NIF**
(`:selenium_nif`, the one BEAM binding to the engine, `defdelegate`d onto here),
so the whole engine story — building the NIF, how the `.so` travels, `ERL_LIBS`,
`SELENIUM_CORE_LIB` — lives in [`erlang/README.md`](../erlang/README.md). Erlang
owns the shared NIF for the whole BEAM family (Erlang/Elixir/Gleam load the SAME
compiled `:selenium_nif`); an Elixir-specific NIF would only be a second copy of
the C ABI to drift.

## Using it (Elixir app developer)

Depend on the `selenium_nif` OTP app (on `ERL_LIBS`, or as a dep), then:

```elixir
{:ok, d} = Selenium.headless_chrome("http://127.0.0.1:9515")
{:ok, _} = Selenium.get(d, "https://example.com")
{:ok, title} = Selenium.title(d)
{:ok, el} = Selenium.find_element(d, Selenium.By.id("main"))
{:ok, text} = Selenium.element_text(d, el)
Selenium.quit(d)
```

Locators come from the `Selenium.By` factory (`By.id`, `By.css`, `By.class_name`,
`By.xpath`, …) — or a literal `{:id, "main"}` tuple — and `find_element/2`
returns an opaque element-id handle you pass to `element_text/2`, `click/2`, and
the rest. Command params are Elixir maps/lists; results are decoded JSON. A
session is an opaque integer handle.

## Layout

```
lib/selenium.ex          the idiomatic Selenium.* WebDriver surface (+ BiDi, waits, Select)
lib/selenium/by.ex        the Selenium.By locator factory
lib/selenium/native.ex    defdelegates onto the shared :selenium_nif NIF (no second C source)
mix.exs                   the mix project (app :selenium, no third-party deps)
test/selenium_test.exs    FFI + live-surface test over the shared NIF
.tests.ae                 aeb node → deps erlang/.build.ae, wires ERL_LIBS, runs mix test
```

Elixir adds no engine — see [`erlang/README.md`](../erlang/README.md) for the
NIF and how the engine is bundled.
