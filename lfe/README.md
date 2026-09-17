# selenium (LFE) — Lisp Flavoured Erlang over the Erlang NIF

Selenium WebDriver for LFE — a `selenium_lfe` module over the shared BEAM NIF,
results as `#(ok value)` / `#(error #(code message))`.

LFE adds **no engine of its own** — and no second NIF. The engine is one pure,
reentrant shared library — a single .so/.dylib/.dll … NOT an installation, a
service, or a framework: no installer, no daemon, no config, no special
directories. LFE reaches it **through the host artifact — the Erlang NIF**
(`selenium_nif`, the one BEAM binding to the engine), so the whole engine story —
building the NIF, how the `.so` travels, `ERL_LIBS`, `SELENIUM_CORE_LIB` — lives
in [`erlang/README.md`](../erlang/README.md). Erlang owns the shared NIF for the
whole BEAM family (Erlang/Elixir/Gleam/LFE all load the SAME compiled
`selenium_nif`); an LFE-specific NIF would only be a second copy of the C ABI to
drift.

## Using it (LFE app developer)

With the `selenium_nif` app on `ERL_LIBS` (and its `ebin` on the code path), call
the `selenium_lfe` module. Note remote calls use the **underscored** export names
(`selenium_lfe:headless_chrome`, `by_id`, `find_element`, `element_text`) — a
remote call to a hyphenated name would not resolve to the exported atom:

```lfe
(let* ((`#(ok ,d)     (selenium_lfe:headless_chrome #"http://127.0.0.1:9515"))
       (`#(ok ,_)     (selenium_lfe:get d #"https://example.com"))
       (`#(ok ,title) (selenium_lfe:title d))
       (`#(ok ,el)    (selenium_lfe:find_element d (selenium_lfe:by_id #"main")))
       (`#(ok ,text)  (selenium_lfe:element_text d el)))
  (lfe_io:format "~s~n" (list title))
  (lfe_io:format "~s~n" (list text))
  (selenium_lfe:quit d))
```

Locators come from the `by_*` factory (`by_id`, `by_css`, `by_class_name`,
`by_xpath`, …) — each returns a `#(strategy value)` tuple — and `find_element/2`
returns an opaque element-id handle you pass to `element_text/2`, `click/2`, and
the rest. Command params are Erlang maps; results are decoded JSON. Strings are
binaries. A session is an opaque handle.

## Layout

```
src/selenium_lfe.lfe     the idiomatic selenium_lfe WebDriver surface (by_* factory, #(ok …) tuples)
test/ffi_test.lfe        no-browser FFI facts over the shared NIF
test/surface_test.lfe    surface facts (shadow finders, firefox factory exported)
test/live_test.lfe       live-Chrome + Firefox smoke
.tests.ae                aeb node → deps erlang/.build.ae, wires ERL_LIBS + -pa, runs each suite
```

LFE adds no engine — see [`erlang/README.md`](../erlang/README.md) for the NIF
and how the engine is bundled.
