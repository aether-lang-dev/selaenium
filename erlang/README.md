# selenium_nif (Erlang) — the BEAM engine NIF

Selenium WebDriver for Erlang — a thin NIF over the shared pure-Aether WebDriver
engine (`libselenium_core`), plus an idiomatic `selenium` module.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` the NIF `dlopen`s (N independent sessions per process). It
is **not** an installation, a service, or a framework: no installer, no daemon,
no config, no special directories. The Erlang side carries no protocol logic —
the W3C command map, routing, `By` normalization, error decode and the HTTP round
trip all live in that one library.

This OTP app — `selenium_nif` (the C NIF `priv/selenium_nif.so` + the `selenium`
/ `by` / `keys` modules) — is the **engine host for the whole BEAM family**:
Elixir and Gleam consume this same NIF via `ERL_LIBS` (they add no second NIF; see
their READMEs).

## Using it (Erlang app developer)

Depend on the `selenium_nif` OTP app (in your rebar/mix deps or on `ERL_LIBS`),
then:

```erlang
D = selenium:headless_chrome(<<"http://127.0.0.1:9515">>),
{ok, _}   = selenium:get(D, <<"https://example.com">>),
{ok, Title} = selenium:title(D),
{ok, El}  = selenium:find_element(D, by:id(<<"main">>)),
{ok, Text} = selenium:element_text(D, El),
selenium:quit(D).
```

Strings are Erlang binaries. The engine is a single shared library the NIF
`dlopen`s — nothing to install, compile, or configure at consume time. The NIF
resolves `priv/selenium_nif.so` via `SELENIUM_NIF_DIR` → the OTP app's `priv_dir`
(the normal `ERL_LIBS` path) → a loose `./priv`; that NIF in turn loads
`libselenium_core` (set `SELENIUM_CORE_LIB` to pin the engine).

## Building the NIF (platform / DevOps)

The NIF `.so` links the engine at build time, so building it needs the engine
`.so` present. The team that owns the Aether tooling builds the OTP app once:

```sh
aeb erlang/.build.ae            # builds priv/selenium_nif.so (links libselenium_core)
```

This produces `_build/selenium_nif/{ebin,priv}` and publishes the `erl_libs` edge
the Elixir and Gleam bindings consume. Grab the prebuilt engine before building
with `scripts/fetch-engine.sh` (or set `SELENIUM_CORE_LIB`); see
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md).

## Layout

```
c_src/selenium_nif.c    the NIF: dlopen's the engine, binds the aether_sel_embed_* ABI
src/selenium_nif.erl    the NIF loader (resolves priv/selenium_nif.so)
src/selenium.erl        the idiomatic selenium:* WebDriver surface
src/by.erl              the by:id/… locator factory
src/keys.erl            the Keys constant map
src/selenium_nif.app    the OTP app manifest (shared with Elixir + Gleam via ERL_LIBS)
.build.ae               aeb node → builds the OTP app (NIF + modules)
.tests.ae               aeb node → the binding test suite
```
