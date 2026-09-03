defmodule Selenium.Native do
  @moduledoc """
  Raw NIF surface over the Aether Selenium core's C ABI (the `aether_sel_embed_*`
  symbols from `core/embed.ae`, linked from `libselenium_core.so`).

  ## One shared NIF for the whole BEAM family

  Elixir does **not** compile its own copy of the C NIF. The canonical NIF is
  built once by the **Erlang** binding as the OTP app `selenium_nif` (Erlang is
  the BEAM's lingua franca, so it owns the shared binding — exactly as the one
  Java jar backs the Kotlin/Scala/Clojure/Groovy bindings). This module
  `defdelegate`s onto that shared `:selenium_nif` module, which loads
  `priv/selenium_nif.so` over the BEAM. In the monorepo the `selenium_nif` app
  is put on the code path via `ERL_LIBS` (pointed at `erlang/_build`); as a
  published package it would be a Hex dependency.

  The opaque session handle is a 64-bit integer (`uintptr_t`); `0` from `open`
  means failure. String results are binaries; the NIF frees the native pointer.
  """

  @compile {:no_warn_undefined, :selenium_nif}

  defdelegate open(base_url), to: :selenium_nif
  defdelegate close(handle), to: :selenium_nif
  defdelegate execute(handle, name, params_json), to: :selenium_nif
  defdelegate last_value(handle), to: :selenium_nif
  defdelegate last_status(handle), to: :selenium_nif
  defdelegate last_error_code(handle), to: :selenium_nif
  defdelegate last_error(handle), to: :selenium_nif
  defdelegate session_id(handle), to: :selenium_nif
  defdelegate by_locator(strategy, value), to: :selenium_nif
  defdelegate route(name), to: :selenium_nif
  defdelegate error_code(w3c_error), to: :selenium_nif

  # ---- WebDriver-BiDi (the raw demux primitives; orchestration in Selenium) ----
  defdelegate bidi_open(ws_url), to: :selenium_nif
  defdelegate bidi_close(bidi_handle), to: :selenium_nif
  defdelegate bidi_send(bidi_handle, id, method, params_json), to: :selenium_nif
  defdelegate bidi_pump(bidi_handle, timeout_ms), to: :selenium_nif
  defdelegate bidi_poll_reply(bidi_handle, id), to: :selenium_nif
  defdelegate bidi_wait_event(bidi_handle, method, timeout_ms), to: :selenium_nif
  defdelegate bidi_subscribe(bidi_handle, id, events_csv, timeout_ms), to: :selenium_nif
  defdelegate bidi_unsubscribe(bidi_handle, id, events_csv, timeout_ms), to: :selenium_nif
  defdelegate bidi_lost_events(bidi_handle), to: :selenium_nif
end
