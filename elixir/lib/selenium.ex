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
  Start a Chrome session over HTTPS with explicit TLS trust. `tls` is a map:
  `%{ca_path: "/path/to/ca.pem"}` trusts a private-CA bundle; `%{insecure:
  true}` skips verification entirely (self-signed dev/staging Grid — trust the
  host out-of-band). Both land on the handle BEFORE newSession.
  """
  def chrome_tls(command_executor, options \\ %{}, tls \\ %{}) do
    caps = Map.merge(%{"browserName" => "chrome"}, options)
    new(command_executor, caps, tls)
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

  defp new(command_executor, caps, tls \\ %{}) do
    handle = Native.open(to_string(command_executor))

    case handle do
      0 ->
        {:error, {-1, "failed to open session handle"}}

      _ ->
        apply_tls(handle, tls)
        # Request a BiDi channel so bidi_* works on demand; the remote end
        # returns value.capabilities.webSocketUrl (mirrors erlang/src/selenium.erl).
        bidi_caps = Map.put(caps, "webSocketUrl", true)
        payload = %{"capabilities" => %{"alwaysMatch" => bidi_caps}}

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

  defp apply_tls(handle, tls) do
    case Map.get(tls, :ca_path) || Map.get(tls, "ca_path") do
      p when is_binary(p) and p != "" -> Native.set_ca(handle, p)
      _ -> :ok
    end

    case Map.get(tls, :insecure) || Map.get(tls, "insecure") do
      true -> Native.set_insecure(handle, 1)
      _ -> :ok
    end
  end

  # ---- self-managed driver (no chromedriver on PATH, no Grid) ----

  @doc "Resolve the driver binary for `browser` (engine auto-download/cache). Returns the path binary."
  def resolve_driver(browser, hint \\ ""),
    do: Native.resolve_driver(to_string(browser), to_string(hint))

  @doc "Launch `driver_path` as a child process. Returns {:ok, driver_handle} | {:error, _}."
  def launch_driver(driver_path, timeout_ms \\ 15_000) do
    case Native.launch_driver(to_string(driver_path), timeout_ms) do
      0 -> {:error, {-1, "driver launch failed"}}
      dh -> {:ok, dh}
    end
  end

  @doc "Resolve + launch the driver for `browser` in one step. Returns {:ok, driver_handle} | {:error, _}."
  def ensure_driver(browser \\ "chrome", hint \\ "", timeout_ms \\ 15_000) do
    case Native.ensure_driver(to_string(browser), to_string(hint), timeout_ms) do
      0 -> {:error, {-1, "driver ensure failed"}}
      dh -> {:ok, dh}
    end
  end

  @doc "The base URL a launched driver is listening on."
  def driver_url(driver_handle), do: Native.driver_url(driver_handle)

  @doc "The OS process id of a launched driver."
  def driver_pid(driver_handle), do: Native.driver_pid(driver_handle)

  @doc "Terminate a launched driver process."
  def stop_driver(driver_handle) do
    Native.stop_driver(driver_handle)
    :ok
  end

  @doc """
  A Chrome session that spawns its OWN chromedriver via the engine — no driver
  on PATH, no Grid. Returns `{:ok, handle, driver_handle}`; the caller quits the
  session (`quit/1`) and stops the driver (`stop_driver/1`). `options` is the
  caps map.
  """
  def local_chrome(options \\ %{}) do
    case ensure_driver("chrome", "", 15_000) do
      {:ok, dh} ->
        case chrome(driver_url(dh), options) do
          {:ok, handle} -> {:ok, handle, dh}
          err -> stop_driver(dh) && err
        end

      err ->
        err
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

  # Decode a return-code from an engine ATOM call (is_displayed/get_attribute/
  # find_relative) into {:ok, value} | {:error, {code, msg}}, same convention as
  # execute/3 but reading the atom's last_value.
  defp atom_result(handle, rc) do
    case rc do
      0 ->
        case Native.last_value(handle) do
          "" -> {:ok, nil}
          raw -> {:ok, decode(raw)}
        end

      _ ->
        {:error, {Native.last_error_code(handle), Native.last_error(handle)}}
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

  @doc """
  Find one descendant of `element_id` matching a `Selenium.By` locator or a
  `{strategy, value}` tuple (element-scoped `findChildElement`).
  """
  def find_child_element(h, element_id, {strategy, value}),
    do: find_child_element(h, element_id, strategy, value)

  def find_child_element(h, element_id, by, value) do
    params = Map.put(decode_by(by, value), "id", element_id)

    case execute(h, "findChildElement", params) do
      {:ok, m} -> {:ok, Map.fetch!(m, @w3c_key)}
      err -> err
    end
  end

  @doc "Find all descendants of `element_id` matching the locator (element-scoped `findChildElements`)."
  def find_child_elements(h, element_id, {strategy, value}),
    do: find_child_elements(h, element_id, strategy, value)

  def find_child_elements(h, element_id, by, value) do
    params = Map.put(decode_by(by, value), "id", element_id)

    case execute(h, "findChildElements", params) do
      {:ok, list} -> {:ok, Enum.map(list, &Map.fetch!(&1, @w3c_key))}
      err -> err
    end
  end

  @doc """
  Relative locators (`find_relative`): the ids of elements matching `base_css`,
  filtered/ordered by W3C relative filters (above/below/near/toLeftOf/toRightOf).
  Returns `{:ok, [element_id]}`.
  """
  def find_relative(h, base_css, filters) do
    case atom_result(h, Native.find_relative(h, to_string(base_css), encode(filters))) do
      {:ok, nil} -> {:ok, []}
      {:ok, refs} when is_list(refs) -> {:ok, Enum.map(refs, &Map.fetch!(&1, @w3c_key))}
      err -> err
    end
  end

  @doc "Count of elements matching `base_css` under the relative `filters`."
  def find_relative_count(h, base_css, filters) do
    case find_relative(h, base_css, filters) do
      {:ok, ids} -> {:ok, length(ids)}
      err -> err
    end
  end

  @doc "The active (focused) element id (`getActiveElement`)."
  def active_element(h) do
    case execute(h, "getActiveElement") do
      {:ok, m} -> {:ok, Map.fetch!(m, @w3c_key)}
      err -> err
    end
  end

  def click(h, element_id), do: execute(h, "clickElement", %{"id" => element_id})
  def clear(h, element_id), do: execute(h, "clearElement", %{"id" => element_id})

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

  @doc "Alias of `element_property/3` matching the classic `get_property` name."
  def get_property(h, element_id, name), do: element_property(h, element_id, name)

  @doc "The literal DOM attribute (W3C `getDomAttribute`), no property fallback."
  def dom_attribute(h, element_id, name),
    do: execute(h, "getDomAttribute", %{"id" => element_id, "name" => to_string(name)})

  @doc "Whether the element is enabled (`isElementEnabled`)."
  def is_enabled(h, element_id) do
    case execute(h, "isElementEnabled", %{"id" => element_id}) do
      {:ok, v} -> {:ok, v == true}
      err -> err
    end
  end

  @doc "Whether the element is selected/checked (`isElementSelected`)."
  def is_selected(h, element_id) do
    case execute(h, "isElementSelected", %{"id" => element_id}) do
      {:ok, v} -> {:ok, v == true}
      err -> err
    end
  end

  @doc "The computed value of a CSS property (`getElementValueOfCssProperty`)."
  def css_value(h, element_id, prop),
    do:
      execute(h, "getElementValueOfCssProperty", %{"id" => element_id, "name" => to_string(prop)})

  @doc "Classic-Selenium-named alias of `css_value/3`."
  def value_of_css_property(h, element_id, prop), do: css_value(h, element_id, prop)

  @doc "A base64 PNG screenshot of just this element (`takeElementScreenshot`)."
  def element_screenshot(h, element_id),
    do: execute(h, "takeElementScreenshot", %{"id" => element_id})

  @doc """
  Whether the element is shown — the isDisplayed atom (the real visibility
  algorithm, run in-page by the engine), not a naive style check.
  """
  def is_displayed(h, element_id) do
    case atom_result(h, Native.is_displayed(h, to_string(element_id))) do
      {:ok, v} -> {:ok, v == true}
      err -> err
    end
  end

  @doc """
  The classic `getAttribute(name)`: property-or-attribute via the shared engine
  atom. Returns `{:ok, nil}` when the attribute is absent.
  """
  def get_attribute(h, element_id, name) do
    atom_result(h, Native.get_attribute(h, to_string(element_id), to_string(name)))
  end

  @doc """
  Submit the form the element belongs to. W3C removed the `submit` endpoint, so
  — like the reference binding — this walks up to the enclosing `<form>` and
  calls `requestSubmit()` (falling back to `submit()`) via an injected script.
  """
  def submit(h, element_id) do
    script =
      "var e=arguments[0];var f=e.form||e.closest('form');" <>
        "if(!f){throw new Error('Element is not within a form');}" <>
        "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"

    execute_script(h, script, [%{@w3c_key => element_id}])
  end

  # ---- script ----
  def execute_script(h, script, args \\ []),
    do: execute(h, "executeScript", %{"script" => to_string(script), "args" => args})

  @doc "Run an async script; the page signals completion via the injected callback."
  def execute_async_script(h, script, args \\ []),
    do: execute(h, "executeAsyncScript", %{"script" => to_string(script), "args" => args})

  # ---- windows ----
  def window_handles(h), do: execute(h, "getWindowHandles")
  def current_window_handle(h), do: execute(h, "getCurrentWindowHandle")
  def set_window_rect(h, rect), do: execute(h, "setWindowRect", rect)
  def get_window_rect(h), do: execute(h, "getWindowRect")

  @doc "Switch the session's top-level browsing context to window `handle`."
  def switch_to_window(h, handle),
    do: execute(h, "switchToWindow", %{"handle" => to_string(handle)})

  @doc "Maximize the current window. Returns the resulting rect."
  def maximize_window(h), do: execute(h, "maximizeWindow")

  @doc "Minimize (hide) the current window. Returns the resulting rect."
  def minimize_window(h), do: execute(h, "minimizeWindow")

  @doc "Put the current window into fullscreen. Returns the resulting rect."
  def fullscreen_window(h), do: execute(h, "fullscreenWindow")

  @doc """
  Open a new top-level browsing context (`newWindow`). `type_hint` is `"tab"` or
  `"window"`. Returns `{:ok, handle}` — pass it to `switch_to_window/2`.
  """
  def new_window(h, type_hint \\ "tab") do
    case execute(h, "newWindow", %{"type" => to_string(type_hint)}) do
      {:ok, %{"handle" => handle}} -> {:ok, handle}
      {:ok, _} -> {:ok, ""}
      err -> err
    end
  end

  @doc """
  Close the current window/tab (`close`). Returns `{:ok, remaining_handles}`;
  when it empties the session is gone. Does NOT end the session (use `quit/1`).
  """
  def close_window(h) do
    case execute(h, "close") do
      {:ok, handles} when is_list(handles) -> {:ok, handles}
      {:ok, _} -> {:ok, []}
      err -> err
    end
  end

  # ---- frames ----

  @doc """
  Switch focus to a frame (`switchToFrame`): a 0-based integer index, an element
  id string (the `<iframe>` element), or `:default`/`nil` for the top-level
  context. Subsequent element commands run inside the chosen frame.
  """
  def switch_to_frame(h, index) when is_integer(index),
    do: execute(h, "switchToFrame", %{"id" => index})

  def switch_to_frame(h, frame) when frame in [:default, nil],
    do: execute(h, "switchToFrame", %{"id" => nil})

  def switch_to_frame(h, element_id) when is_binary(element_id),
    do: execute(h, "switchToFrame", %{"id" => %{@w3c_key => element_id}})

  @doc "Switch to the parent of the current frame (one level out)."
  def switch_to_parent_frame(h), do: execute(h, "switchToFrameParent")

  @doc "Return focus to the top-level browsing context."
  def switch_to_default_content(h), do: switch_to_frame(h, :default)

  # ---- cookies ----
  def add_cookie(h, cookie), do: execute(h, "addCookie", %{"cookie" => cookie})
  def cookies(h), do: execute(h, "getCookies")
  def cookie(h, name), do: execute(h, "getCookie", %{"name" => to_string(name)})
  def delete_cookie(h, name), do: execute(h, "deleteCookie", %{"name" => to_string(name)})
  def delete_all_cookies(h), do: execute(h, "deleteAllCookies")
  def get_cookies(h), do: cookies(h)
  def get_cookie(h, name), do: cookie(h, name)

  # ---- alerts ----
  @doc "Accept (OK) the current user-prompt / alert dialog."
  def accept_alert(h), do: execute(h, "acceptAlert")

  @doc "Dismiss (Cancel) the current user-prompt / alert dialog."
  def dismiss_alert(h), do: execute(h, "dismissAlert")

  @doc "The message text of the current dialog."
  def alert_text(h), do: execute(h, "getAlertText")

  @doc "Type `text` into the current prompt dialog's input field."
  def send_alert_text(h, text),
    do:
      execute(h, "setAlertValue", %{
        "text" => to_string(text),
        "value" => String.graphemes(to_string(text))
      })

  @doc """
  True if a dialog is present (probing via `getAlertText`). A clean "no such
  alert" (code 15) resolves to `{:ok, false}`; transport failures propagate.
  """
  def alert_present(h) do
    case execute(h, "getAlertText") do
      {:ok, _} -> {:ok, true}
      {:error, {15, _}} -> {:ok, false}
      err -> err
    end
  end

  # ---- actions ----
  def perform_actions(h, actions), do: execute(h, "actions", %{"actions" => actions})
  def clear_actions(h), do: execute(h, "clearActions")

  # High-level pointer gestures over perform_actions/2, each targeting the
  # "mouse" device and moving to the element centre (origin = element ref) first.
  @doc "Move to the element centre and click through the input-actions device."
  def action_click(h, element_id),
    do: perform_actions(h, [ptr_seq([ptr_move_origin(element_id), ptr_down(0), ptr_up(0)])])

  @doc "Alias of `action_click/2` (hover-then-press-and-hold at the element centre)."
  def click_and_hold(h, element_id),
    do: perform_actions(h, [ptr_seq([ptr_move_origin(element_id), ptr_down(0)])])

  @doc "Release the currently-held pointer button."
  def release(h), do: perform_actions(h, [ptr_seq([ptr_up(0)])])

  @doc "Double-click at the element centre."
  def double_click(h, element_id),
    do:
      perform_actions(h, [
        ptr_seq([ptr_move_origin(element_id), ptr_down(0), ptr_up(0), ptr_down(0), ptr_up(0)])
      ])

  @doc "Right-click (contextmenu) at the element centre."
  def context_click(h, element_id),
    do: perform_actions(h, [ptr_seq([ptr_move_origin(element_id), ptr_down(2), ptr_up(2)])])

  @doc "Hover: move the pointer to the element centre (no button)."
  def move_to_element(h, element_id),
    do: perform_actions(h, [ptr_seq([ptr_move_origin(element_id)])])

  @doc "Drag `source_id` onto `target_id` (press at source, move to target, release)."
  def drag_and_drop(h, source_id, target_id),
    do:
      perform_actions(h, [
        ptr_seq([ptr_move_origin(source_id), ptr_down(0), ptr_move_origin(target_id), ptr_up(0)])
      ])

  defp ptr_seq(actions) do
    %{
      "type" => "pointer",
      "id" => "mouse",
      "parameters" => %{"pointerType" => "mouse"},
      "actions" => actions
    }
  end

  defp ptr_move_origin(element_id) do
    %{
      "type" => "pointerMove",
      "duration" => 0,
      "x" => 0,
      "y" => 0,
      "origin" => %{@w3c_key => element_id}
    }
  end

  defp ptr_down(button), do: %{"type" => "pointerDown", "button" => button}
  defp ptr_up(button), do: %{"type" => "pointerUp", "button" => button}

  # ---- Select (a <select> element helper) ----

  @doc "The `<option>` element ids of a `<select>` (scoped `findChildElements`)."
  def options_of(h, select_id), do: find_child_elements(h, select_id, {:tag_name, "option"})

  @doc "Whether the `<select>` allows multiple selection."
  def is_multiple(h, select_id) do
    case get_attribute(h, select_id, "multiple") do
      {:ok, v} when v in [nil, false] -> {:ok, false}
      {:ok, _} -> {:ok, true}
      err -> err
    end
  end

  @doc "The `<option>` ids currently selected within `select_id`."
  def all_selected_options(h, select_id) do
    with {:ok, opts} <- options_of(h, select_id) do
      {:ok, Enum.filter(opts, fn o -> match?({:ok, true}, is_selected(h, o)) end)}
    end
  end

  @doc "The first selected `<option>` id, or `{:ok, nil}` if none."
  def first_selected_option(h, select_id) do
    with {:ok, sel} <- all_selected_options(h, select_id), do: {:ok, List.first(sel)}
  end

  @doc "Deselect every option of a multi-`<select>` (no-op for single-select already blank)."
  def deselect_all(h, select_id) do
    with {:ok, sel} <- all_selected_options(h, select_id) do
      Enum.reduce_while(sel, {:ok, nil}, fn o, _acc ->
        case click(h, o) do
          {:ok, _} = ok -> {:cont, ok}
          err -> {:halt, err}
        end
      end)
    end
  end

  @doc "Select the `<option>` whose `value` attribute equals `value`."
  def select_by_value(h, select_id, value),
    do: select_option(h, select_id, fn o -> match?({:ok, ^value}, {:ok, opt_value(h, o)}) end)

  @doc "Select the `<option>` whose visible text equals `text`."
  def select_by_visible_text(h, select_id, text),
    do: select_option(h, select_id, fn o -> match?({:ok, ^text}, element_text(h, o)) end)

  @doc "Select the `<option>` at the zero-based `index`."
  def select_by_index(h, select_id, index) when is_integer(index) do
    with {:ok, opts} <- options_of(h, select_id) do
      case Enum.at(opts, index) do
        nil -> {:error, {0, "no such option"}}
        opt -> click_option(h, opt)
      end
    end
  end

  defp opt_value(h, opt) do
    case get_attribute(h, opt, "value") do
      {:ok, v} -> v
      _ -> nil
    end
  end

  defp select_option(h, select_id, pred) do
    with {:ok, opts} <- options_of(h, select_id) do
      case Enum.find(opts, pred) do
        nil -> {:error, {0, "no such option"}}
        opt -> click_option(h, opt)
      end
    end
  end

  defp click_option(h, opt) do
    case is_selected(h, opt) do
      {:ok, true} -> {:ok, opt}
      {:ok, false} -> with({:ok, _} <- click(h, opt), do: {:ok, opt})
      err -> err
    end
  end

  # ---- waits (poll the driver until a predicate holds or timeout) ----

  @doc """
  Poll `fun.(handle)` (a 0/1-arity predicate returning truthy) every `poll_every`
  ms until it holds or `timeout_ms` elapses. Returns `{:ok, value}` (the truthy
  result) or `{:error, {24, ...}}` on timeout.
  """
  def wait_until(h, fun, timeout_ms \\ 10_000, poll_every \\ 200) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_loop(h, fun, deadline, poll_every)
  end

  defp wait_loop(h, fun, deadline, poll_every) do
    case safe_pred(fun, h) do
      result when result not in [nil, false] ->
        {:ok, result}

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {24, "wait timed out"}}
        else
          Process.sleep(poll_every)
          wait_loop(h, fun, deadline, poll_every)
        end
    end
  end

  defp safe_pred(fun, h) when is_function(fun, 1), do: fun.(h)
  defp safe_pred(fun, _h) when is_function(fun, 0), do: fun.()

  @doc "Wait until an element matching the locator is present. Returns `{:ok, element_id}`."
  def wait_for_element(h, by_or_locator, timeout_ms \\ 10_000) do
    wait_until(
      h,
      fn hd ->
        case find_element(hd, by_or_locator) do
          {:ok, id} -> id
          _ -> false
        end
      end,
      timeout_ms
    )
  end

  @doc "Wait until an element matching the locator is displayed. Returns `{:ok, element_id}`."
  def wait_for_visible(h, by_or_locator, timeout_ms \\ 10_000) do
    wait_until(
      h,
      fn hd ->
        with {:ok, id} <- find_element(hd, by_or_locator),
             {:ok, true} <- is_displayed(hd, id) do
          id
        else
          _ -> false
        end
      end,
      timeout_ms
    )
  end

  @doc "Wait until an element matching the locator is displayed AND enabled. Returns `{:ok, element_id}`."
  def wait_for_clickable(h, by_or_locator, timeout_ms \\ 10_000) do
    wait_until(
      h,
      fn hd ->
        with {:ok, id} <- find_element(hd, by_or_locator),
             {:ok, true} <- is_displayed(hd, id),
             {:ok, true} <- is_enabled(hd, id) do
          id
        else
          _ -> false
        end
      end,
      timeout_ms
    )
  end

  @doc "Wait until no element matches the locator (element gone/absent)."
  def wait_until_gone(h, by_or_locator, timeout_ms \\ 10_000) do
    wait_until(
      h,
      fn hd -> match?({:error, {17, _}}, find_element(hd, by_or_locator)) end,
      timeout_ms
    )
  end

  @doc "Wait until the page title contains `substr`."
  def wait_for_title_contains(h, substr, timeout_ms \\ 10_000),
    do: wait_until(h, fn hd -> value_contains(title(hd), substr) end, timeout_ms)

  @doc "Wait until the page title equals `want`."
  def wait_for_title_is(h, want, timeout_ms \\ 10_000),
    do: wait_until(h, fn hd -> match?({:ok, ^want}, title(hd)) end, timeout_ms)

  @doc "Wait until the current URL contains `substr`."
  def wait_for_url_contains(h, substr, timeout_ms \\ 10_000),
    do: wait_until(h, fn hd -> value_contains(current_url(hd), substr) end, timeout_ms)

  @doc "Wait until the current URL equals `want`."
  def wait_for_url_is(h, want, timeout_ms \\ 10_000),
    do: wait_until(h, fn hd -> match?({:ok, ^want}, current_url(hd)) end, timeout_ms)

  @doc "Wait until `element_id`'s text contains `substr`."
  def wait_for_text_contains(h, element_id, substr, timeout_ms \\ 10_000),
    do:
      wait_until(h, fn hd -> value_contains(element_text(hd, element_id), substr) end, timeout_ms)

  defp value_contains({:ok, s}, substr) when is_binary(s), do: String.contains?(s, substr)
  defp value_contains(_, _), do: false

  # ---- timeouts / screenshots ----
  def set_timeouts(h, timeouts), do: execute(h, "setTimeout", timeouts)

  @doc "Set the page-load timeout (ms)."
  def set_page_load_timeout(h, ms), do: execute(h, "setTimeout", %{"pageLoad" => ms})

  @doc "Set the async-script timeout (ms)."
  def set_script_timeout(h, ms), do: execute(h, "setTimeout", %{"script" => ms})

  @doc "Set the implicit wait (ms): how long `find_element` retries before failing."
  def implicitly_wait(h, ms), do: execute(h, "setTimeout", %{"implicit" => ms})

  def screenshot(h), do: execute(h, "screenshot")

  @doc "Alias of `screenshot/1` (base64 PNG), matching the classic `screenshot_base` name."
  def screenshot_base(h), do: screenshot(h)

  @doc """
  Print the current page to PDF (`printPage`), returning a base64 string.
  `options` is the W3C print-options map (page size, margins, orientation,
  scale, `pageRanges`, …); pass `%{}` for defaults.
  """
  def print_pdf(h, options \\ %{}), do: execute(h, "printPage", options)

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
      {:ok, %{"result" => %{"contexts" => [%{"context" => ctx} | _]}}} -> ctx
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
      {:ok, %{"result" => %{"result" => %{"value" => v}}}} -> {:ok, v}
      {:ok, other} -> {:ok, other}
      err -> err
    end
  end

  # ---- WebDriver-BiDi network interception ----
  # Dedicated NIF entry points (own request id per call). `request_id` comes from
  # a network event via `bidi_event_request_id/1`.

  @doc """
  Intercept requests matching `url_pattern` (`""` intercepts all) at `phases`
  (default `"beforeRequestSent"`). Returns `{:ok, intercept_id}`.
  """
  def bidi_add_intercept(h, url_pattern, phases \\ "beforeRequestSent") do
    with_bidi(h, fn bh ->
      reply =
        decode(
          Native.bidi_network_add_intercept(
            bh,
            bidi_next_id(h),
            to_string(phases),
            to_string(url_pattern),
            10_000
          )
        )

      case reply do
        %{"result" => %{"intercept" => ic}} -> {:ok, ic}
        _ -> {:error, {0, "no intercept id"}}
      end
    end)
  end

  @doc "Remove a previously-added network intercept."
  def bidi_remove_intercept(h, intercept_id) do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_remove_intercept(
           bh,
           bidi_next_id(h),
           to_string(intercept_id),
           10_000
         )
       )}
    end)
  end

  @doc "Let a paused request proceed (`network.continueRequest`)."
  def bidi_continue_request(h, request_id) do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_continue_request(bh, bidi_next_id(h), to_string(request_id), 10_000)
       )}
    end)
  end

  @doc "Fail a paused request (`network.failRequest`)."
  def bidi_fail_request(h, request_id) do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_fail_request(bh, bidi_next_id(h), to_string(request_id), 10_000)
       )}
    end)
  end

  @doc """
  Fulfill a paused request with a MOCK response (never hits the network).
  Defaults to status 200, no content-type, empty body.
  """
  def bidi_provide_response(h, request_id, status \\ 200, content_type \\ "", body \\ "") do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_provide_response(
           bh,
           bidi_next_id(h),
           to_string(request_id),
           status,
           to_string(content_type),
           to_string(body),
           10_000
         )
       )}
    end)
  end

  @doc "Answer a paused authRequired with credentials (`network.continueWithAuth`)."
  def bidi_continue_with_auth(h, request_id, username, password) do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_continue_with_auth(
           bh,
           bidi_next_id(h),
           to_string(request_id),
           to_string(username),
           to_string(password),
           10_000
         )
       )}
    end)
  end

  @doc "Disable (\"bypass\") or restore (\"default\") the session HTTP cache."
  def bidi_set_cache_behavior(h, behavior \\ "bypass") do
    with_bidi(h, fn bh ->
      {:ok,
       decode(
         Native.bidi_network_set_cache_behavior(bh, bidi_next_id(h), to_string(behavior), 10_000)
       )}
    end)
  end

  @doc "The network.request id out of a network event: params.request.request."
  def bidi_event_request_id(%{"params" => %{"request" => %{"request" => rid}}}), do: rid
  def bidi_event_request_id(_), do: nil

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
