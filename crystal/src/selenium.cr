# selenium.cr — the Crystal binding over the shared Aether engine.
#
# Crystal binds the engine's flat C ABI (aether_sel_embed_*) DIRECTLY via a `lib`
# block — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is resolved at link time via the
# ldflags below (the .tests.ae stages native/ and passes -L/-rpath through
# SELENIUM_CORE_LIB / the shard build flags). This file is the idiomatic Crystal
# surface: a `By` factory (Selenium 4.x shape), caller-owned-string handling, a
# typed error, and a full-feature `WebDriver`/`WebElement` mirroring the Rust
# reference (rust/src/*.rs) — navigation, elements, script, windows, frames,
# alerts, cookies, actions, waits, Select, screenshots/PDF, driver orchestration
# and WebDriver-BiDi.

require "json"

# -L/-rpath are made self-locating from this source file's dir (../native holds
# the staged libselenium_core.so) so the link works regardless of the linker's
# cwd; %-interpolation expands __DIR__ at compile time.
@[Link(ldflags: "-L#{__DIR__}/../native -Wl,-rpath,#{__DIR__}/../native -lselenium_core")]
lib LibSel
  fun open = aether_sel_embed_open(base_url : LibC::Char*) : Void*
  fun close = aether_sel_embed_close(h : Void*) : Void
  fun execute = aether_sel_embed_execute(h : Void*, name : LibC::Char*, params_json : LibC::Char*) : LibC::Int
  fun last_value = aether_sel_embed_last_value(h : Void*) : LibC::Char*
  fun last_error_code = aether_sel_embed_last_error_code(h : Void*) : LibC::Int
  fun last_error = aether_sel_embed_last_error(h : Void*) : LibC::Char*
  fun session_id = aether_sel_embed_session_id(h : Void*) : LibC::Char*
  fun by_locator = aether_sel_embed_by_locator(strategy : LibC::Char*, value : LibC::Char*) : LibC::Char*
  fun route = aether_sel_embed_route(name : LibC::Char*) : LibC::Char*
  fun error_code = aether_sel_embed_error_code(w3c_error : LibC::Char*) : LibC::Int
  fun free_string = aether_sel_embed_free_string(s : LibC::Char*) : LibC::Char*

  # TLS config (per session handle; set before newSession).
  fun set_ca = aether_sel_embed_set_ca(h : Void*, ca_path : LibC::Char*) : Void
  fun set_insecure = aether_sel_embed_set_insecure(h : Void*, on : LibC::Int) : Void

  # Atom-backed commands (run a shared JS atom in-page via the engine).
  fun is_displayed = aether_sel_embed_is_displayed(h : Void*, elem_id : LibC::Char*) : LibC::Int
  fun get_attribute = aether_sel_embed_get_attribute(h : Void*, elem_id : LibC::Char*, name : LibC::Char*) : LibC::Int
  fun find_relative = aether_sel_embed_find_relative(h : Void*, base_css : LibC::Char*, filters_json : LibC::Char*) : LibC::Int

  # Driver orchestration (spawn/adopt a driver process in-binding). An opaque
  # driver handle, independent of the W3C session handle.
  fun resolve_driver = aether_sel_embed_resolve_driver(browser : LibC::Char*, hint : LibC::Char*) : LibC::Char*
  fun launch_driver = aether_sel_embed_launch_driver(driver_path : LibC::Char*, timeout_ms : LibC::Int) : Void*
  fun ensure_driver = aether_sel_embed_ensure_driver(browser : LibC::Char*, hint : LibC::Char*, timeout_ms : LibC::Int) : Void*
  fun driver_url = aether_sel_embed_driver_url(dh : Void*) : LibC::Char*
  fun driver_pid = aether_sel_embed_driver_pid(dh : Void*) : LibC::Int
  fun stop_driver = aether_sel_embed_stop_driver(dh : Void*) : Void

  # WebDriver-BiDi (over the session's webSocketUrl). An opaque BiDi channel
  # handle, independent of the W3C session handle.
  fun bidi_open = aether_sel_embed_bidi_open(ws_url : LibC::Char*) : Void*
  fun bidi_close = aether_sel_embed_bidi_close(h : Void*) : Void
  fun bidi_send = aether_sel_embed_bidi_send(h : Void*, id : LibC::Int, method : LibC::Char*, params_json : LibC::Char*) : LibC::Int
  fun bidi_pump = aether_sel_embed_bidi_pump(h : Void*, timeout_ms : LibC::Int) : LibC::Int
  fun bidi_poll_reply = aether_sel_embed_bidi_poll_reply(h : Void*, id : LibC::Int) : LibC::Char*
  fun bidi_poll_event = aether_sel_embed_bidi_poll_event(h : Void*) : LibC::Char*
  fun bidi_lost_events = aether_sel_embed_bidi_lost_events(h : Void*) : LibC::Int
  fun bidi_cancel = aether_sel_embed_bidi_cancel(h : Void*, id : LibC::Int) : Void
  fun bidi_subscribe = aether_sel_embed_bidi_subscribe(h : Void*, id : LibC::Int, events_csv : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_unsubscribe = aether_sel_embed_bidi_unsubscribe(h : Void*, id : LibC::Int, events_csv : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_wait_event = aether_sel_embed_bidi_wait_event(h : Void*, method : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_get_tree = aether_sel_embed_bidi_get_tree(h : Void*, id : LibC::Int, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_script_evaluate = aether_sel_embed_bidi_script_evaluate(h : Void*, id : LibC::Int, expr : LibC::Char*, context_id : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_navigate = aether_sel_embed_bidi_navigate(h : Void*, id : LibC::Int, context_id : LibC::Char*, url : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_add_intercept = aether_sel_embed_bidi_network_add_intercept(h : Void*, id : LibC::Int, phases_csv : LibC::Char*, url_pattern : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_remove_intercept = aether_sel_embed_bidi_network_remove_intercept(h : Void*, id : LibC::Int, intercept_id : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_continue_request = aether_sel_embed_bidi_network_continue_request(h : Void*, id : LibC::Int, request_id : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_fail_request = aether_sel_embed_bidi_network_fail_request(h : Void*, id : LibC::Int, request_id : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_provide_response = aether_sel_embed_bidi_network_provide_response(h : Void*, id : LibC::Int, request_id : LibC::Char*, status : LibC::Int, content_type : LibC::Char*, body : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_continue_with_auth = aether_sel_embed_bidi_network_continue_with_auth(h : Void*, id : LibC::Int, request_id : LibC::Char*, username : LibC::Char*, password : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
  fun bidi_network_set_cache_behavior = aether_sel_embed_bidi_network_set_cache_behavior(h : Void*, id : LibC::Int, behavior : LibC::Char*, timeout_ms : LibC::Int) : LibC::Char*
end

module Selenium
  W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

  # A locator carrying a (strategy, value) pair — what `By.id("x")` returns and
  # what `WebDriver#find_element` takes (Selenium 4.x one-arg find).
  struct Locator
    getter strategy : String
    getter value : String

    def initialize(@strategy : String, @value : String)
    end
  end

  # By: a factory returning a `Locator`, mirroring Java's `By.id("x")`. The
  # strategy strings are the same values the engine's by_locator expects.
  # CLASS_NAME is the W3C "class name" (not "className").
  module By
    # Strategy-name constants (kept for the legacy two-arg find and for callers
    # that build a locator string via `Selenium.locator`).
    ID                = "id"
    NAME              = "name"
    CSS               = "css selector"
    CLASS_NAME        = "class name"
    TAG_NAME          = "tag name"
    LINK_TEXT         = "link text"
    PARTIAL_LINK_TEXT = "partial link text"
    XPATH             = "xpath"

    def self.id(value : String) : Locator
      Locator.new("id", value)
    end

    def self.name(value : String) : Locator
      Locator.new("name", value)
    end

    def self.css_selector(value : String) : Locator
      Locator.new("css selector", value)
    end

    def self.class_name(value : String) : Locator
      Locator.new("class name", value)
    end

    def self.tag_name(value : String) : Locator
      Locator.new("tag name", value)
    end

    def self.link_text(value : String) : Locator
      Locator.new("link text", value)
    end

    def self.partial_link_text(value : String) : Locator
      Locator.new("partial link text", value)
    end

    def self.xpath(value : String) : Locator
      Locator.new("xpath", value)
    end
  end

  # Special keys — the W3C WebDriver Unicode private-use code points for non-text
  # keys (W3C §17.4.2). Mirrors mainstream Selenium's `Keys`: send them through
  # `WebElement#send_keys` or an `Actions` key gesture. Each is a one-char String
  # in U+E000..U+E03D.
  module Keys
    NULL      = "\u{E000}"
    CANCEL    = "\u{E001}"
    HELP      = "\u{E002}"
    BACKSPACE = "\u{E003}"
    BACK_SPACE = BACKSPACE
    TAB       = "\u{E004}"
    CLEAR     = "\u{E005}"
    RETURN    = "\u{E006}"
    ENTER     = "\u{E007}"
    SHIFT     = "\u{E008}"
    LEFT_SHIFT = SHIFT
    CONTROL   = "\u{E009}"
    LEFT_CONTROL = CONTROL
    ALT       = "\u{E00A}"
    LEFT_ALT  = ALT
    PAUSE     = "\u{E00B}"
    ESCAPE    = "\u{E00C}"
    SPACE     = "\u{E00D}"
    PAGE_UP   = "\u{E00E}"
    PAGE_DOWN = "\u{E00F}"
    END_KEY   = "\u{E010}"
    HOME      = "\u{E011}"
    LEFT      = "\u{E012}"
    ARROW_LEFT = LEFT
    UP        = "\u{E013}"
    ARROW_UP  = UP
    RIGHT     = "\u{E014}"
    ARROW_RIGHT = RIGHT
    DOWN      = "\u{E015}"
    ARROW_DOWN = DOWN
    INSERT    = "\u{E016}"
    DELETE    = "\u{E017}"
    SEMICOLON = "\u{E018}"
    EQUALS    = "\u{E019}"

    NUMPAD0 = "\u{E01A}"
    NUMPAD1 = "\u{E01B}"
    NUMPAD2 = "\u{E01C}"
    NUMPAD3 = "\u{E01D}"
    NUMPAD4 = "\u{E01E}"
    NUMPAD5 = "\u{E01F}"
    NUMPAD6 = "\u{E020}"
    NUMPAD7 = "\u{E021}"
    NUMPAD8 = "\u{E022}"
    NUMPAD9 = "\u{E023}"
    MULTIPLY = "\u{E024}"
    ADD      = "\u{E025}"
    SEPARATOR = "\u{E026}"
    SUBTRACT = "\u{E027}"
    DECIMAL  = "\u{E028}"
    DIVIDE   = "\u{E029}"

    F1  = "\u{E031}"
    F2  = "\u{E032}"
    F3  = "\u{E033}"
    F4  = "\u{E034}"
    F5  = "\u{E035}"
    F6  = "\u{E036}"
    F7  = "\u{E037}"
    F8  = "\u{E038}"
    F9  = "\u{E039}"
    F10 = "\u{E03A}"
    F11 = "\u{E03B}"
    F12 = "\u{E03C}"

    META    = "\u{E03D}"
    COMMAND = "\u{E03D}"

    # A modifier chord: `modifier` held while `text` is typed, then the sequence
    # closed by the terminating NULL that the protocol uses to release held
    # modifiers — e.g. `Keys.chord(Keys::CONTROL, "a")` for select-all.
    def self.chord(modifier : String, text : String) : String
      "#{modifier}#{text}#{NULL}"
    end
  end

  # A typed WebDriver error (-1 = transport failure). `code` is the engine's
  # stable W3C error code (0 = success).
  class WebDriverError < Exception
    getter code : Int32

    def initialize(@message : String, @code : Int32)
      super(@message)
    end
  end

  # Take ownership of an engine-returned C string: copy to a Crystal String, then
  # free it via the engine's allocator (never LibC.free). Not private: instance
  # methods call it qualified as Selenium.take across the module.
  def self.take(ptr : LibC::Char*) : String
    return "" if ptr.null?
    s = String.new(ptr)
    LibSel.free_string(ptr)
    s
  end

  # ---- pure engine helpers (no session) — shared with every binding ----

  def self.route(command : String) : String
    take(LibSel.route(command))
  end

  def self.error_code(w3c_error : String) : Int32
    LibSel.error_code(w3c_error)
  end

  def self.locator(by : String, value : String) : String
    take(LibSel.by_locator(by, value))
  end

  # ---- driver orchestration (spawn / adopt a driver process in-binding) ----
  # The engine can resolve, download-or-cache, and launch a browser driver
  # process itself — so a caller needs neither a driver on PATH nor a running
  # Grid. These wrap the driver-handle C ABI (independent of the W3C session).

  # Resolve the local driver binary path for `browser` without launching it
  # (detect/download/cache as needed). `hint` pins a version or path; ""
  # auto-detects. Returns "" if none resolvable (offline, no cache).
  def self.resolve_driver(browser : String, hint : String = "") : String
    take(LibSel.resolve_driver(browser, hint))
  end

  # A driver process launched by the engine. Owns the opaque driver handle; call
  # `#stop` (or let it be GC'd/finalized) to terminate the process.
  class DriverProcess
    def initialize(@handle : Void*)
    end

    protected def handle : Void*
      @handle
    end

    def finalize
      stop
    end

    # The base URL the driver is listening on — pass to `WebDriver.chrome`.
    def url : String
      return "" if @handle.null?
      Selenium.take(LibSel.driver_url(@handle))
    end

    # The driver process id (0 if not running / stopped).
    def pid : Int32
      return 0 if @handle.null?
      LibSel.driver_pid(@handle)
    end

    # Terminate the driver process and clear the handle (idempotent).
    def stop
      unless @handle.null?
        LibSel.stop_driver(@handle)
        @handle = Pointer(Void).null
      end
    end
  end

  # Launch a driver at an explicit binary path. Returns a running DriverProcess,
  # or nil if it did not come up within `timeout_ms`.
  def self.launch_driver(driver_path : String, timeout_ms : Int32) : DriverProcess?
    h = LibSel.launch_driver(driver_path, timeout_ms)
    h.null? ? nil : DriverProcess.new(h)
  end

  # Resolve (detect/download/cache) AND launch a driver for `browser` in one
  # step. Returns a running DriverProcess, or nil if none could be
  # resolved/launched within `timeout_ms`.
  def self.ensure_driver(browser : String, hint : String, timeout_ms : Int32) : DriverProcess?
    h = LibSel.ensure_driver(browser, hint, timeout_ms)
    h.null? ? nil : DriverProcess.new(h)
  end

  # ---- session ----

  class WebDriver
    # The negotiated BiDi endpoint (value.capabilities.webSocketUrl), or "" if
    # the remote end granted none. The channel is opened lazily on first use.
    getter ws_url : String = ""
    @bidi : BiDi? = nil
    # A driver process owned by this session (populated by `.local_chrome`),
    # stopped when this WebDriver is finalized.
    @driver : DriverProcess? = nil

    # Open a session bound to a remote-end URL. No I/O until execute("newSession").
    # Prefer the `.chrome` / `.headless_chrome` / `.local_chrome` factories, which
    # negotiate capabilities and a BiDi channel for you.
    def initialize(command_executor : String)
      @handle = LibSel.open(command_executor)
    end

    def finalize
      LibSel.close(@handle)
    end

    # Start a Chrome session against a running chromedriver (or Grid). `options`
    # is a JSON object of extra capabilities merged under browserName: chrome.
    # `ca_path` pins a private-CA bundle; `insecure` skips TLS verification
    # (dev/staging only) — both land on the handle BEFORE newSession.
    def self.chrome(command_executor : String, options : JSON::Any? = nil,
                    ca_path : String? = nil, insecure : Bool = false) : WebDriver
      caps = Hash(String, JSON::Any).new
      if options && (obj = options.as_h?)
        obj.each { |k, v| caps[k] = v }
      end
      caps["browserName"] = JSON::Any.new("chrome")
      d = WebDriver.new(command_executor)
      d.configure_tls(ca_path, insecure)
      d.new_session(caps)
      d
    end

    # Convenience: headless-Chrome launch args baked in.
    def self.headless_chrome(command_executor : String) : WebDriver
      opts = JSON.parse(%({"goog:chromeOptions":{"args":["--headless=new","--no-sandbox","--disable-gpu","--disable-dev-shm-usage"]}}))
      chrome(command_executor, opts)
    end

    # A Chrome session that spawns its own chromedriver via the engine — no
    # driver on PATH, no Grid. The driver process is owned by the returned
    # WebDriver and stopped when it is quit or finalized. `hint` pins a driver
    # version/path ("" auto-detects).
    def self.local_chrome(options : JSON::Any? = nil, hint : String = "",
                          timeout_ms : Int32 = 15000,
                          ca_path : String? = nil, insecure : Bool = false) : WebDriver
      proc = Selenium.ensure_driver("chrome", hint, timeout_ms)
      raise WebDriverError.new("could not resolve/launch chromedriver", -1) if proc.nil?
      d = chrome(proc.url, options, ca_path, insecure)
      d.adopt_driver(proc)
      d
    end

    # Apply TLS trust config on the handle before newSession. Internal — called
    # by the factories; not part of the everyday surface.
    protected def configure_tls(ca_path : String?, insecure : Bool)
      LibSel.set_ca(@handle, ca_path) if ca_path
      LibSel.set_insecure(@handle, 1) if insecure
    end

    # Negotiate the W3C session (newSession) with `caps` as alwaysMatch, also
    # requesting a BiDi channel (webSocketUrl). Records the negotiated ws url.
    protected def new_session(caps : Hash(String, JSON::Any))
      caps["webSocketUrl"] = JSON::Any.new(true)
      payload = {"capabilities" => {"alwaysMatch" => caps}}
      result = execute_json("newSession", payload.to_json)
      @ws_url = result.dig?("capabilities", "webSocketUrl").try(&.as_s?) || ""
    end

    protected def adopt_driver(proc : DriverProcess)
      @driver = proc
    end

    # Run a command by name with JSON params; return the result value (raw JSON),
    # raising a typed WebDriverError on a protocol/transport error.
    def execute(name : String, params_json : String = "{}") : String
      rc = LibSel.execute(@handle, name, params_json)
      if rc != 0
        msg = Selenium.take(LibSel.last_error(@handle))
        code = LibSel.last_error_code(@handle)
        raise WebDriverError.new(msg, (rc == -1 && code == 0) ? -1 : code)
      end
      Selenium.take(LibSel.last_value(@handle))
    end

    # As `execute`, but parse the result JSON to a JSON::Any (Null when empty).
    def execute_json(name : String, params_json : String = "{}") : JSON::Any
      raw = execute(name, params_json)
      raw.empty? ? JSON::Any.new(nil) : JSON.parse(raw)
    end

    # Drain the last_value after an atom call (is_displayed / get_attribute /
    # find_relative), mapping rc != 0 to a typed error exactly as `execute` does.
    protected def atom_result(rc : LibC::Int) : JSON::Any
      if rc != 0
        msg = Selenium.take(LibSel.last_error(@handle))
        code = LibSel.last_error_code(@handle)
        raise WebDriverError.new(msg, (rc == -1 && code == 0) ? -1 : code)
      end
      raw = Selenium.take(LibSel.last_value(@handle))
      raw.empty? ? JSON::Any.new(nil) : JSON.parse(raw)
    end

    # The raw engine handle — used by the element-scoped atom calls.
    protected def handle : Void*
      @handle
    end

    # ---- navigation ----
    def get(url : String)
      execute("get", {"url" => url}.to_json)
    end

    def current_url : String
      execute_json("getCurrentUrl").as_s? || ""
    end

    def title : String
      execute_json("getTitle").as_s? || ""
    end

    def page_source : String
      execute_json("getPageSource").as_s? || ""
    end

    def back
      execute("goBack", "{}")
    end

    def forward
      execute("goForward", "{}")
    end

    def refresh
      execute("refresh", "{}")
    end

    # ---- elements ----

    # Find one element by a `By` locator (Selenium 4.x one-arg find):
    #   driver.find_element(Selenium::By.id("hdr"))
    # Returns a WebElement. Raises WebDriverError(17) when the response carries
    # no element reference.
    def find_element(locator : Locator) : WebElement
      params = Selenium.locator(locator.strategy, locator.value)
      element_from(execute_json("findElement", params))
    end

    # Find all elements matching a `By` locator; returns their WebElements.
    def find_elements(locator : Locator) : Array(WebElement)
      params = Selenium.locator(locator.strategy, locator.value)
      arr = execute_json("findElements", params).as_a? || [] of JSON::Any
      arr.map { |el| element_from(el) }
    end

    protected def element_from(value : JSON::Any) : WebElement
      id = value[W3C_ELEMENT_KEY]?.try(&.as_s?)
      raise WebDriverError.new("element reference key missing", 17) if id.nil?
      WebElement.new(self, id)
    end

    # True if at least one element matching `locator` is present RIGHT NOW — an
    # immediate presence check with no implicit wait. A clean element-not-found
    # resolves to false; a transport-level failure still raises.
    def exists?(locator : Locator) : Bool
      find_element(locator)
      true
    rescue e : WebDriverError
      return false if e.code == 17
      raise e
    end

    # The active (focused) element (getActiveElement) — the element that would
    # receive keyboard input.
    def active_element : WebElement
      element_from(execute_json("getActiveElement"))
    end

    # Relative locators: elements matching `base_css` filtered by spatial relation
    # to anchors, nearest first. Each filter is a JSON object
    # {"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"} ("near" also
    # accepts "dist"). Returns the matching elements.
    def find_relative(base_css : String, filters : Array(JSON::Any)) : Array(WebElement)
      rc = LibSel.find_relative(@handle, base_css, filters.to_json)
      result = atom_result(rc)
      (result.as_a? || [] of JSON::Any).map { |r| element_from(r) }
    end

    # The NUMBER of elements a relative-locator query matches, without
    # materializing WebElement handles — the count-only counterpart to
    # `find_relative`.
    def find_relative_count(base_css : String, filters : Array(JSON::Any)) : Int32
      rc = LibSel.find_relative(@handle, base_css, filters.to_json)
      result = atom_result(rc)
      (result.as_a? || [] of JSON::Any).size
    end

    # ---- script ----
    def execute_script(script : String, args : Array(JSON::Any) = [] of JSON::Any) : JSON::Any
      execute_json("executeScript", {"script" => script, "args" => args}.to_json)
    end

    # Run an async script: the page signals completion via the injected callback
    # (arguments[arguments.length - 1]). Returns the callback value.
    def execute_async_script(script : String, args : Array(JSON::Any) = [] of JSON::Any) : JSON::Any
      execute_json("executeAsyncScript", {"script" => script, "args" => args}.to_json)
    end

    # ---- windows ----
    def window_handles : Array(String)
      arr = execute_json("getWindowHandles").as_a? || [] of JSON::Any
      arr.compact_map(&.as_s?)
    end

    def current_window_handle : String
      execute_json("getCurrentWindowHandle").as_s? || ""
    end

    # Switch the session's top-level browsing context to the window `handle`.
    def switch_to_window(handle : String)
      execute("switchToWindow", {"handle" => handle}.to_json)
    end

    def set_window_rect(rect : JSON::Any) : JSON::Any
      execute_json("setWindowRect", rect.to_json)
    end

    def get_window_rect : JSON::Any
      execute_json("getWindowRect")
    end

    # Maximize the current window. Returns the resulting window rect.
    def maximize_window : JSON::Any
      execute_json("maximizeWindow")
    end

    # Minimize (hide) the current window. Returns the resulting window rect.
    def minimize_window : JSON::Any
      execute_json("minimizeWindow")
    end

    # Put the current window into fullscreen. Returns the resulting window rect.
    def fullscreen_window : JSON::Any
      execute_json("fullscreenWindow")
    end

    # Open a new top-level browsing context (newWindow). `type_hint` is "tab" or
    # "window". Returns the new window's handle — pass it to `switch_to_window`.
    def new_window(type_hint : String = "tab") : String
      execute_json("newWindow", {"type" => type_hint}.to_json).dig?("handle").try(&.as_s?) || ""
    end

    # Close the current window/tab (close). Returns the window handles that
    # remain. Does NOT end the session (use `quit` for that).
    def close_window : Array(String)
      arr = execute_json("close").as_a? || [] of JSON::Any
      arr.compact_map(&.as_s?)
    end

    # ---- frames ----

    # Switch focus to a frame by 0-based index among the current context's child
    # frames.
    def switch_to_frame(index : Int)
      execute("switchToFrame", {"id" => index}.to_json)
    end

    # Switch focus to the frame whose <iframe>/<frame> element is `element`.
    def switch_to_frame(element : WebElement)
      execute("switchToFrame", {"id" => {W3C_ELEMENT_KEY => element.id}}.to_json)
    end

    # Switch to the parent of the current frame (one level out, unlike
    # `switch_to_default_content` which jumps to the top).
    def switch_to_parent_frame
      execute("switchToFrameParent", "{}")
    end

    # Return focus to the top-level browsing context (switchToFrame with a null
    # id).
    def switch_to_default_content
      execute("switchToFrame", %({"id":null}))
    end

    # ---- alerts ----

    # Accept (OK) the current user-prompt / alert dialog.
    def accept_alert
      execute("acceptAlert", "{}")
    end

    # Dismiss (Cancel) the current user-prompt / alert dialog.
    def dismiss_alert
      execute("dismissAlert", "{}")
    end

    # The message text of the current dialog.
    def alert_text : String
      execute_json("getAlertText").as_s? || ""
    end

    # Type `text` into the current prompt dialog's input field.
    def send_alert_text(text : String)
      execute("setAlertValue", {"text" => text}.to_json)
    end

    # True if a user-prompt / alert dialog is currently present (probing it via
    # getAlertText). A clean "no such alert" (code 15) resolves to false; a
    # transport-level failure still raises.
    def alert_present? : Bool
      execute("getAlertText", "{}")
      true
    rescue e : WebDriverError
      return false if e.code == 15
      raise e
    end

    # ---- cookies ----
    def add_cookie(cookie : JSON::Any)
      execute("addCookie", {"cookie" => cookie}.to_json)
    end

    def get_cookies : JSON::Any
      execute_json("getCookies")
    end

    def get_cookie(name : String) : JSON::Any
      execute_json("getCookie", {"name" => name}.to_json)
    end

    def delete_cookie(name : String)
      execute("deleteCookie", {"name" => name}.to_json)
    end

    def delete_all_cookies
      execute("deleteAllCookies", "{}")
    end

    # ---- actions ----

    # Start a fluent `Actions` builder bound to this driver: queue pointer / key
    # gestures, then `.perform`.
    def actions : Actions
      Actions.new(self)
    end

    def perform_actions(actions : Array(JSON::Any))
      execute("actions", {"actions" => actions}.to_json)
    end

    def clear_actions
      execute("clearActions", "{}")
    end

    # ---- timeouts (all in milliseconds) ----
    def set_timeouts(timeouts : JSON::Any)
      execute("setTimeout", timeouts.to_json)
    end

    # How long navigation may take before timing out.
    def set_page_load_timeout(ms : Int)
      execute("setTimeout", {"pageLoad" => ms}.to_json)
    end

    # How long `execute_async_script` may run before timing out.
    def set_script_timeout(ms : Int)
      execute("setTimeout", {"script" => ms}.to_json)
    end

    # How long `find_element` retries before failing.
    def implicitly_wait(ms : Int)
      execute("setTimeout", {"implicit" => ms}.to_json)
    end

    # ---- screenshots / print ----
    def screenshot_base64 : String
      execute_json("screenshot").as_s? || ""
    end

    # Print the current page to PDF (printPage), returning the PDF as a base64
    # string. `options` is the W3C print-options object; pass nil for defaults.
    def print_pdf(options : JSON::Any? = nil) : String
      params = (options && options.as_h?) ? options.to_json : "{}"
      execute_json("printPage", params).as_s? || ""
    end

    # ---- explicit waits ----

    # Start an explicit wait with the given `timeout_ms`. Poll cadence defaults to
    # 500ms; override with `Wait#poll_every`.
    def wait(timeout_ms : Int32) : Wait
      Wait.new(self, timeout_ms)
    end

    # Block until an element matching `locator` is present in the DOM; return it.
    def wait_for_element(locator : Locator, timeout_ms : Int32) : WebElement
      wait(timeout_ms).until_element { try_find(locator) }
    end

    # Block until an element matching `locator` is present AND displayed; return
    # it.
    def wait_for_visible(locator : Locator, timeout_ms : Int32) : WebElement
      wait(timeout_ms).until_element do
        el = try_find(locator)
        el && el.displayed? ? el : nil
      end
    end

    # Block until an element matching `locator` is present, displayed AND enabled
    # (clickable); return it.
    def wait_for_clickable(locator : Locator, timeout_ms : Int32) : WebElement
      wait(timeout_ms).until_element do
        el = try_find(locator)
        el && el.displayed? && el.enabled? ? el : nil
      end
    end

    # Block until NO element matches `locator` — it's absent/removed.
    def wait_until_gone(locator : Locator, timeout_ms : Int32)
      wait(timeout_ms).until_not { !try_find(locator).nil? }
    end

    # Block until the page title equals `title`.
    def wait_for_title_is(title_text : String, timeout_ms : Int32)
      wait(timeout_ms).until { title == title_text }
    end

    # Block until the page title contains `substr`.
    def wait_for_title_contains(substr : String, timeout_ms : Int32)
      wait(timeout_ms).until { title.includes?(substr) }
    end

    # Block until the current URL equals `url`.
    def wait_for_url_is(url : String, timeout_ms : Int32)
      wait(timeout_ms).until { current_url == url }
    end

    # Block until the current URL contains `substr`.
    def wait_for_url_contains(substr : String, timeout_ms : Int32)
      wait(timeout_ms).until { current_url.includes?(substr) }
    end

    # `find_element` that maps a NoSuchElement miss to nil instead of raising —
    # the primitive the element-returning waits poll on. Any other error raises.
    protected def try_find(locator : Locator) : WebElement?
      find_element(locator)
    rescue e : WebDriverError
      return nil if e.code == 17
      raise e
    end

    # ---- lifecycle ----
    def session_id : String
      Selenium.take(LibSel.session_id(@handle))
    end

    def quit
      @bidi = nil
      execute("quit", "{}") rescue nil
    end

    # ---- WebDriver-BiDi ----

    # True if this session negotiated a webSocketUrl (BiDi usable).
    def bidi_available? : Bool
      !@ws_url.empty?
    end

    # The event-driven BiDi surface for this session, opened lazily over the
    # negotiated webSocketUrl. Raises if the remote end granted no BiDi URL.
    def bidi : BiDi
      existing = @bidi
      return existing if existing
      raise WebDriverError.new("BiDi not available: the session negotiated no webSocketUrl", 0) if @ws_url.empty?
      h = LibSel.bidi_open(@ws_url)
      raise WebDriverError.new("BiDi channel failed to open", -1) if h.null?
      channel = BiDi.new(h)
      @bidi = channel
      channel
    end
  end

  # ---- WebElement ----

  # A remote element handle. Methods issue element-scoped commands, passing this
  # element's id as the `:id` path parameter.
  class WebElement
    getter id : String

    def initialize(@driver : WebDriver, @id : String)
    end

    # Issue an element-scoped command, injecting this element's id.
    private def exec(command : String, params : Hash(String, JSON::Any) = {} of String => JSON::Any) : JSON::Any
      params = params.dup
      params["id"] = JSON::Any.new(@id)
      @driver.execute_json(command, params.to_json)
    end

    def click
      exec("clickElement")
    end

    def clear
      exec("clearElement")
    end

    # Type `text` (accepts `Keys` constants embedded in the string). Sends the
    # decomposed char array the protocol wants plus the flat text.
    def send_keys(text : String)
      chars = text.chars.map { |c| JSON::Any.new(c.to_s) }
      exec("sendKeysToElement", {"text" => JSON::Any.new(text), "value" => JSON::Any.new(chars)})
    end

    def text : String
      exec("getElementText").as_s? || ""
    end

    def tag_name : String
      exec("getElementTagName").as_s? || ""
    end

    # Whether the element is shown (the isDisplayed atom, run in-page by the
    # engine — the real visibility algorithm, not a naive style check).
    def displayed? : Bool
      rc = LibSel.is_displayed(@driver.handle, @id)
      @driver.atom_result(rc).as_bool? || false
    end

    # The classic getAttribute(name): property-or-attribute (boolean attrs, live
    # properties like value/checked), via the shared engine atom. Returns nil when
    # the attribute is absent. Use `dom_attribute` for the raw W3C DOM attribute.
    def get_attribute(name : String) : String?
      rc = LibSel.get_attribute(@driver.handle, @id, name)
      @driver.atom_result(rc).as_s?
    end

    # The literal DOM attribute (W3C getDomAttribute), no property fallback.
    def dom_attribute(name : String) : JSON::Any
      exec("getDomAttribute", {"name" => JSON::Any.new(name)})
    end

    def property(name : String) : JSON::Any
      exec("getElementProperty", {"name" => JSON::Any.new(name)})
    end

    def enabled? : Bool
      exec("isElementEnabled").as_bool? || false
    end

    def selected? : Bool
      exec("isElementSelected").as_bool? || false
    end

    def rect : JSON::Any
      exec("getElementRect")
    end

    # The computed value of the CSS property `prop` on this element
    # (getElementValueOfCssProperty). Aliased as `value_of_css_property` for
    # parity with the classic Selenium name.
    def css_value(prop : String) : String
      exec("getElementValueOfCssProperty", {"propertyName" => JSON::Any.new(prop)}).as_s? || ""
    end

    # Classic-Selenium-named alias of `css_value`.
    def value_of_css_property(prop : String) : String
      css_value(prop)
    end

    # A PNG screenshot of just this element (takeElementScreenshot), as a base64
    # string.
    def screenshot_base64 : String
      exec("takeElementScreenshot").as_s? || ""
    end

    # Submit the form this element belongs to. W3C removed the dedicated `submit`
    # endpoint, so — like the reference binding and modern Selenium — this walks
    # up to the enclosing <form> and calls requestSubmit() (falling back to
    # submit()) via an injected script. Raises (code 17) if not inside a form.
    def submit
      script = "var e=arguments[0];var f=e.form||e.closest('form');" \
               "if(!f){throw new Error('Element is not within a form');}" \
               "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"
      arg = JSON::Any.new({W3C_ELEMENT_KEY => JSON::Any.new(@id)})
      @driver.execute_script(script, [arg])
    end

    # Find one descendant of this element matching `locator` (findChildElement).
    def find_element(locator : Locator) : WebElement
      params = Selenium.locator(locator.strategy, locator.value)
      inject_id(params) do |json|
        @driver.element_from(@driver.execute_json("findChildElement", json))
      end
    end

    # Find all descendants of this element matching `locator` (findChildElements).
    def find_elements(locator : Locator) : Array(WebElement)
      params = Selenium.locator(locator.strategy, locator.value)
      inject_id(params) do |json|
        arr = @driver.execute_json("findChildElements", json).as_a? || [] of JSON::Any
        arr.map { |el| @driver.element_from(el) }
      end
    end

    # The findChild* commands take the W3C locator JSON plus this element's id;
    # merge the two objects and yield the combined JSON string.
    private def inject_id(locator_json : String)
      obj = JSON.parse(locator_json).as_h.dup
      obj["id"] = JSON::Any.new(@id)
      yield obj.to_json
    end
  end

  # ---- Actions (fluent action builder) ----

  # A queued sequence of W3C input actions, built fluently and posted in one
  # `actions` command by `#perform`. Obtain one from `WebDriver#actions`. Each
  # call appends to a W3C actions sequence (a pointer virtual device and a key
  # virtual device); `#perform` posts the whole sequence in one command.
  class Actions
    @pointer = [] of JSON::Any
    @key = [] of JSON::Any

    def initialize(@driver : WebDriver)
    end

    private def pause_action(duration_ms : Int32) : JSON::Any
      JSON::Any.new({"type" => JSON::Any.new("pause"), "duration" => JSON::Any.new(duration_ms.to_i64)})
    end

    private def move_to(id : String) : JSON::Any
      origin = JSON::Any.new({W3C_ELEMENT_KEY => JSON::Any.new(id)})
      JSON::Any.new({
        "type"     => JSON::Any.new("pointerMove"),
        "duration" => JSON::Any.new(100_i64),
        "x"        => JSON::Any.new(0_i64),
        "y"        => JSON::Any.new(0_i64),
        "origin"   => origin,
      })
    end

    private def button_down(button : Int32) : JSON::Any
      JSON::Any.new({"type" => JSON::Any.new("pointerDown"), "button" => JSON::Any.new(button.to_i64)})
    end

    private def button_up(button : Int32) : JSON::Any
      JSON::Any.new({"type" => JSON::Any.new("pointerUp"), "button" => JSON::Any.new(button.to_i64)})
    end

    private def key_event(kind : String, value : String) : JSON::Any
      JSON::Any.new({"type" => JSON::Any.new(kind), "value" => JSON::Any.new(value)})
    end

    private def is_pause?(a : JSON::Any) : Bool
      a["type"]?.try(&.as_s?) == "pause"
    end

    # W3C requires every device's action list to be the same length; pad the
    # shorter device with zero-duration pauses so gestures on one device don't
    # desync the other's ticks.
    private def sync_lengths
      n = Math.max(@pointer.size, @key.size)
      @pointer << pause_action(0) while @pointer.size < n
      @key << pause_action(0) while @key.size < n
    end

    # ---- pointer gestures ----

    # Move the pointer to the centre of `element`.
    def move_to_element(element : WebElement) : Actions
      @pointer << move_to(element.id)
      sync_lengths
      self
    end

    # Left-click. With an element, moves to it first; without, clicks where the
    # pointer currently is.
    def click(element : WebElement? = nil) : Actions
      @pointer << move_to(element.id) if element
      @pointer << button_down(0)
      @pointer << button_up(0)
      sync_lengths
      self
    end

    # Right-click (contextmenu). Moves to `element` first when given.
    def context_click(element : WebElement? = nil) : Actions
      @pointer << move_to(element.id) if element
      @pointer << button_down(2)
      @pointer << button_up(2)
      sync_lengths
      self
    end

    # Double-click. Moves to `element` first when given.
    def double_click(element : WebElement? = nil) : Actions
      @pointer << move_to(element.id) if element
      2.times do
        @pointer << button_down(0)
        @pointer << button_up(0)
      end
      sync_lengths
      self
    end

    # Press and hold the left button (the start of a drag). Moves to `element`
    # first when given.
    def click_and_hold(element : WebElement? = nil) : Actions
      @pointer << move_to(element.id) if element
      @pointer << button_down(0)
      sync_lengths
      self
    end

    # Release the held left button. Moves to `element` first when given.
    def release(element : WebElement? = nil) : Actions
      @pointer << move_to(element.id) if element
      @pointer << button_up(0)
      sync_lengths
      self
    end

    # Drag `source` onto `target` (press at source, move to target, release).
    def drag_and_drop(source : WebElement, target : WebElement) : Actions
      click_and_hold(source)
      move_to_element(target)
      release
      self
    end

    # ---- key gestures ----

    # Press (and hold) a key on the keyboard device — pair with `#key_up` for a
    # chord. `key` is a one-char String (e.g. a `Keys` constant).
    def key_down(key : String) : Actions
      @key << key_event("keyDown", key)
      sync_lengths
      self
    end

    # Release a previously pressed key.
    def key_up(key : String) : Actions
      @key << key_event("keyUp", key)
      sync_lengths
      self
    end

    # Type `text` (a keyDown+keyUp per character) on the keyboard device.
    def send_keys(text : String) : Actions
      text.each_char do |ch|
        @key << key_event("keyDown", ch.to_s)
        @key << key_event("keyUp", ch.to_s)
      end
      sync_lengths
      self
    end

    # Insert a pause (ms) on the pointer device — a deliberate delay tick.
    def pause(duration_ms : Int32) : Actions
      @pointer << pause_action(duration_ms)
      sync_lengths
      self
    end

    # ---- terminal ----

    # The W3C `actions` array this builder has accumulated. A device sub-array is
    # emitted only when it holds a real (non-pause) action.
    def build : Array(JSON::Any)
      actions = [] of JSON::Any
      if @pointer.any? { |a| !is_pause?(a) }
        actions << JSON::Any.new({
          "type"       => JSON::Any.new("pointer"),
          "id"         => JSON::Any.new("mouse"),
          "parameters" => JSON::Any.new({"pointerType" => JSON::Any.new("mouse")}),
          "actions"    => JSON::Any.new(@pointer.dup),
        })
      end
      if @key.any? { |a| !is_pause?(a) }
        actions << JSON::Any.new({
          "type"    => JSON::Any.new("key"),
          "id"      => JSON::Any.new("keyboard"),
          "actions" => JSON::Any.new(@key.dup),
        })
      end
      actions
    end

    # Post the queued gestures as one `actions` command. A no-op (no request) when
    # nothing but pauses was queued.
    def perform
      actions = build
      return if actions.empty?
      @driver.perform_actions(actions)
    end
  end

  # ---- Wait (explicit waits) ----

  # A configured waiter over a driver: call `#until` / `#until_not` with a block.
  # Polls the block until it returns a truthy value (or the deadline passes). The
  # poll loop lives here in the binding — the engine issues single commands and
  # holds no thread, exactly as the reference waits do. On timeout, raises a
  # WebDriverError of code 21.
  class Wait
    # The default poll cadence between condition checks (mainstream's 500ms).
    POLL_INTERVAL_MS = 500

    def initialize(@driver : WebDriver, @timeout_ms : Int32)
      @poll_ms = POLL_INTERVAL_MS
    end

    # Override the poll cadence (default 500ms). A non-positive interval is
    # clamped up to the default.
    def poll_every(interval_ms : Int32) : Wait
      @poll_ms = interval_ms <= 0 ? POLL_INTERVAL_MS : interval_ms
      self
    end

    # Poll `block` until it returns a truthy value; then return. A NoSuchElement
    # (code 17) raised by the block is swallowed and retried. On timeout, raises.
    def until(&block : -> Bool)
      deadline = Time.monotonic + @timeout_ms.milliseconds
      loop do
        begin
          return if block.call
        rescue e : WebDriverError
          raise e unless e.code == 17
        end
        raise timed_out if Time.monotonic >= deadline
        sleep @poll_ms.milliseconds
      end
    end

    # Poll `block` until it returns false (or an ignored NoSuchElement, which
    # counts as "gone"); then return. On timeout, raises.
    def until_not(&block : -> Bool)
      deadline = Time.monotonic + @timeout_ms.milliseconds
      loop do
        begin
          return unless block.call
        rescue e : WebDriverError
          return if e.code == 17
          raise e
        end
        raise timed_out if Time.monotonic >= deadline
        sleep @poll_ms.milliseconds
      end
    end

    # Element-returning poll loop: run `block` each tick; the first non-nil result
    # is returned, nil retries, an ignored NoSuchElement retries, the deadline
    # raises a timeout. Used by the `wait_for_*` element helpers.
    def until_element(&block : -> WebElement?) : WebElement
      deadline = Time.monotonic + @timeout_ms.milliseconds
      loop do
        begin
          el = block.call
          return el if el
        rescue e : WebDriverError
          raise e unless e.code == 17
        end
        raise timed_out if Time.monotonic >= deadline
        sleep @poll_ms.milliseconds
      end
    end

    private def timed_out : WebDriverError
      WebDriverError.new("waited #{@timeout_ms}ms for condition", 21)
    end
  end

  # ---- Select (<select> dropdown helper) ----

  # A wrapper over a <select> element that selects among its <option> children,
  # the same approach mainstream Selenium's Select uses. Build one with
  # `Select.new(element)`.
  class Select
    def initialize(@element : WebElement)
      tag = @element.tag_name.downcase
      raise WebDriverError.new("Select only works on <select> elements, not <#{tag}>", 0) if tag != "select"
      # `multiple` is a boolean attribute: present (any non-"false" value) ==
      # multi-select.
      multi = @element.get_attribute("multiple")
      @is_multiple = multi ? (!multi.empty? && multi != "false") : false
    end

    # Whether this is a multi-select (`multiple` attribute present).
    def multiple? : Bool
      @is_multiple
    end

    # All <option> children, in document order.
    def options : Array(WebElement)
      @element.find_elements(By.tag_name("option"))
    end

    # The options currently selected.
    def all_selected_options : Array(WebElement)
      options.select(&.selected?)
    end

    # The first selected option. Raises (code 17) if none is selected.
    def first_selected_option : WebElement
      options.each { |o| return o if o.selected? }
      raise WebDriverError.new("no option is selected", 17)
    end

    # Select the option whose visible text equals `text`. Raises (code 17) if none
    # matches.
    def select_by_visible_text(text : String)
      opts = options
      opts.each do |o|
        if o.text == text
          select_option(o)
          return
        end
      end
      raise WebDriverError.new("no option with visible text #{text.inspect}", 17)
    end

    # Select the option whose `value` attribute equals `value`. Raises (code 17)
    # if none matches.
    def select_by_value(value : String)
      opts = options
      opts.each do |o|
        if o.get_attribute("value") == value
          select_option(o)
          return
        end
      end
      raise WebDriverError.new("no option with value #{value.inspect}", 17)
    end

    # Select the option at `index` (0-based, document order). Raises (code 17) if
    # out of range.
    def select_by_index(index : Int)
      opts = options
      raise WebDriverError.new("no option at index #{index}", 17) unless (0...opts.size).includes?(index)
      select_option(opts[index])
    end

    # Deselect every selected option (multi-select only). Raises (code 0) on a
    # single-select.
    def deselect_all
      raise WebDriverError.new("deselect_all only makes sense on a multi-select", 0) unless @is_multiple
      options.each { |o| o.click if o.selected? }
    end

    # Click an option to select it, but only if it isn't already selected — a
    # second click on a selected single-select option is a no-op, but on a
    # multi-select it would toggle it off.
    private def select_option(option : WebElement)
      option.click unless option.selected?
    end
  end

  # ---- WebDriver-BiDi ----

  # The common WebDriver-BiDi event names (W3C spec). Pass to `BiDi#subscribe`
  # and match in `BiDi#next_event`.
  module BidiEvent
    LOG_ENTRY_ADDED     = "log.entryAdded"
    CONTEXT_CREATED     = "browsingContext.contextCreated"
    CONTEXT_DESTROYED   = "browsingContext.contextDestroyed"
    NAVIGATION_STARTED  = "browsingContext.navigationStarted"
    DOM_CONTENT_LOADED  = "browsingContext.domContentLoaded"
    LOAD                = "browsingContext.load"
    DOWNLOAD_WILL_BEGIN = "browsingContext.downloadWillBegin"
    BEFORE_REQUEST_SENT = "network.beforeRequestSent"
    AUTH_REQUIRED       = "network.authRequired"
    RESPONSE_STARTED    = "network.responseStarted"
    RESPONSE_COMPLETED  = "network.responseCompleted"
    FETCH_ERROR         = "network.fetchError"
    REALM_CREATED       = "script.realmCreated"
    REALM_DESTROYED     = "script.realmDestroyed"
    MESSAGE             = "script.message"
  end

  # The event-driven BiDi channel for a session (over the demux C ABI). Commands
  # and events multiplex over one WebSocket via the engine's demux; command ids
  # are supplied automatically from a monotonic per-channel counter (from 1).
  class BiDi
    def initialize(@handle : Void*)
      @next_id = 1
    end

    def finalize
      unless @handle.null?
        LibSel.bidi_close(@handle)
        @handle = Pointer(Void).null
      end
    end

    private def next_id : Int32
      id = @next_id
      @next_id += 1
      id
    end

    private def decode(raw : String) : JSON::Any
      raw.empty? ? JSON::Any.new(nil) : JSON.parse(raw)
    end

    # session.subscribe to one or more event names; wait for the ack. Matching
    # events then arrive on the queue (drain via `#next_event`).
    def subscribe(events : Array(String), timeout_ms : Int32 = 10000) : JSON::Any
      decode(Selenium.take(LibSel.bidi_subscribe(@handle, next_id, events.join(","), timeout_ms)))
    end

    def unsubscribe(events : Array(String), timeout_ms : Int32 = 10000) : JSON::Any
      decode(Selenium.take(LibSel.bidi_unsubscribe(@handle, next_id, events.join(","), timeout_ms)))
    end

    # Block until an event whose `method` matches arrives, or timeout. Returns the
    # event, or nil on timeout/close. (Subscribe first.)
    def next_event(method : String, timeout_ms : Int32) : JSON::Any?
      raw = Selenium.take(LibSel.bidi_wait_event(@handle, method, timeout_ms))
      raw.empty? ? nil : decode(raw)
    end

    # Issue any BiDi command and return its reply payload. Reaches BiDi methods
    # with no dedicated wrapper (script.evaluate, network.*, ...). Sends, then
    # pumps until this id's reply arrives or the timeout elapses.
    def command(method : String, params : JSON::Any, timeout_ms : Int32) : JSON::Any
      cid = next_id
      raise WebDriverError.new("BiDi send failed: #{method}", -1) if LibSel.bidi_send(@handle, cid, method, params.to_json) != 0
      waited = 0
      step = 50
      while waited < timeout_ms
        reply = Selenium.take(LibSel.bidi_poll_reply(@handle, cid))
        return decode(reply) unless reply.empty?
        break if LibSel.bidi_pump(@handle, step) < 0
        waited += step
      end
      raise WebDriverError.new("BiDi command timed out: #{method}", 21)
    end

    # browsingContext.getTree — the browsing contexts (each with a `context` id).
    def get_tree(timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_get_tree(@handle, next_id, timeout_ms)))
    end

    # The top-level browsing context id (the anchor for evaluate/navigate), or nil
    # when the tree is empty.
    def top_context(timeout_ms : Int32) : String?
      tree = get_tree(timeout_ms)
      tree.dig?("result", "contexts").try(&.as_a?).try(&.first?).try(&.dig?("context")).try(&.as_s?)
    end

    # script.evaluate an expression in the top-level context's realm, awaiting a
    # returned promise. Returns the reply; ["result"]["result"] is the BiDi-typed
    # value.
    def evaluate(expr : String, timeout_ms : Int32) : JSON::Any
      ctx = top_context(timeout_ms)
      raise WebDriverError.new("no browsing context for script.evaluate", 0) if ctx.nil?
      decode(Selenium.take(LibSel.bidi_script_evaluate(@handle, next_id, expr, ctx, timeout_ms)))
    end

    # script.evaluate, returning just the unwrapped value (the `.value` of the
    # BiDi-typed result), or nil if it wasn't a simple value.
    def evaluate_value(expr : String, timeout_ms : Int32) : JSON::Any?
      evaluate(expr, timeout_ms).dig?("result", "result", "value")
    end

    # browsingContext.navigate the top-level context to `url` (wait: complete).
    def navigate(url : String, timeout_ms : Int32) : JSON::Any
      ctx = top_context(timeout_ms)
      raise WebDriverError.new("no browsing context for navigate", 0) if ctx.nil?
      decode(Selenium.take(LibSel.bidi_navigate(@handle, next_id, ctx, url, timeout_ms)))
    end

    # ---- network interception ----

    # network.addIntercept for a URL pattern at the given comma-separated phases.
    # Returns the intercept id (result.intercept), or nil.
    def add_intercept(phases_csv : String, url_pattern : String, timeout_ms : Int32) : String?
      raw = Selenium.take(LibSel.bidi_network_add_intercept(@handle, next_id, phases_csv, url_pattern, timeout_ms))
      decode(raw).dig?("result", "intercept").try(&.as_s?)
    end

    # network.removeIntercept — stop intercepting for a prior intercept id.
    def remove_intercept(intercept_id : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_remove_intercept(@handle, next_id, intercept_id, timeout_ms)))
    end

    # Let a paused (intercepted) request proceed unchanged. `request_id` comes
    # from a network event's params.request.request (see `.event_request_id`).
    def continue_request(request_id : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_continue_request(@handle, next_id, request_id, timeout_ms)))
    end

    # Block a paused request (the ad/tracker-blocking case).
    def fail_request(request_id : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_fail_request(@handle, next_id, request_id, timeout_ms)))
    end

    # Fulfill a paused request with a mock response (network.provideResponse),
    # bypassing the network.
    def provide_response(request_id : String, status : Int32, content_type : String, body : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_provide_response(@handle, next_id, request_id, status, content_type, body, timeout_ms)))
    end

    # Answer an HTTP auth challenge (a paused authRequired request) with
    # credentials.
    def continue_with_auth(request_id : String, username : String, password : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_continue_with_auth(@handle, next_id, request_id, username, password, timeout_ms)))
    end

    # Set the session HTTP cache behavior (network.setCacheBehavior): "bypass"
    # disables it, "default" restores it.
    def set_cache_behavior(behavior : String, timeout_ms : Int32) : JSON::Any
      decode(Selenium.take(LibSel.bidi_network_set_cache_behavior(@handle, next_id, behavior, timeout_ms)))
    end

    # The network.request id out of a network.beforeRequestSent (or other network)
    # event: params.request.request.
    def self.event_request_id(event : JSON::Any) : String?
      event.dig?("params", "request", "request").try(&.as_s?)
    end

    # How many events the bounded queue has dropped since the last call (then
    # resets) — so a consumer knows it missed events.
    def lost_events : Int32
      LibSel.bidi_lost_events(@handle)
    end
  end
end
