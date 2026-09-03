defmodule Selenium do
  @moduledoc """
  Selenium WebDriver for Elixir, re-glued to the shared pure-Aether WebDriver
  core. Carries NO protocol logic — the W3C command map, routing, By
  normalization, error decode and HTTP round-trip all live in the Aether engine,
  reached over the BEAM through the shared C NIF `:selenium_nif` (owned by the
  Erlang binding; Erlang/Elixir/Gleam load the SAME compiled NIF).

  Command params are Elixir maps/lists; results are decoded JSON (maps with
  string keys, lists, binaries, numbers, booleans, `nil`). A session is an
  opaque integer handle. Commands return `{:ok, value}` or `{:error, {code,
  message}}`.

  NOTE: authored on a box without Elixir; verified on a box with Elixir +
  Erlang/BEAM (catchyos). The Erlang NIF underneath is fully live-verified, and
  the JSON codec here is exercised by the Elixir test suite there.
  """

  alias Selenium.Native

  @w3c_key "element-6066-11e4-a52e-4f735466cecf"

  # ---- session lifecycle ----

  @doc "Start a Chrome session against a running chromedriver (or Grid)."
  def chrome(command_executor, options \\ %{}) do
    caps = Map.merge(%{"browserName" => "chrome"}, options)
    new(command_executor, caps)
  end

  @doc """
  Convenience: a headless Chrome session with the standard launch args.

  Honors `SEL_CHROME_BINARY` when set (a box with no system Chrome but a cached
  Chrome-for-Testing), pointing `goog:chromeOptions.binary` at it.
  """
  def headless_chrome(command_executor) do
    chrome_opts = %{
      "args" => ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
    }

    chrome_opts =
      case System.get_env("SEL_CHROME_BINARY") do
        bin when is_binary(bin) and bin != "" -> Map.put(chrome_opts, "binary", bin)
        _ -> chrome_opts
      end

    chrome(command_executor, %{"goog:chromeOptions" => chrome_opts})
  end

  defp new(command_executor, caps) do
    handle = Native.open(to_string(command_executor))

    case handle do
      0 ->
        {:error, {-1, "failed to open session handle"}}

      _ ->
        payload = %{"capabilities" => %{"alwaysMatch" => caps}}

        case execute(handle, "newSession", payload) do
          {:ok, value} ->
            # Register the negotiated webSocketUrl so `bidi_*` works on demand.
            bidi_register(handle, ws_url_of(value))
            {:ok, handle}

          err ->
            Native.close(handle) && err
        end
    end
  end

  # ---- the FFI seam ----

  @doc "Execute a command by name with a params map. Returns {:ok, value} | {:error, {code, msg}}."
  def execute(handle, command, params \\ %{}) do
    rc = Native.execute(handle, to_string(command), encode(params))

    case rc do
      0 ->
        case Native.last_value(handle) do
          "" -> {:ok, nil}
          raw -> {:ok, decode(raw)}
        end

      _ ->
        code = Native.last_error_code(handle)
        msg = Native.last_error(handle)
        {:error, {code, msg}}
    end
  end

  # ---- navigation ----
  def get(h, url), do: execute(h, "get", %{"url" => to_string(url)})
  def title(h), do: execute(h, "getTitle")
  def current_url(h), do: execute(h, "getCurrentUrl")
  def page_source(h), do: execute(h, "getPageSource")
  def back(h), do: execute(h, "goBack")
  def forward(h), do: execute(h, "goForward")
  def refresh(h), do: execute(h, "refresh")

  # ---- elements ----

  @doc """
  Find one element. Selenium-style: pass a `Selenium.By` locator (a `{strategy,
  value}` tuple), e.g. `find_element(d, Selenium.By.id("hdr"))` or the literal
  `find_element(d, {:id, "hdr"})`. The 3-arg `find_element/3` stays (additive).
  """
  def find_element(h, {strategy, value}), do: find_element(h, strategy, value)

  def find_element(h, by, value) do
    case execute(h, "findElement", decode_by(by, value)) do
      {:ok, m} -> {:ok, Map.fetch!(m, @w3c_key)}
      err -> err
    end
  end

  def find_elements(h, {strategy, value}), do: find_elements(h, strategy, value)

  def find_elements(h, by, value) do
    case execute(h, "findElements", decode_by(by, value)) do
      {:ok, list} -> {:ok, Enum.map(list, &Map.fetch!(&1, @w3c_key))}
      err -> err
    end
  end

  def click(h, element_id), do: execute(h, "clickElement", %{"id" => element_id})

  def send_keys(h, element_id, text) do
    execute(h, "sendKeysToElement", %{
      "id" => element_id,
      "text" => to_string(text),
      "value" => String.graphemes(to_string(text))
    })
  end

  def element_text(h, element_id), do: execute(h, "getElementText", %{"id" => element_id})
  def tag_name(h, element_id), do: execute(h, "getElementTagName", %{"id" => element_id})
  def element_rect(h, element_id), do: execute(h, "getElementRect", %{"id" => element_id})

  def element_property(h, element_id, name),
    do: execute(h, "getElementProperty", %{"id" => element_id, "name" => to_string(name)})

  # ---- script ----
  def execute_script(h, script, args \\ []),
    do: execute(h, "executeScript", %{"script" => to_string(script), "args" => args})

  # ---- windows ----
  def window_handles(h), do: execute(h, "getWindowHandles")
  def current_window_handle(h), do: execute(h, "getCurrentWindowHandle")
  def set_window_rect(h, rect), do: execute(h, "setWindowRect", rect)
  def get_window_rect(h), do: execute(h, "getWindowRect")

  # ---- cookies ----
  def add_cookie(h, cookie), do: execute(h, "addCookie", %{"cookie" => cookie})
  def cookies(h), do: execute(h, "getCookies")
  def cookie(h, name), do: execute(h, "getCookie", %{"name" => to_string(name)})
  def delete_cookie(h, name), do: execute(h, "deleteCookie", %{"name" => to_string(name)})
  def delete_all_cookies(h), do: execute(h, "deleteAllCookies")

  # ---- actions ----
  def perform_actions(h, actions), do: execute(h, "actions", %{"actions" => actions})
  def clear_actions(h), do: execute(h, "clearActions")

  # ---- timeouts / screenshots ----
  def set_timeouts(h, timeouts), do: execute(h, "setTimeout", timeouts)
  def screenshot(h), do: execute(h, "screenshot")

  # ---- lifecycle ----
  def session_id(h), do: Native.session_id(h)

  def quit(h) do
    r = execute(h, "quit")
    Native.close(h)
    r
  end

  # ---- pure engine helpers ----
  def route(command), do: Native.route(to_string(command))
  def error_code(w3c_error), do: Native.error_code(to_string(w3c_error))
  def locator(by, value), do: Native.by_locator(to_string(by), to_string(value))

  # ---- WebDriver-BiDi ----
  # The NIF exposes the raw demux primitives; the orchestration (id-correlated
  # send→pump→poll_reply await loop, lazy ws open, event drain) lives here,
  # mirroring erlang/src/selenium.erl. Per-session BiDi state {ws_url, bidi
  # handle, next_id} is kept in a public ETS table keyed by the session handle.

  @bidi_table :selenium_elixir_bidi

  @doc "True if this session negotiated a webSocketUrl (BiDi usable)."
  def bidi_available(h) do
    case bidi_lookup(h) do
      {:ok, ws_url, _bh, _id} -> ws_url != ""
      :error -> false
    end
  end

  @doc "session.subscribe to one or more event names; wait for the ack."
  def bidi_subscribe(h, events, timeout_ms \\ 10_000) do
    with_bidi(h, fn bh ->
      id = bidi_next_id(h)
      {:ok, ack(Native.bidi_subscribe(bh, id, join_events(events), timeout_ms))}
    end)
  end

  @doc "Block until an event whose method matches arrives, or timeout. {:ok, event} | {:ok, :timeout}."
  def bidi_next_event(h, method, timeout_ms \\ 5_000) do
    with_bidi(h, fn bh ->
      case Native.bidi_wait_event(bh, to_string(method), timeout_ms) do
        "" -> {:ok, :timeout}
        raw -> {:ok, decode(raw)}
      end
    end)
  end

  @doc "Issue any BiDi command; send + pump-poll until this id's reply arrives."
  def bidi_command(h, method, params \\ %{}, timeout_ms \\ 10_000) do
    with_bidi(h, fn bh ->
      id = bidi_next_id(h)

      case Native.bidi_send(bh, id, to_string(method), encode(params)) do
        0 -> bidi_await_reply(bh, id, timeout_ms, 50, 0, method)
        _ -> {:error, {-1, "BiDi send failed: #{method}"}}
      end
    end)
  end

  @doc "The top-level browsing context id, or nil."
  def bidi_top_context(h, timeout_ms \\ 10_000) do
    case bidi_command(h, "browsingContext.getTree", %{}, timeout_ms) do
      {:ok, %{"contexts" => [%{"context" => ctx} | _]}} -> ctx
      _ -> nil
    end
  end

  @doc "script.evaluate in the top context, returning the raw value (awaits promises)."
  def bidi_evaluate_value(h, expr, timeout_ms \\ 30_000) do
    ctx = bidi_top_context(h, timeout_ms)

    params = %{
      "expression" => to_string(expr),
      "target" => %{"context" => ctx},
      "awaitPromise" => true
    }

    case bidi_command(h, "script.evaluate", params, timeout_ms) do
      {:ok, %{"result" => %{"value" => v}}} -> {:ok, v}
      {:ok, other} -> {:ok, other}
      err -> err
    end
  end

  defp bidi_await_reply(_bh, _id, timeout_ms, _step, waited, method) when waited >= timeout_ms,
    do: {:error, {24, "BiDi command timed out: #{method}"}}

  defp bidi_await_reply(bh, id, timeout_ms, step, waited, method) do
    case Native.bidi_poll_reply(bh, id) do
      "" ->
        case Native.bidi_pump(bh, step) do
          rc when rc < 0 -> {:error, {-1, "BiDi channel closed"}}
          _ -> bidi_await_reply(bh, id, timeout_ms, step, waited + step, method)
        end

      raw ->
        {:ok, decode(raw)}
    end
  end

  # --- BiDi session state (ETS) ---

  defp bidi_table do
    case :ets.info(@bidi_table, :name) do
      :undefined ->
        try do
          :ets.new(@bidi_table, [:named_table, :public, :set])
        rescue
          ArgumentError -> @bidi_table
        end

      _ ->
        @bidi_table
    end
  end

  defp bidi_register(handle, ws_url) do
    :ets.insert(bidi_table(), {handle, ws_url, :undefined, 1})
  end

  defp bidi_lookup(handle) do
    case :ets.info(@bidi_table, :name) do
      :undefined ->
        :error

      _ ->
        case :ets.lookup(@bidi_table, handle) do
          [{^handle, ws_url, bh, next_id}] -> {:ok, ws_url, bh, next_id}
          [] -> :error
        end
    end
  end

  defp bidi_next_id(handle), do: :ets.update_counter(@bidi_table, handle, {4, 1}) - 1

  # Lazily open the ws channel on first use; return the BiDi handle.
  defp bidi_channel(handle) do
    case bidi_lookup(handle) do
      {:ok, "", _, _} ->
        {:error, {0, "BiDi not available: no webSocketUrl negotiated"}}

      {:ok, _ws, bh, _id} when bh != :undefined ->
        {:ok, bh}

      {:ok, ws_url, :undefined, _id} ->
        case Native.bidi_open(ws_url) do
          0 ->
            {:error, {-1, "BiDi channel failed to open"}}

          bh ->
            :ets.update_element(@bidi_table, handle, {3, bh})
            {:ok, bh}
        end

      :error ->
        {:error, {0, "BiDi not available: unknown session handle"}}
    end
  end

  defp with_bidi(handle, fun) do
    case bidi_channel(handle) do
      {:ok, bh} -> fun.(bh)
      {:error, _} = err -> err
    end
  end

  defp join_events(events) when is_list(events), do: Enum.map_join(events, ",", &to_string/1)
  defp join_events(event), do: to_string(event)

  defp ack(""), do: %{}
  defp ack(raw), do: decode(raw)

  defp ws_url_of(%{"capabilities" => %{"webSocketUrl" => url}}) when is_binary(url), do: url
  defp ws_url_of(_), do: ""

  defp decode_by(by, value),
    do: decode(Native.by_locator(strategy_string(by), to_string(value)))

  # Normalize convenience atom strategies to the engine's strategy strings.
  # :class_name maps to the W3C "class name" (matching every Selenium binding).
  defp strategy_string(:class_name), do: "class name"
  defp strategy_string(:css), do: "css selector"
  defp strategy_string(:css_selector), do: "css selector"
  defp strategy_string(:tag_name), do: "tag name"
  defp strategy_string(:link_text), do: "link text"
  defp strategy_string(:partial_link_text), do: "partial link text"
  defp strategy_string(by), do: to_string(by)

  # ==== minimal JSON (maps with string keys <-> JSON), dependency-free ====

  defp encode(v), do: IO.iodata_to_binary(enc(v))

  defp enc(nil), do: "null"
  defp enc(true), do: "true"
  defp enc(false), do: "false"
  defp enc(v) when is_integer(v), do: Integer.to_string(v)
  defp enc(v) when is_float(v), do: Float.to_string(v)
  defp enc(v) when is_binary(v), do: [?", esc(v), ?"]
  defp enc(v) when is_atom(v), do: [?", esc(Atom.to_string(v)), ?"]

  defp enc(v) when is_map(v) do
    pairs = Enum.map(v, fn {k, val} -> [?", esc(to_string(k)), ?", ?:, enc(val)] end)
    [?{, Enum.intersperse(pairs, ?,), ?}]
  end

  defp enc(v) when is_list(v) do
    [?[, Enum.intersperse(Enum.map(v, &enc/1), ?,), ?]]
  end

  defp esc(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp decode(bin) do
    {v, rest} = dec(skip_ws(bin))
    "" = skip_ws(rest)
    v
  end

  defp skip_ws(<<c, r::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_ws(r)
  defp skip_ws(b), do: b

  defp dec("null" <> r), do: {nil, r}
  defp dec("true" <> r), do: {true, r}
  defp dec("false" <> r), do: {false, r}
  defp dec(<<?", r::binary>>), do: dec_str(r, [])
  defp dec(<<?{, r::binary>>), do: dec_obj(skip_ws(r), %{})
  defp dec(<<?[, r::binary>>), do: dec_arr(skip_ws(r), [])
  defp dec(b), do: dec_num(b, [])

  defp dec_str(<<?", r::binary>>, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), r}

  defp dec_str(<<?\\, c, r::binary>>, acc) do
    case c do
      ?u ->
        <<hex::binary-size(4), rest::binary>> = r
        cp = String.to_integer(hex, 16)
        dec_str(rest, [<<cp::utf8>> | acc])

      _ ->
        ch =
          case c do
            ?" -> ?"
            ?\\ -> ?\\
            ?/ -> ?/
            ?n -> ?\n
            ?r -> ?\r
            ?t -> ?\t
            ?b -> ?\b
            ?f -> ?\f
            other -> other
          end

        dec_str(r, [ch | acc])
    end
  end

  defp dec_str(<<c::utf8, r::binary>>, acc), do: dec_str(r, [<<c::utf8>> | acc])

  defp dec_obj(<<?}, r::binary>>, m), do: {m, r}

  defp dec_obj(b, m) do
    <<?", r0::binary>> = skip_ws(b)
    {key, r1} = dec_str(r0, [])
    <<?:, r2::binary>> = skip_ws(r1)
    {val, r3} = dec(skip_ws(r2))
    m2 = Map.put(m, key, val)

    case skip_ws(r3) do
      <<?,, r4::binary>> -> dec_obj(skip_ws(r4), m2)
      <<?}, r4::binary>> -> {m2, r4}
    end
  end

  defp dec_arr(<<?], r::binary>>, l), do: {Enum.reverse(l), r}

  defp dec_arr(b, l) do
    {v, r1} = dec(skip_ws(b))

    case skip_ws(r1) do
      <<?,, r2::binary>> -> dec_arr(skip_ws(r2), [v | l])
      <<?], r2::binary>> -> {Enum.reverse([v | l]), r2}
    end
  end

  defp dec_num(<<c, r::binary>>, acc)
       when c in ?0..?9 or c in [?-, ?+, ?., ?e, ?E],
       do: dec_num(r, [c | acc])

  defp dec_num(b, acc) do
    s = IO.iodata_to_binary(Enum.reverse(acc))

    n =
      if String.contains?(s, [".", "e", "E"]) do
        String.to_float(s)
      else
        String.to_integer(s)
      end

    {n, b}
  end
end
