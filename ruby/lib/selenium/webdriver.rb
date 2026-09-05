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
        relative: 'relative',
        xpath: XPATH
      }.freeze

      # Class-method locator form (mainstream/Java-style By.id('x')) — returns a
      # single-entry {strategy_symbol => value} Hash that find_element / decode_by
      # already accept, so `driver.find_element(By.id('x'))` works ALONGSIDE the
      # existing find_element(By::ID, 'x') / find_element(id: 'x') forms. One
      # convenience method per strategy symbol. :class is skipped — By.class must
      # stay Object#class; use By.class_name for the class-name locator.
      (SYMBOLS.keys - [:class]).each do |sym|
        define_singleton_method(sym) { |value| { sym => value } }
      end

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

    # The remaining W3C/Selenium error taxonomy (upstream rb error.rb). Added as
    # flat Selenium::WebDriver::* classes so `rescue`-by-name works, and aliased
    # under Error:: below (one source of truth). Each subclasses WebDriverError, so
    # code that rescues the base still catches them.
    class DetachedShadowRootError < WebDriverError; end
    class InvalidElementStateError < WebDriverError; end
    class UnknownError < WebDriverError; end
    class NoSuchTargetError < WebDriverError; end
    class NoSuchShadowRootError < WebDriverError; end
    class InvalidCookieDomainError < WebDriverError; end
    class UnableToSetCookieError < WebDriverError; end
    class NoSuchAlertError < WebDriverError; end
    class ScriptTimeoutError < WebDriverError; end
    class MoveTargetOutOfBoundsError < WebDriverError; end
    class InsecureCertificateError < WebDriverError; end
    class InvalidArgumentError < WebDriverError; end
    class NoSuchCookieError < WebDriverError; end
    class UnableToCaptureScreenError < WebDriverError; end
    class InvalidSessionIdError < WebDriverError; end
    class UnexpectedAlertOpenError < WebDriverError; end
    class UnknownMethodError < WebDriverError; end
    class NoSuchDriverError < WebDriverError; end

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
      DetachedShadowRootError      = ::Selenium::WebDriver::DetachedShadowRootError
      InvalidElementStateError     = ::Selenium::WebDriver::InvalidElementStateError
      UnknownError                 = ::Selenium::WebDriver::UnknownError
      NoSuchTargetError            = ::Selenium::WebDriver::NoSuchTargetError
      NoSuchShadowRootError        = ::Selenium::WebDriver::NoSuchShadowRootError
      InvalidCookieDomainError     = ::Selenium::WebDriver::InvalidCookieDomainError
      UnableToSetCookieError       = ::Selenium::WebDriver::UnableToSetCookieError
      NoSuchAlertError             = ::Selenium::WebDriver::NoSuchAlertError
      ScriptTimeoutError           = ::Selenium::WebDriver::ScriptTimeoutError
      MoveTargetOutOfBoundsError   = ::Selenium::WebDriver::MoveTargetOutOfBoundsError
      InsecureCertificateError     = ::Selenium::WebDriver::InsecureCertificateError
      InvalidArgumentError         = ::Selenium::WebDriver::InvalidArgumentError
      NoSuchCookieError            = ::Selenium::WebDriver::NoSuchCookieError
      UnableToCaptureScreenError   = ::Selenium::WebDriver::UnableToCaptureScreenError
      InvalidSessionIdError        = ::Selenium::WebDriver::InvalidSessionIdError
      UnexpectedAlertOpenError     = ::Selenium::WebDriver::UnexpectedAlertOpenError
      UnknownMethodError           = ::Selenium::WebDriver::UnknownMethodError
      NoSuchDriverError            = ::Selenium::WebDriver::NoSuchDriverError
    end

    # Engine integer error codes -> exception class (see core error_code()). The
    # codes are the engine's stable W3C error taxonomy (probe with
    # WebDriver.error_code("<w3c string>")). Codes not listed fall back to the
    # base WebDriverError.
    CODE_TO_EXC = {
      1  => UnknownError,                  # "unknown error" / "no such driver"
      2  => DetachedShadowRootError,
      3  => ElementClickInterceptedError,
      4  => ElementNotInteractableError,
      6  => InsecureCertificateError,
      7  => InvalidArgumentError,
      8  => InvalidCookieDomainError,
      10 => InvalidElementStateError,
      11 => InvalidSelectorError,
      12 => InvalidSessionIdError,
      13 => JavascriptError,
      14 => MoveTargetOutOfBoundsError,
      15 => NoSuchAlertError,
      16 => NoSuchCookieError,
      17 => NoSuchElementError,
      18 => NoSuchFrameError,
      19 => NoSuchShadowRootError,
      20 => NoSuchWindowError,
      21 => ScriptTimeoutError,
      22 => SessionNotCreatedError,
      23 => StaleElementReferenceError,
      24 => TimeoutError,
      25 => UnableToSetCookieError,
      26 => UnableToCaptureScreenError,
      27 => UnexpectedAlertOpenError,
      28 => UnknownCommandError,
      29 => UnknownMethodError,
      30 => UnsupportedOperationError
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

  # Serialize execute_script args, encoding any WebElement as its W3C
  # element-reference object ({element-key => id}) so the engine forwards a live
  # element handle. Recurses into Arrays and Hashes (mainstream _wrap_args).
  def wrap_script_args(args)
    args.map { |a| encode_script_arg(a) }
  end

  def encode_script_arg(arg)
    case arg
    when WebElement then { W3C_ELEMENT_KEY => arg.id }
    when Array      then arg.map { |x| encode_script_arg(x) }
    when Hash       then arg.transform_values { |v| encode_script_arg(v) }
    else arg
    end
  end

  # Normalize a Chrome +options+ argument to a raw capabilities Hash. Accepts a
  # mainstream Chrome::Options object (anything answering #to_capabilities) or a
  # raw capabilities Hash (back-compat), or nil.
  def options_to_caps(options)
    return {} if options.nil?
    return options.to_capabilities if options.respond_to?(:to_capabilities)

    options
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

    # Variadic (mainstream): accepts Strings, key Symbols (via Keys), and Arrays
    # (chords), joined into one keystroke sequence through Keys.encode. W3C expects
    # {"text": full, "value": [chars...]} — send both for broad driver
    # compatibility.
    #
    #   element.send_keys "foo"
    #   element.send_keys "tet", :arrow_left, "s"
    #   element.send_keys [:control, 'a'], :space
    def send_keys(*args)
      keys = Keys.encode(args).join
      exec('sendKeysToElement', 'text' => keys, 'value' => keys.chars)
    end
    alias send_key send_keys

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

    # Plural child finder (mainstream Element#find_elements).
    def find_elements(how, what = nil)
      params = WebDriver.decode_by(how, what)
      params['id'] = @id
      result = @driver.send(:execute, 'findChildElements', params)
      result.map { |e| WebElement.new(@driver, e.fetch(W3C_ELEMENT_KEY)) }
    end

    # The computed value of a CSS property (mainstream Element#css_value / #style).
    def css_value(prop)
      exec('getElementValueOfCssProperty', 'propertyName' => prop)
    end
    alias style css_value

    # The element's {"x","y"} position (derived from the W3C rect).
    def location
      r = rect
      { 'x' => r['x'], 'y' => r['y'] }
    end

    # The element's {"height","width"} (derived from the W3C rect).
    def size
      r = rect
      { 'height' => r['height'], 'width' => r['width'] }
    end

    # Submit the form containing this element (mainstream: walks up to the
    # enclosing <form> and dispatches submit, in-page — the engine exposes no
    # submitElement command).
    def submit
      script = <<~JS
        /* submitForm */var form = arguments[0];
        while (form.nodeName != "FORM" && form.parentNode) { form = form.parentNode; }
        if (!form) { throw Error('Unable to find containing form element'); }
        if (!form.ownerDocument) { throw Error('Unable to find owning document'); }
        var e = form.ownerDocument.createEvent('Event');
        e.initEvent('submit', true, true);
        if (form.dispatchEvent(e)) { HTMLFormElement.prototype.submit.call(form) }
      JS
      @driver.execute_script(script, self)
    rescue JavascriptError => e
      raise WebDriverError.new('To submit an element, it must be nested inside a form element', e.code)
    end

    # A base64-encoded PNG screenshot of this element (mainstream: returns the
    # base64 string).
    def screenshot
      exec('takeElementScreenshot')
    end

    def ==(other)
      other.is_a?(WebElement) && other.id == @id
    end
    alias eql? ==

    def hash
      @id.hash
    end

    # Sugar mirroring mainstream Element: first/all finders and [] attribute
    # shorthand.
    alias first find_element
    alias all find_elements
    alias [] attribute

    private

    def exec(command, params = {})
      params = params.merge('id' => @id)
      @driver.send(:execute, command, params)
    end
  end

  # Canonical mainstream name: authentic Selenium calls the remote-element class
  # Selenium::WebDriver::Element. This binding's primary class is WebElement (the
  # Python/Java spelling); alias so BOTH constants resolve to the same class and
  # `is_a?(Element)` / `is_a?(WebElement)` agree.
  Element = WebElement

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
      caps.merge!(WebDriver.options_to_caps(options)) if options
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

    # Construct a session for +browser+ (mainstream Selenium::WebDriver.for /
    # Driver.for). Only :chrome (and its aliases) is served by this binding;
    # delegates to the existing .chrome constructor. +opts+ is passed through
    # (e.g. options:, ca_path:, insecure:, command_executor:).
    def self.for(browser, opts = {})
      case browser
      when :chrome, :chrome_headless_shell, :headless_chrome
        executor = opts.delete(:command_executor)
        if executor
          chrome(executor, **opts)
        else
          local_chrome(**opts)
        end
      else
        raise ArgumentError, "unknown driver: #{browser.inspect}"
      end
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
    # WebElement args are encoded as their W3C element-reference object so the
    # engine forwards a live element handle (mainstream behavior — a script can
    # take an element as arguments[n]).
    def execute_script(script, *args)
      execute('executeScript', 'script' => script, 'args' => WebDriver.wrap_script_args(args))
    end

    # Run an async script: the page calls the injected callback (last argument)
    # to yield its value; +args+ precede the callback exactly like execute_script.
    def execute_async_script(script, *args)
      execute('executeAsyncScript', 'script' => script, 'args' => WebDriver.wrap_script_args(args))
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

    # ---- mainstream facades (issue W3C commands via #execute) ----------------
    # Authentic Selenium reaches navigation/focus/cookies/timeouts/windows
    # through facade objects on Driver; the flat methods above stay available.

    # @return [Navigation] driver.navigate.to(url) / .back / .forward / .refresh
    def navigate
      @navigate ||= Navigation.new(self)
    end

    # @return [TargetLocator] driver.switch_to.window(h) / .frame(id) /
    #   .parent_frame / .default_content / .new_window / .active_element / .alert
    def switch_to
      @switch_to ||= TargetLocator.new(self)
    end

    # @return [Manager] driver.manage.add_cookie / .timeouts / .window / ...
    def manage
      @manage ||= Manager.new(self)
    end

    # ---- session status / metadata ----
    # Remote-end readiness + meta info (W3C GET /status).
    def status = execute('getStatus')

    # The session capabilities the remote end returned at newSession.
    def capabilities = @caps

    # ---- print to PDF ----
    # Render the current page to a PDF, returned base64-encoded. +opts+ are the
    # W3C print parameters (e.g. landscape:, page_ranges:, scale:).
    def print_page(**opts)
      execute('printPage', stringify_keys(opts))
    end

    # Render the current page to a PDF and write the decoded bytes to +path+.
    def save_print_page(path, **opts)
      require 'base64'
      File.binwrite(path, Base64.decode64(print_page(**opts)))
      path
    end

    # ---- screenshots (mainstream TakesScreenshot surface) ----
    # A screenshot in +format+ (:base64 or :png). full_page is accepted for
    # signature parity (the classic endpoint has no full-page mode).
    def screenshot_as(format, full_page: false)
      case format
      when :base64
        execute('screenshot')
      when :png
        require 'base64'
        Base64.decode64(execute('screenshot'))
      else
        raise UnsupportedOperationError, "unsupported format: #{format.inspect}"
      end
    end

    # Save a PNG screenshot of the viewport to +path+ (mainstream save_screenshot).
    def save_screenshot(path, full_page: false)
      File.binwrite(path, screenshot_as(:png, full_page: full_page))
      path
    end

    # ---- finder sugar (mainstream) ----
    alias first find_element
    alias all find_elements

    # driver['id'] or driver[tag_name: 'div'] — id string/symbol, else a locator.
    def [](sel)
      sel = { id: sel } if sel.is_a?(String) || sel.is_a?(Symbol)
      find_element(sel)
    end

    # ---- windows ----
    def window_handles = execute('getWindowHandles')
    def current_window_handle = execute('getCurrentWindowHandle')
    # Mainstream spelling (singular); current_window_handle stays as an alias.
    def window_handle = execute('getCurrentWindowHandle')
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

    # Close the current window (not the whole session). Mainstream Driver#close.
    def close = execute('close')

    private

    # Symbolize->string top-level keys (for kwargs passed to W3C command params).
    def stringify_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

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
    # Mainstream's documented low-level entrypoint: driver.execute(command,
    # params) issues a W3C command by name and returns its parsed value (the
    # engine already unwraps the {"value": ...} envelope). Public so the facades
    # and callers reach the seam; WebElement still uses it internally.
    public :execute

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
      caps.merge!(WebDriver.options_to_caps(options)) if options
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

  # ==========================================================================
  # Mainstream facade objects (rb/lib/selenium/webdriver/common/*). Each wraps a
  # Driver and issues W3C commands through Driver#execute — the same seam the
  # flat Driver methods use. Names/signatures/hierarchy copied from upstream;
  # only the bottom is rewired to this binding. These are ADDITIVE — the flat
  # Driver methods (get, back, switch_to_window, add_cookie, ...) stay.
  # ==========================================================================

  # driver.navigate -> Navigation (upstream common/navigation.rb).
  class Navigation
    def initialize(driver)
      @driver = driver
    end

    def to(url) = (@driver.execute('get', 'url' => url); nil)
    def back = (@driver.execute('goBack'); nil)
    def forward = (@driver.execute('goForward'); nil)
    def refresh = (@driver.execute('refresh'); nil)
  end # Navigation

  # driver.switch_to -> TargetLocator (upstream common/target_locator.rb).
  class TargetLocator
    def initialize(driver)
      @driver = driver
    end

    # Switch to the frame with the given id (Integer index, name/id String looked
    # up as an element, a frame WebElement, or nil for the top-level document).
    def frame(id)
      id = { WebDriver::W3C_ELEMENT_KEY => id.id } if id.is_a?(WebElement)
      @driver.execute('switchToFrame', 'id' => id)
      nil
    end

    def parent_frame = (@driver.execute('switchToFrameParent'); nil)

    # Switch to a new top-level browsing context. type is :tab or :window.
    def new_window(type = :tab)
      unless %i[tab window].include?(type)
        raise ArgumentError, "Valid types are :tab and :window, received: #{type.inspect}"
      end

      handle = @driver.execute('newWindow', 'type' => type.to_s)['handle']
      window(handle)
      handle
    end

    def window(id) = (@driver.execute('switchToWindow', 'handle' => id); nil)

    # The element with focus (or BODY if nothing has focus).
    def active_element
      result = @driver.execute('getActiveElement')
      WebElement.new(@driver, result.fetch(W3C_ELEMENT_KEY))
    end

    def default_content = (@driver.execute('switchToFrame', 'id' => nil); nil)

    # The currently active modal dialog (upstream returns an Alert, touching its
    # text first to fail fast if none is present).
    def alert = Alert.new(@driver)
  end # TargetLocator

  # driver.switch_to.alert -> Alert (upstream common/alert.rb).
  class Alert
    def initialize(driver)
      @driver = driver
      # fail fast if the alert doesn't exist (mainstream behavior)
      @driver.execute('getAlertText')
    end

    def text = @driver.execute('getAlertText')
    def accept = (@driver.execute('acceptAlert'); nil)
    def dismiss = (@driver.execute('dismissAlert'); nil)

    def send_keys(keys)
      @driver.execute('setAlertValue', 'text' => keys, 'value' => keys.chars)
      nil
    end
  end # Alert

  # driver.manage -> Manager (upstream common/manager.rb) — cookies, timeouts,
  # window.
  class Manager
    def initialize(driver)
      @driver = driver
    end

    # Add a cookie. Accepts a Hash with either symbol (:name/:value/:same_site/
    # :http_only/:expires) or string keys; normalizes the camelCase W3C fields.
    def add_cookie(opts = {})
      cookie = normalize_cookie(opts)
      raise ArgumentError, 'name is required' unless cookie['name']
      raise ArgumentError, 'value is required' unless cookie['value']

      cookie['secure'] = false unless cookie.key?('secure')
      @driver.execute('addCookie', 'cookie' => cookie)
      nil
    end

    def cookie_named(name) = @driver.execute('getCookie', 'name' => name)
    def all_cookies = @driver.execute('getCookies')

    def delete_cookie(name)
      raise ArgumentError, 'Cookie name cannot be null or empty' if name.nil? || name.to_s.strip.empty?

      @driver.execute('deleteCookie', 'name' => name)
      nil
    end

    def delete_all_cookies = (@driver.execute('deleteAllCookies'); nil)

    def timeouts = @timeouts ||= Timeouts.new(@driver)
    def window = @window ||= Window.new(@driver)

    private

    def normalize_cookie(opts)
      map = { same_site: 'sameSite', http_only: 'httpOnly', expires: 'expiry' }
      opts.each_with_object({}) do |(k, v), h|
        key = map[k.to_sym] || k.to_s
        v = v.to_i if key == 'expiry' && v.respond_to?(:to_i)
        h[key] = v
      end
    end
  end # Manager

  # driver.manage.timeouts -> Timeouts (upstream common/timeouts.rb). Setters
  # take SECONDS and send milliseconds on the wire, matching mainstream exactly.
  class Timeouts
    def initialize(driver)
      @driver = driver
    end

    def implicit_wait=(seconds)
      @driver.execute('setTimeout', 'implicit' => Integer(seconds * 1000))
    end

    def script=(seconds)
      @driver.execute('setTimeout', 'script' => Integer(seconds * 1000))
    end

    def page_load=(seconds)
      @driver.execute('setTimeout', 'pageLoad' => Integer(seconds * 1000))
    end
  end # Timeouts

  # driver.manage.window -> Window (upstream common/window.rb).
  class Window
    def initialize(driver)
      @driver = driver
    end

    def maximize = (@driver.execute('maximizeWindow'); nil)
    def minimize = (@driver.execute('minimizeWindow'); nil)
    def full_screen = (@driver.execute('fullscreenWindow'); nil)

    def rect = @driver.execute('getWindowRect')

    # rect= accepts a Rectangle-like object (#x/#y/#width/#height) or a Hash.
    def rect=(rectangle)
      @driver.execute('setWindowRect', rect_params(rectangle))
    end

    # The {"width","height"} of the current window.
    def size
      r = rect
      { 'width' => r['width'], 'height' => r['height'] }
    end

    # size= accepts a Dimension-like object (#width/#height) or a Hash.
    def size=(dimension)
      w, h = dimension_wh(dimension)
      @driver.execute('setWindowRect', 'width' => Integer(w), 'height' => Integer(h))
    end

    # The {"x","y"} top-left position of the current window.
    def position
      r = rect
      { 'x' => r['x'], 'y' => r['y'] }
    end

    # position= accepts a Point-like object (#x/#y) or a Hash.
    def position=(point)
      x, y = point_xy(point)
      @driver.execute('setWindowRect', 'x' => Integer(x), 'y' => Integer(y))
    end

    private

    def rect_params(rectangle)
      if rectangle.is_a?(Hash)
        rectangle.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      else
        { 'x' => rectangle.x, 'y' => rectangle.y,
          'width' => rectangle.width, 'height' => rectangle.height }
      end
    end

    def dimension_wh(dim)
      dim.is_a?(Hash) ? [dim[:width] || dim['width'], dim[:height] || dim['height']] : [dim.width, dim.height]
    end

    def point_xy(pt)
      pt.is_a?(Hash) ? [pt[:x] || pt['x'], pt[:y] || pt['y']] : [pt.x, pt.y]
    end
  end # Window

  # Chrome::Options (upstream chrome/options.rb + chromium/options.rb, subset).
  # Collect --flags via #add_argument, experimental options via
  # #add_experimental_option / #add_option, a binary= path, and top-level caps
  # via #add_option(hash); #to_capabilities assembles the W3C caps Hash with a
  # goog:chromeOptions block. Selenium::WebDriver.chrome(options: <Options>)
  # applies #to_capabilities.
  module Chrome
    class Options
      KEY = 'goog:chromeOptions'
      BROWSER = 'chrome'

      attr_accessor :binary
      attr_reader :arguments, :experimental_options

      def initialize(args: [], binary: nil, **)
        @arguments = args.dup
        @binary = binary
        @experimental_options = {}
        @extra_caps = {}
      end

      # Add a command-line argument (mainstream add_argument).
      def add_argument(arg)
        @arguments << arg
        self
      end

      # Set an experimental option nested under goog:chromeOptions (mainstream
      # add_experimental_option).
      def add_experimental_option(name, value)
        @experimental_options[name.to_s] = value
        self
      end

      # add_option: with a two-arg (name, value) or a single Hash, sets an
      # experimental/browser option under goog:chromeOptions (mainstream Ruby
      # Options#add_option delegates to the vendor block).
      def add_option(name, value = nil)
        name, value = name.first if value.nil? && name.is_a?(Hash)
        add_experimental_option(name, value)
      end

      # Assemble the W3C capabilities Hash: browserName plus the goog:chromeOptions
      # block (experimental options, binary, args).
      def to_capabilities
        chrome_options = @experimental_options.dup
        chrome_options['binary'] = @binary if @binary
        chrome_options['args'] = @arguments
        { 'browserName' => BROWSER }.merge(@extra_caps).merge(KEY => chrome_options)
      end
      alias as_json to_capabilities
    end # Options
  end # Chrome
  end
end

# The convenience tier (Wait / Select / Keys / ActionBuilder) — loaded after the
# core classes above so it can reference WebElement / Driver / the exception
# classes at definition time.
require_relative 'webdriver/support'
