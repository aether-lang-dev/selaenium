# selenium (Gleam) — idiomatic Gleam over the Erlang NIF

Selenium WebDriver for Gleam — a `selenium` module with typed `Result`s
(`Result(WebDriver, WebDriverError)`) over the shared BEAM NIF.

Gleam adds **no engine of its own** — and no second NIF. The engine is one pure,
reentrant shared library — a single .so/.dylib/.dll … NOT an installation, a
service, or a framework: no installer, no daemon, no config, no special
directories. Gleam reaches it **through the host artifact — the Erlang NIF**
(`selenium_nif`, the one BEAM binding to the engine, called via
`@external(erlang, "selenium_nif", …)`), so the whole engine story — building
the NIF, how the `.so` travels, `ERL_LIBS`, `SELENIUM_CORE_LIB` — lives in
[`erlang/README.md`](../erlang/README.md). Erlang owns the shared NIF for the
whole BEAM family (Erlang/Elixir/Gleam load the SAME compiled `selenium_nif`); a
Gleam-specific NIF would only be a second copy of the C ABI to drift.

## Using it (Gleam app developer)

With the `selenium_nif` app on `ERL_LIBS` (see the status note below), the
Gleam surface is:

```gleam
import selenium

pub fn main() {
  let assert Ok(d) = selenium.headless_chrome("http://127.0.0.1:9515")
  let assert Ok(_) = selenium.get(d, "https://example.com")
  let assert Ok(title) = selenium.title(d)
  let assert Ok(el) = selenium.find_element(d, selenium.by_id("main"))
  let assert Ok(text) = selenium.element_text(el)
  let _ = selenium.quit(d)
}
```

Locators come from the `by_*` factory functions (`by_id`, `by_css`,
`by_class_name`, `by_xpath`, …) yielding a `Locator`; `find_element` returns an
opaque `WebElement` you pass to `element_text`/`click`/`tag_name`. Command params
are JSON strings (build them with `gleam/json`); command results come back as the
raw JSON string of the response `value`, keeping the binding thin.

## Status / known limitation

Today Gleam works **when built through aeb**: `gleam/.tests.ae` deps
`erlang/.build.ae` and points `ERL_LIBS` at the Erlang NIF build, so
`selenium_nif` (and its `priv/selenium_nif.so`, which links `libselenium_core`)
resolves on the code path over the BEAM.

A standalone `gleam add selenium` is **not yet self-contained**. `gleam.toml`'s
`[dependencies]` declares only `gleam_stdlib` — it does **not** declare the
`selenium_nif` OTP app the `@external(erlang, "selenium_nif", …)` calls need. So
a plain Gleam project that adds this package (no aeb) does not get the NIF, and
the first real call raises `not_loaded` at run time. This is a tracked gap
(aeb consumer-manifest generation, in flight) — see
[`asks/aeb-generate-consumer-manifest-and-override-dep.md`](../asks/aeb-generate-consumer-manifest-and-override-dep.md).
Until that lands, consume Gleam through aeb, or put the `selenium_nif` app on
`ERL_LIBS` yourself.

## Layout

```
src/selenium.gleam        the idiomatic Gleam surface (by_* factory, typed Results)
src/selenium_ffi.erl      a tiny Erlang shim (getenv/1) for SEL_CHROME_BINARY
test/selenium_test.gleam  FFI + live-surface test over the shared NIF
gleam.toml                the Gleam manifest (deps: gleam_stdlib only — see the status note)
.tests.ae                 aeb node → deps erlang/.build.ae, wires ERL_LIBS, runs gleam test
```

Gleam adds no engine — see [`erlang/README.md`](../erlang/README.md) for the NIF
and how the engine is bundled.
