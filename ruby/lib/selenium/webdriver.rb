# frozen_string_literal: true

require 'json'
require_relative 'native'

module Selenium
  module WebDriver
    # Locator strategies. Values match the engine's by_locator strategy strings;
    # ID/NAME/CLASS_NAME are rewritten to CSS in the engine. className is sent as
    # the W3C "class name" strategy string.
    module By
      ID                = 'id'
      NAME              = 'name'
      CSS_SELECTOR      = 'css selector'
      CLASS_NAME        = 'class name'
      TAG_NAME          = 'tag name'
      LINK_TEXT         = 'link text'
      PARTIAL_LINK_TEXT = 'partial link text'
      XPATH             = 'xpath'

      # Map the Ruby keyword/symbol finder forms (:id, :class, :css, :link, ...)
      # onto the engine strategy strings. Accepts the authentic Ruby short names
      # (:class -> "class name", :css -> "css selector", :link -> "link text",
      # :partial_link_text, :tag_name) as well as the canonical strings.
      SYMBOLS = {
        id: ID,
        name: NAME,
        class: CLASS_NAME,
        class_name: CLASS_NAME,
        css: CSS_SELECTOR,
        css_selector: CSS_SELECTOR,
        tag_name: TAG_NAME,
        link: LINK_TEXT,
        link_text: LINK_TEXT,
        partial_link_text: PARTIAL_LINK_TEXT,
        xpath: XPATH
      }.freeze

      # Normalize a finder call to (strategy, value). Supports the authentic
      # Ruby forms:
      #   find_element(id: 'x')      -> keyword/hash: one {strategy => value}
      #   find_element(:id, 'x')     -> symbol + value
      #   find_element(By::ID, 'x')  -> canonical strategy string + value
      def self.normalize(how, what = nil)
        if what.nil? && how.is_a?(Hash)
          raise ArgumentError, "expected exactly one locator, got #{how.inspect}" unless how.size == 1

          sym, value = how.first
          [strategy_for(sym), value]
        else
          [strategy_for(how), what]
        end
      end

      # Resolve a strategy token to the engine strategy string. A symbol short
      # name (:id, :class, :css, ...) maps through SYMBOLS; a canonical strategy
      # string ("css selector", "class name", "xpath", ...) passes through
      # unchanged.
      def self.strategy_for(token)
        if token.is_a?(Symbol)
          SYMBOLS.fetch(token) { raise ArgumentError, "unknown locator strategy: #{token.inspect}" }
        else
          token.to_s
        end
      end
    end

    # Base for all remote-end errors, carrying the engine's stable W3C error code
    # (0 = success, -1 = transport failure). Authentic Selenium spells this
    # WebDriverError under Selenium::WebDriver::Error; we keep the flatter
    # Selenium::WebDriver::WebDriverError plus the Error:: aliases below.
    class WebDriverError < StandardError
      attr_reader :code

      def initialize(message = '', code = 0)
        super(message)
        @code = code
      end
    end

    class NoSuchElementError < WebDriverError; end
    class StaleElementReferenceError < WebDriverError; end
    class ElementClickInterceptedError < WebDriverError; end
    class ElementNotInteractableError < WebDriverError; end
    class InvalidSelectorError < WebDriverError; end
    class NoSuchWindowError < WebDriverError; end
    class NoSuchFrameError < WebDriverError; end
    class TimeoutError < WebDriverError; end
    class JavascriptError < WebDriverError; end
    class UnknownCommandError < WebDriverError; end
    class SessionNotCreatedError < WebDriverError; end
    # Raised by the convenience tier (Select/Keys) when an operation isn't valid
    # for the element/key at hand — authentic Selenium spells this
    # Error::UnsupportedOperationError.
    class UnsupportedOperationError < WebDriverError; end

    # Authentic Selenium nests exceptions under Selenium::WebDriver::Error with
    # the *Exception suffix (WebDriverException, NoSuchElementException, ...).
    # We expose that shape as aliases so code written to the real gem's
    # Error::NoSuchElementError / Error::WebDriverError names resolves. The flat
    # names above stay the primary (thrown) classes.
    module Error
      WebDriverError               = ::Selenium::WebDriver::WebDriverError
      NoSuchElementError           = ::Selenium::WebDriver::NoSuchElementError
      StaleElementReferenceError   = ::Selenium::WebDriver::StaleElementReferenceError
      ElementClickInterceptedError = ::Selenium::WebDriver::ElementClickInterceptedError
      ElementNotInteractableError  = ::Selenium::WebDriver::ElementNotInteractableError
      InvalidSelectorError         = ::Selenium::WebDriver::InvalidSelectorError
      NoSuchWindowError            = ::Selenium::WebDriver::NoSuchWindowError
      NoSuchFrameError             = ::Selenium::WebDriver::NoSuchFrameError
      TimeoutError                 = ::Selenium::WebDriver::TimeoutError
      JavascriptError              = ::Selenium::WebDriver::JavascriptError
      UnknownCommandError          = ::Selenium::WebDriver::UnknownCommandError
      SessionNotCreatedError       = ::Selenium::WebDriver::SessionNotCreatedError
      UnsupportedOperationError    = ::Selenium::WebDriver::UnsupportedOperationError
    end

    # Engine integer error codes -> exception class (see core error_code()).
    CODE_TO_EXC = {
      3  => ElementClickInterceptedError,
      4  => ElementNotInteractableError,
      11 => InvalidSelectorError,
      13 => JavascriptError,
      17 => NoSuchElementError,
      21 => TimeoutError,
      23 => StaleElementReferenceError,
      24 => TimeoutError,
      28 => UnknownCommandError
    }.freeze

    W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf'

  # ---- pure engine helpers (no session needed) ----
  module_function

  # "METHOD PATH" route for a command name, or "" if unknown.
  def route(command)
    Native.take_string(Native.call(:route, command))
  end

  # Map a W3C error string to its stable integer code (0 = success).
  def error_code(w3c_error)
    Native.call(:error_code, w3c_error)
  end

  # The W3C {"using","value"} locator JSON for a (by, value) pair.
  def locator(by, value)
    Native.take_string(Native.call(:by_locator, by, value))
  end

  # Decode a finder call into the W3C {"using","value"} params Hash. Accepts the
  # authentic Ruby forms: find_element(id: 'x') (keyword hash), find_element(:id,
  # 'x') (symbol), or find_element(By::ID, 'x') (canonical strategy string).
  def decode_by(how, what = nil)
    strategy, value = By.normalize(how, what)
    JSON.parse(locator(strategy, value))
  end

  # A remote element handle. Methods issue element-scoped commands, passing this
  # element's id as the :id path parameter.
  class WebElement
    attr_reader :id

    def initialize(driver, id)
      @driver = driver
      @id = id
    end

    def click
      exec('clickElement')
    end

    def clear
      exec('clearElement')
    end

    def send_keys(text)
      exec('sendKeysToElement', 'text' => text, 'value' => text.chars)
    end

    def text
      exec('getElementText')
    end

    def tag_name
      exec('getElementTagName')
    end

    # Whether the element is shown (the isDisplayed atom, run in-page by the
    # engine — the visibility algorithm, not a naive style check).
    def displayed?
      !!@driver.send(:atom_bool, :is_displayed, @id)
    end

    # The classic getAttribute(name): property-or-attribute (boolean attrs,
    # live properties like value/checked), via the shared engine atom. Use
    # #dom_attribute for the raw W3C DOM attribute.
    def attribute(name)
      @driver.send(:atom_get_attribute, @id, name)
    end

    # The literal DOM attribute (W3C getDomAttribute), no property fallback.
    def dom_attribute(name)
      exec('getDomAttribute', 'name' => name)
    end

    def property(name)
      exec('getElementProperty', 'name' => name)
    end

    def rect
      exec('getElementRect')
    end

    def enabled?
      !!exec('isElementEnabled')
    end

    def selected?
      !!exec('isElementSelected')
    end

    def find_element(how, what = nil)
      params = WebDriver.decode_by(how, what)
      params['id'] = @id
      result = @driver.send(:execute, 'findChildElement', params)
      WebElement.new(@driver, result.fetch(W3C_ELEMENT_KEY))
    end

    def ==(other)
      other.is_a?(WebElement) && other.id == @id
    end

    private

    def exec(command, params = {})
      params = params.merge('id' => @id)
      @driver.send(:execute, command, params)
    end
  end

  # A WebDriver session over the shared engine. Authentic Selenium names the
  # session class Selenium::WebDriver::Driver; the module-level entry points
  # (Selenium::WebDriver.for / .chrome / .headless_chrome / .local_chrome)
  # construct it.
  class Driver
    # Start a Chrome session against a running chromedriver (or Grid).
    #   options: a raw capabilities Hash merged under browserName: chrome.
    #   ca_path:  pin a private-CA bundle for the transport (before newSession).
    #   insecure: skip TLS verification entirely (self-signed dev/staging Grid).
    def self.chrome(command_executor = 'http://127.0.0.1:9515', options: nil, ca_path: nil, insecure: false)
      caps = { 'browserName' => 'chrome' }
      caps.merge!(options) if options
      new(command_executor, caps, ca_path: ca_path, insecure: insecure)
    end

    # Convenience: headless-Chrome launch args baked in.
    def self.headless_chrome(command_executor = 'http://127.0.0.1:9515', ca_path: nil, insecure: false)
      chrome(command_executor, ca_path: ca_path, insecure: insecure, options: {
               'goog:chromeOptions' => {
                 'args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
               }
             })
    end

    # Chrome session that spawns its OWN chromedriver via the engine — no driver
    # on PATH, no Grid. See {Selenium::WebDriver.local_chrome}.
    def self.local_chrome(options: nil, hint: '', timeout_ms: 15_000, ca_path: nil, insecure: false)
      WebDriver.local_chrome(options: options, hint: hint, timeout_ms: timeout_ms,
                             ca_path: ca_path, insecure: insecure)
    end

    def initialize(command_executor, capabilities, ca_path: nil, insecure: false)
      @handle = Native.call(:open, command_executor)
      raise WebDriverError.new('failed to open session handle', -1) if @handle.nil? || @handle.null?

      # TLS trust config must land on the handle BEFORE newSession (the first
      # request). ca_path pins a private-CA bundle; insecure skips verification
      # entirely (self-signed dev/staging Grid — trust the host out-of-band).
      Native.call(:set_ca, @handle, ca_path) if ca_path && !ca_path.empty?
      Native.call(:set_insecure, @handle, 1) if insecure
      # Request a BiDi channel so #bidi is available on demand; the WebSocket
      # itself opens lazily (a classic script never opens it).
      caps = capabilities.merge('webSocketUrl' => true)
      result = execute('newSession', 'capabilities' => { 'alwaysMatch' => caps })
      @ws_url = (result.is_a?(Hash) ? result.dig('capabilities', 'webSocketUrl') : nil) || ''
      @bidi = nil
    end

    # ---- navigation ----
    def get(url)
      execute('get', 'url' => url)
      nil
    end

    def current_url = execute('getCurrentUrl')
    def title        = execute('getTitle')
    def page_source  = execute('getPageSource')
    def back  = (execute('goBack'); nil)
    def forward = (execute('goForward'); nil)
    def refresh = (execute('refresh'); nil)

    # ---- elements ----
    # Authentic Ruby finder grammar: find_element(id: 'x') (keyword hash),
    # find_element(:id, 'x') (symbol), or find_element(By::ID, 'x').
    def find_element(how, what = nil)
      result = execute('findElement', WebDriver.decode_by(how, what))
      WebElement.new(self, result.fetch(W3C_ELEMENT_KEY))
    end

    def find_elements(how, what = nil)
      result = execute('findElements', WebDriver.decode_by(how, what))
      result.map { |e| WebElement.new(self, e.fetch(W3C_ELEMENT_KEY)) }
    end

    # ---- script ----
    def execute_script(script, *args)
      execute('executeScript', 'script' => script, 'args' => args)
    end

    # Run an async script: the page calls the injected callback (last argument)
    # to yield its value; +args+ precede the callback exactly like execute_script.
    def execute_async_script(script, *args)
      execute('executeAsyncScript', 'script' => script, 'args' => args)
    end

    # ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

    # Relative locators: elements matching +base_css+ filtered by spatial
    # relation to anchors, nearest first. Each filter is a Hash
    # {kind: "above"|"below"|"left"|"right"|"near", sel: "<css>"} (+near+ also
    # accepts +dist+). Returns an Array of WebElement.
    def find_relative(base_css, *filters)
      rc = Native.call(:find_relative, @handle, base_css, JSON.generate(filters))
      result = atom_result(rc) || []
      result.map { |ref| WebElement.new(self, ref.fetch(W3C_ELEMENT_KEY)) }
    end

    # ---- windows ----
    def window_handles = execute('getWindowHandles')
    def current_window_handle = execute('getCurrentWindowHandle')
    def switch_to_window(handle) = (execute('switchToWindow', 'handle' => handle); nil)
    def maximize_window = (execute('maximizeWindow'); nil)
    def minimize_window = (execute('minimizeWindow'); nil)
    def fullscreen_window = (execute('fullscreenWindow'); nil)

    # ---- cookies ----
    def add_cookie(cookie) = (execute('addCookie', 'cookie' => cookie); nil)
    def cookies = execute('getCookies')
    def cookie(name) = execute('getCookie', 'name' => name)
    def delete_cookie(name) = (execute('deleteCookie', 'name' => name); nil)
    def delete_all_cookies = (execute('deleteAllCookies'); nil)

    # ---- window rect ----
    def window_rect = execute('getWindowRect')
    def set_window_rect(rect) = execute('setWindowRect', rect)

    # ---- W3C actions ----
    def perform_actions(actions) = (execute('actions', 'actions' => actions); nil)
    def clear_actions = (execute('clearActions'); nil)

    # A fluent action builder bound to this session — authentic Selenium
    # +driver.action.move_to(el).click.perform+. Queues pointer/key gestures and
    # posts them as one W3C actions sequence via {#perform_actions}. See
    # {Selenium::WebDriver::ActionBuilder}.
    def action(async: false)
      ActionBuilder.new(self, async: async)
    end

    # ---- alerts ----
    def accept_alert = (execute('acceptAlert'); nil)
    def dismiss_alert = (execute('dismissAlert'); nil)
    def alert_text = execute('getAlertText')
    def send_alert_text(text) = (execute('setAlertValue', 'text' => text); nil)

    # ---- timeouts ----
    # Take SECONDS, send milliseconds on the wire — matching mainstream
    # Selenium-Ruby exactly (upstream: Integer(seconds * 1000)). A script's
    # implicitly_wait(10) must mean 10 seconds, not 10 ms.
    def set_page_load_timeout(seconds) = (execute('setTimeout', 'pageLoad' => Integer(seconds * 1000)); nil)
    def set_script_timeout(seconds) = (execute('setTimeout', 'script' => Integer(seconds * 1000)); nil)
    def implicitly_wait(seconds) = (execute('setTimeout', 'implicit' => Integer(seconds * 1000)); nil)

    # ---- screenshots ----
    def screenshot_base64 = execute('screenshot')

    # ---- lifecycle ----
    def session_id
      Native.take_string(Native.call(:session_id, @handle))
    end

    # ---- WebDriver-BiDi ----

    # True if this session negotiated a webSocketUrl (BiDi usable).
    def bidi_available? = !@ws_url.empty?

    # The event-driven BiDi surface for this session, opened lazily over the
    # negotiated webSocketUrl. Raises if the remote end granted no BiDi URL.
    #
    #   driver.bidi.subscribe(BidiEvent::LOG_ENTRY_ADDED)
    #   driver.get(url)
    #   ev = driver.bidi.next_event(BidiEvent::LOG_ENTRY_ADDED, timeout_ms: 5000)
    def bidi
      @bidi ||= begin
        raise WebDriverError.new('BiDi not available: no webSocketUrl negotiated', 0) if @ws_url.empty?

        handle = Native.call(:bidi_open, @ws_url)
        raise WebDriverError.new('BiDi channel failed to open', -1) if handle.nil? || handle.null?

        BiDi.new(handle)
      end
    end

    def quit
      @bidi&.close
      @bidi = nil
      execute('quit')
    ensure
      close_handle
    end

    private

    def close_handle
      return unless @handle && !@handle.null?

      Native.call(:close, @handle)
      @handle = nil
    end

    # The FFI seam: one command by name with a Hash of JSON params. Returns the
    # decoded `value` payload, or raises a typed WebDriverError.
    def execute(command, params = {})
      rc = Native.call(:execute, @handle, command, JSON.generate(params))
      if rc != 0
        code = Native.call(:last_error_code, @handle)
        message = Native.take_string(Native.call(:last_error, @handle))
        if rc == -1 && code.zero?
          raise WebDriverError.new(message.empty? ? 'transport failure' : message, -1)
        end

        exc = CODE_TO_EXC.fetch(code, WebDriverError)
        raise exc.new(message, code)
      end
      raw = Native.take_string(Native.call(:last_value, @handle))
      return nil if raw.empty?

      JSON.parse(raw)
    end

    # Drain last_value after an atom call, raising the same typed WebDriverError
    # that #execute uses on a non-zero return code.
    def atom_result(rc)
      if rc != 0
        code = Native.call(:last_error_code, @handle)
        message = Native.take_string(Native.call(:last_error, @handle))
        if rc == -1 && code.zero?
          raise WebDriverError.new(message.empty? ? 'transport failure' : message, -1)
        end

        exc = CODE_TO_EXC.fetch(code, WebDriverError)
        raise exc.new(message, code)
      end
      raw = Native.take_string(Native.call(:last_value, @handle))
      return nil if raw.empty?

      JSON.parse(raw)
    end

    # An atom verb taking (handle, element_id) whose last_value is a JSON boolean.
    def atom_bool(verb, element_id)
      !!atom_result(Native.call(verb, @handle, element_id))
    end

    # The getAttribute atom: (handle, element_id, name) -> JSON string|null.
    def atom_get_attribute(element_id, name)
      atom_result(Native.call(:get_attribute, @handle, element_id, name))
    end
  end

  # ---- driver orchestration (spawn / adopt a driver process in-binding) ------
  # The engine can resolve, download-or-cache, and launch a browser driver
  # process itself — so a caller needs neither a driver on PATH nor a running
  # Grid. These wrap the driver-handle C ABI (independent of the W3C session
  # handle).

  # A driver process launched by the engine. Owns the driver handle; call #stop
  # to terminate it.
  class DriverProcess
    def initialize(handle)
      @handle = handle
    end

    # The base URL the driver is listening on — pass to {WebDriver}.
    def url
      return '' if @handle.nil? || @handle.null?

      Native.take_string(Native.call(:driver_url, @handle))
    end

    # The driver process id (0 if not running).
    def pid
      return 0 if @handle.nil? || @handle.null?

      Native.call(:driver_pid, @handle)
    end

    def stop
      return if @handle.nil? || @handle.null?

      Native.call(:stop_driver, @handle)
      @handle = nil
    end
  end

  module_function

  # Resolve the local driver binary path for +browser+ without launching it
  # (detect/download/cache as needed). +hint+ pins a version or path; "" auto-
  # detects. Returns "" if none resolvable (offline, no cache).
  def resolve_driver(browser = 'chrome', hint = '')
    Native.take_string(Native.call(:resolve_driver, browser, hint))
  end

  # Launch a driver at an explicit binary path. Returns a {DriverProcess}, or nil
  # if it did not come up in +timeout_ms+.
  def launch_driver(driver_path, timeout_ms: 15_000)
    handle = Native.call(:launch_driver, driver_path, timeout_ms)
    return nil if handle.nil? || handle.null?

    DriverProcess.new(handle)
  end

  # Resolve (detect/download/cache) AND launch a driver for +browser+ in one
  # step. Returns a running {DriverProcess}, or nil if none could be
  # resolved/launched.
  def ensure_driver(browser = 'chrome', hint = '', timeout_ms: 15_000)
    handle = Native.call(:ensure_driver, browser, hint, timeout_ms)
    return nil if handle.nil? || handle.null?

    DriverProcess.new(handle)
  end

  # A Chrome session that spawns its own chromedriver via the engine — no driver
  # on PATH, no Grid. The driver process is stopped on #quit. Raises a
  # {WebDriverError} if the driver can't be resolved/launched.
  def local_chrome(options: nil, hint: '', timeout_ms: 15_000, ca_path: nil, insecure: false)
    LocalChrome.new(options: options, hint: hint, timeout_ms: timeout_ms,
                    ca_path: ca_path, insecure: insecure)
  end

  # Module-level session entry points (authentic Selenium::WebDriver.chrome /
  # .headless_chrome). They delegate to the Driver class constructors so the
  # existing surface keeps working alongside Selenium::WebDriver.for(:chrome).
  def chrome(command_executor = 'http://127.0.0.1:9515', options: nil, ca_path: nil, insecure: false)
    Driver.chrome(command_executor, options: options, ca_path: ca_path, insecure: insecure)
  end

  def headless_chrome(command_executor = 'http://127.0.0.1:9515', ca_path: nil, insecure: false)
    Driver.headless_chrome(command_executor, ca_path: ca_path, insecure: insecure)
  end

  # A Chrome session that spawns its own chromedriver via the engine — no driver
  # on PATH, no Grid. The driver process is stopped on #quit.
  class LocalChrome < Driver
    def initialize(options: nil, hint: '', timeout_ms: 15_000, ca_path: nil, insecure: false)
      @proc = WebDriver.ensure_driver('chrome', hint, timeout_ms: timeout_ms)
      raise WebDriverError.new('could not resolve/launch chromedriver', -1) if @proc.nil?

      caps = { 'browserName' => 'chrome' }
      caps.merge!(options) if options
      super(@proc.url, caps, ca_path: ca_path, insecure: insecure)
    end

    def quit
      super
    ensure
      @proc&.stop
    end
  end

  # The common WebDriver-BiDi event names (W3C spec). Pass to
  # +driver.bidi.subscribe(...)+ and match in +next_event+.
  module BidiEvent
    LOG_ENTRY_ADDED     = 'log.entryAdded'
    CONTEXT_CREATED     = 'browsingContext.contextCreated'
    CONTEXT_DESTROYED   = 'browsingContext.contextDestroyed'
    NAVIGATION_STARTED  = 'browsingContext.navigationStarted'
    DOM_CONTENT_LOADED  = 'browsingContext.domContentLoaded'
    LOAD                = 'browsingContext.load'
    DOWNLOAD_WILL_BEGIN = 'browsingContext.downloadWillBegin'
    BEFORE_REQUEST_SENT = 'network.beforeRequestSent'
    AUTH_REQUIRED = 'network.authRequired'
    RESPONSE_STARTED    = 'network.responseStarted'
    RESPONSE_COMPLETED  = 'network.responseCompleted'
    FETCH_ERROR         = 'network.fetchError'
    REALM_CREATED       = 'script.realmCreated'
    REALM_DESTROYED     = 'script.realmDestroyed'
    MESSAGE             = 'script.message'
  end

  # The event-driven BiDi channel for a session (over the demux C ABI).
  # Commands and events multiplex over one WebSocket via the engine's shape-C
  # demux (single reader -> id-keyed replies + bounded event queue), so replies
  # stay correlated while events stream. Command ids are supplied automatically.
  class BiDi
    def initialize(handle)
      @handle = handle
      @next_id = 1
    end

    # session.subscribe to one or more event names; wait for the ack. Returns the
    # ack payload Hash. Matching events then arrive on the queue (drain via
    # #next_event).
    def subscribe(*events, timeout_ms: 10_000)
      raw = Native.take_string(Native.call(:bidi_subscribe, @handle, next_id, events.join(','), timeout_ms))
      raw.empty? ? {} : JSON.parse(raw)
    end

    def unsubscribe(*events, timeout_ms: 10_000)
      raw = Native.take_string(Native.call(:bidi_unsubscribe, @handle, next_id, events.join(','), timeout_ms))
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Block until an event whose +method+ matches arrives, or timeout. Returns the
    # event Hash, or nil on timeout/close. (Subscribe first.)
    def next_event(method, timeout_ms: 5_000)
      raw = Native.take_string(Native.call(:bidi_wait_event, @handle, method, timeout_ms))
      raw.empty? ? nil : JSON.parse(raw)
    end

    # Issue any BiDi command and return its reply payload Hash. Reaches BiDi
    # methods with no dedicated wrapper (script.evaluate, network.*, ...).
    def command(method, params = {}, timeout_ms: 10_000)
      cid = next_id
      raise WebDriverError.new("BiDi send failed: #{method}", -1) if
        Native.call(:bidi_send, @handle, cid, method, JSON.generate(params)) != 0

      waited = 0
      step = 50
      while waited < timeout_ms
        reply = Native.take_string(Native.call(:bidi_poll_reply, @handle, cid))
        return JSON.parse(reply) unless reply.empty?
        break if Native.call(:bidi_pump, @handle, step) < 0

        waited += step
      end
      raise TimeoutError.new("BiDi command timed out: #{method}", 0)
    end

    # ---- typed convenience commands ----

    # browsingContext.getTree — the browsing contexts (each with a "context" id).
    def get_tree(timeout_ms: 10_000)
      raw = Native.take_string(Native.call(:bidi_get_tree, @handle, next_id, timeout_ms))
      raw.empty? ? {} : JSON.parse(raw)
    end

    # The top-level browsing context id (the anchor for evaluate/navigate), or nil.
    def top_context(timeout_ms: 10_000)
      contexts = get_tree(timeout_ms: timeout_ms).dig('result', 'contexts') || []
      contexts.empty? ? nil : contexts.first['context']
    end

    # script.evaluate an expression in a context's realm, awaiting a returned
    # promise. Returns the reply Hash; dig('result', 'result') is the BiDi-typed
    # value (e.g. {"type" => "number", "value" => 42}). BiDi's richer alternative
    # to execute_script — real realms, promise-awaiting, structured value types.
    def evaluate(expr, context: nil, timeout_ms: 30_000)
      ctx = context || top_context(timeout_ms: timeout_ms)
      raise WebDriverError.new('no browsing context for script.evaluate', 0) unless ctx

      raw = Native.take_string(Native.call(:bidi_script_evaluate, @handle, next_id, expr, ctx, timeout_ms))
      raw.empty? ? {} : JSON.parse(raw)
    end

    # script.evaluate, returning just the unwrapped value (the .value of the
    # BiDi-typed result), or nil if it wasn't a simple value.
    def evaluate_value(expr, context: nil, timeout_ms: 30_000)
      evaluate(expr, context: context, timeout_ms: timeout_ms).dig('result', 'result', 'value')
    end

    # browsingContext.navigate a context to url (wait: complete). Returns the reply.
    def navigate(url, context: nil, timeout_ms: 30_000)
      ctx = context || top_context(timeout_ms: timeout_ms)
      raise WebDriverError.new('no browsing context for navigate', 0) unless ctx

      raw = Native.take_string(Native.call(:bidi_navigate, @handle, next_id, ctx, url, timeout_ms))
      raw.empty? ? {} : JSON.parse(raw)
    end

    # ---- network interception (observe / release / block requests) ----

    # network.addIntercept for a URL pattern (a full parseable URL as a "string"
    # pattern; empty intercepts all) at the given comma-separated phases.
    # Subscribe to the matching network.* event first if you want the
    # paused-request events. Returns the intercept id String, or nil.
    def add_intercept(phases: 'beforeRequestSent', url_pattern: '', timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_add_intercept, @handle, next_id, phases, url_pattern, timeout_ms)
      )
      reply = raw.empty? ? {} : JSON.parse(raw)
      reply.dig('result', 'intercept')
    end

    def remove_intercept(intercept_id, timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_remove_intercept, @handle, next_id, intercept_id, timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Let a paused (intercepted) request proceed unchanged. request_id comes from
    # a network event's +params.request.request+ (see .event_request_id).
    def continue_request(request_id, timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_continue_request, @handle, next_id, request_id, timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Block a paused request (the ad/tracker-blocking case).
    def fail_request(request_id, timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_fail_request, @handle, next_id, request_id, timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Fulfill a paused request with a mock response — the request never hits the
    # network. request_id comes from a network event's +params.request.request+
    # (see .event_request_id). The engine adds Access-Control-Allow-Origin:* to
    # the mock so a cross-origin page can read the body. Returns the reply Hash.
    def provide_response(request_id, status: 200, content_type: '', body: '', timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_provide_response, @handle, next_id, request_id, status, content_type, body,
                    timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Answer an HTTP auth challenge (a paused authRequired request) with
    # credentials — automates basic/digest auth that classic WebDriver can't
    # handle in headless. Returns the reply Hash.
    def continue_with_auth(request_id, username, password, timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_continue_with_auth, @handle, next_id, request_id, username, password, timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # Set the session HTTP cache behavior: "bypass" to disable it (so every
    # request hits the network / an intercept), "default" to restore it.
    # Returns the reply Hash.
    def set_cache_behavior(behavior = 'bypass', timeout_ms: 10_000)
      raw = Native.take_string(
        Native.call(:bidi_network_set_cache_behavior, @handle, next_id, behavior, timeout_ms)
      )
      raw.empty? ? {} : JSON.parse(raw)
    end

    # The network.request id out of a network.beforeRequestSent (or other
    # network) event: +params.request.request+.
    def self.event_request_id(event)
      event.dig('params', 'request', 'request')
    end

    # How many events the bounded queue dropped since the last call (then resets).
    def lost_events = Native.call(:bidi_lost_events, @handle)

    def close
      return unless @handle && !@handle.null?

      Native.call(:bidi_close, @handle)
      @handle = nil
    end

    private

    def next_id
      id = @next_id
      @next_id += 1
      id
    end
  end
  end
end

# The convenience tier (Wait / Select / Keys / ActionBuilder) — loaded after the
# core classes above so it can reference WebElement / Driver / the exception
# classes at definition time.
require_relative 'webdriver/support'
