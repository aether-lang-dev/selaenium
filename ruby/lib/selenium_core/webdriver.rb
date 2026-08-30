# frozen_string_literal: true

require 'json'
require_relative 'native'

module SeleniumCore
  # Locator strategies. Values match the engine's by_locator strategy strings;
  # ID/NAME/CLASS_NAME are rewritten to CSS in the engine.
  module By
    ID                = 'id'
    NAME              = 'name'
    CSS_SELECTOR      = 'css selector'
    CLASS_NAME        = 'className'
    TAG_NAME          = 'tag name'
    LINK_TEXT         = 'link text'
    PARTIAL_LINK_TEXT = 'partial link text'
    XPATH             = 'xpath'
  end

  # Base for all remote-end errors, carrying the engine's stable W3C error code
  # (0 = success, -1 = transport failure).
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
  class TimeoutError < WebDriverError; end
  class JavascriptError < WebDriverError; end
  class UnknownCommandError < WebDriverError; end

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

  def decode_by(by, value)
    JSON.parse(locator(by, value))
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

    def attribute(name)
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

    def find_element(by, value)
      params = SeleniumCore.decode_by(by, value)
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

  # A WebDriver session over the shared engine.
  class WebDriver
    # Start a Chrome session against a running chromedriver (or Grid).
    #   options: a raw capabilities Hash merged under browserName: chrome.
    def self.chrome(command_executor = 'http://127.0.0.1:9515', options: nil)
      caps = { 'browserName' => 'chrome' }
      caps.merge!(options) if options
      new(command_executor, caps)
    end

    # Convenience: headless-Chrome launch args baked in.
    def self.headless_chrome(command_executor = 'http://127.0.0.1:9515')
      chrome(command_executor, options: {
               'goog:chromeOptions' => {
                 'args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
               }
             })
    end

    def initialize(command_executor, capabilities)
      @handle = Native.call(:open, command_executor)
      raise WebDriverError.new('failed to open session handle', -1) if @handle.nil? || @handle.null?

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
    def find_element(by, value)
      result = execute('findElement', SeleniumCore.decode_by(by, value))
      WebElement.new(self, result.fetch(W3C_ELEMENT_KEY))
    end

    def find_elements(by, value)
      result = execute('findElements', SeleniumCore.decode_by(by, value))
      result.map { |e| WebElement.new(self, e.fetch(W3C_ELEMENT_KEY)) }
    end

    # ---- script ----
    def execute_script(script, *args)
      execute('executeScript', 'script' => script, 'args' => args)
    end

    # ---- windows ----
    def window_handles = execute('getWindowHandles')
    def current_window_handle = execute('getCurrentWindowHandle')
    def maximize_window = (execute('maximizeWindow'); nil)
    def minimize_window = (execute('minimizeWindow'); nil)

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
