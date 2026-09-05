# frozen_string_literal: true

# The convenience tier for the Ruby binding: Wait (WebDriverWait), Select,
# ActionBuilder (Actions), and Keys. These carry NO protocol logic of their own —
# they bottom out on the same command seam the rest of the binding uses:
#   * find_element / find_elements, click, text, attribute, property, selected?,
#     enabled?, tag_name on WebElement/Driver, and
#   * Driver#perform_actions (the raw W3C "actions" command).
#
# The engine holds no thread, so the poll-loop in Wait lives here. Structure,
# method names and — for Keys — the exact code points mirror mainstream
# Selenium-Ruby (rb/lib/selenium/webdriver/common/{wait,keys,action_builder}.rb
# and support/select.rb); only the bottom is rewired to this binding's seam.

module Selenium
  module WebDriver
    # Special keys. The KEYS symbol map holds the W3C WebDriver Unicode
    # private-use code points for non-text keys; the values are copied verbatim
    # from mainstream Selenium-Ruby so a script written to the real gem's
    # Keys[:enter] / Keys.encode contract behaves identically. The UPPERCASE
    # constants (Keys::ENTER, ...) point at the same code points for cross-binding
    # parity with the Python/Java/JS Keys.ENTER form.
    #
    # @see Element#send_keys
    module Keys
      KEYS = {
        null: "",
        cancel: "",
        help: "",
        backspace: "",
        tab: "",
        clear: "",
        return: "",
        enter: "",
        shift: "",
        left_shift: "",
        control: "",
        left_control: "",
        alt: "",
        left_alt: "",
        pause: "",
        escape: "",
        space: "",
        page_up: "",
        page_down: "",
        end: "",
        home: "",
        left: "",
        arrow_left: "",
        up: "",
        arrow_up: "",
        right: "",
        arrow_right: "",
        down: "",
        arrow_down: "",
        insert: "",
        delete: "",
        semicolon: "",
        equals: "",
        numpad0: "",
        numpad1: "",
        numpad2: "",
        numpad3: "",
        numpad4: "",
        numpad5: "",
        numpad6: "",
        numpad7: "",
        numpad8: "",
        numpad9: "",
        multiply: "",
        add: "",
        separator: "",
        subtract: "",
        decimal: "",
        divide: "",
        numpad_multiply: "",
        numpad_add: "",
        numpad_comma: "",
        numpad_subtract: "",
        numpad_decimal: "",
        numpad_divide: "",
        numpad_enter: "",
        f1: "",
        f2: "",
        f3: "",
        f4: "",
        f5: "",
        f6: "",
        f7: "",
        f8: "",
        f9: "",
        f10: "",
        f11: "",
        f12: "",
        meta: "",
        command: "", # alias
        left_meta: "", # alias
        zenkaku_hankaku: "",
        right_shift: "",
        right_control: "",
        right_alt: "",
        right_meta: "",
        options: "",
        function: "", # macOS Function key, same as right_control
        numpad_page_up: "",
        numpad_page_down: "",
        numpad_end: "",
        numpad_home: "",
        numpad_left: "",
        numpad_up: "",
        numpad_right: "",
        numpad_down: "",
        numpad_insert: "",
        numpad_delete: ""
      }.freeze

      # UPPERCASE constant form (Keys::ENTER) for parity with the Python/Java/JS
      # bindings' Keys.ENTER. Each maps to the identical code point in KEYS, so
      # Keys::ENTER == Keys[:enter].
      NULL      = KEYS[:null]
      CANCEL    = KEYS[:cancel]
      HELP      = KEYS[:help]
      BACKSPACE = KEYS[:backspace]
      BACK_SPACE = KEYS[:backspace]
      TAB       = KEYS[:tab]
      CLEAR     = KEYS[:clear]
      RETURN    = KEYS[:return]
      ENTER     = KEYS[:enter]
      SHIFT     = KEYS[:shift]
      LEFT_SHIFT = KEYS[:left_shift]
      CONTROL   = KEYS[:control]
      LEFT_CONTROL = KEYS[:left_control]
      ALT       = KEYS[:alt]
      LEFT_ALT  = KEYS[:left_alt]
      PAUSE     = KEYS[:pause]
      ESCAPE    = KEYS[:escape]
      SPACE     = KEYS[:space]
      PAGE_UP   = KEYS[:page_up]
      PAGE_DOWN = KEYS[:page_down]
      # NB: no END constant — END is a Ruby reserved word (END {} block); use
      # Keys[:end] for the End key.
      HOME      = KEYS[:home]
      LEFT      = KEYS[:left]
      ARROW_LEFT = KEYS[:arrow_left]
      UP        = KEYS[:up]
      ARROW_UP  = KEYS[:arrow_up]
      RIGHT     = KEYS[:right]
      ARROW_RIGHT = KEYS[:arrow_right]
      DOWN      = KEYS[:down]
      ARROW_DOWN = KEYS[:arrow_down]
      INSERT    = KEYS[:insert]
      DELETE    = KEYS[:delete]
      SEMICOLON = KEYS[:semicolon]
      EQUALS    = KEYS[:equals]
      MULTIPLY  = KEYS[:multiply]
      ADD       = KEYS[:add]
      SEPARATOR = KEYS[:separator]
      SUBTRACT  = KEYS[:subtract]
      DECIMAL   = KEYS[:decimal]
      DIVIDE    = KEYS[:divide]
      F1        = KEYS[:f1]
      F2        = KEYS[:f2]
      F3        = KEYS[:f3]
      F4        = KEYS[:f4]
      F5        = KEYS[:f5]
      F6        = KEYS[:f6]
      F7        = KEYS[:f7]
      F8        = KEYS[:f8]
      F9        = KEYS[:f9]
      F10       = KEYS[:f10]
      F11       = KEYS[:f11]
      F12       = KEYS[:f12]
      META      = KEYS[:meta]
      COMMAND   = KEYS[:command]

      # @api private
      # The code point for a symbol key name (:enter, :control, ...).
      def self.[](key)
        return KEYS[key] if KEYS[key]

        raise UnsupportedOperationError, "no such key #{key.inspect}"
      end

      # @api private
      # Normalize a list of send_keys arguments (Strings, key Symbols, or Arrays
      # of them for a chord) into an Array of Strings — the authentic Keys.encode.
      def self.encode(keys)
        keys.map { |key| encode_key(key) }
      end

      # @api private
      def self.encode_key(key)
        case key
        when Symbol
          Keys[key]
        when Array
          key = key.map { |e| e.is_a?(Symbol) ? Keys[e] : e }.join
          key << Keys[:null]
          key
        else
          key.to_s
        end
      end
    end # Keys

    # Explicit wait. Authentic Selenium-Ruby Selenium::WebDriver::Wait — poll a
    # block until it returns a truthy value (or times out). The engine holds no
    # thread, so this loop lives in the binding: it issues single commands each
    # tick, exactly like the reference implementation.
    #
    #   wait = Selenium::WebDriver::Wait.new(timeout: 10)
    #   el   = wait.until { driver.find_element(id: 'later') }
    #
    # WebDriverWait is provided as an alias for the Python/Java-style spelling.
    class Wait
      DEFAULT_TIMEOUT  = 5
      # Seconds between polls. Matches the ~0.5s poll cadence of this port's
      # reference bindings (mainstream Ruby historically used 0.2).
      DEFAULT_INTERVAL = 0.5

      # @param [Hash] opts
      # @option opts [Numeric] :timeout (5) seconds before timing out
      # @option opts [Numeric] :interval (0.5) seconds to sleep between polls
      # @option opts [String]  :message exception message on timeout
      # @option opts [Array, Exception] :ignore exceptions swallowed while polling
      #   (default: NoSuchElementError)
      def initialize(opts = {})
        @timeout  = opts.fetch(:timeout, DEFAULT_TIMEOUT)
        @interval = opts.fetch(:interval, DEFAULT_INTERVAL)
        @message  = opts[:message]
        @ignored  = Array(opts[:ignore] || NoSuchElementError)
      end

      # Poll the block every :interval seconds until it yields a truthy value,
      # which is returned. Raises TimeoutError once :timeout seconds elapse.
      #
      # @raise [TimeoutError]
      # @return [Object] the block's truthy result
      def until
        end_time = current_time + @timeout
        last_error = nil

        until current_time > end_time
          begin
            result = yield
            return result if result
          rescue *@ignored => e # rubocop:disable Naming/RescuedExceptionsVariableName
            last_error = e
          end

          sleep @interval
        end

        msg = @message ? @message.dup : "timed out after #{@timeout} seconds"
        msg = +msg
        msg << " (#{last_error.message})" if last_error
        raise TimeoutError, msg
      end

      # Poll until the block yields a falsy value (or raises an ignored
      # exception); returns true. Raises TimeoutError on timeout.
      def until_not
        end_time = current_time + @timeout

        until current_time > end_time
          begin
            return true unless yield
          rescue *@ignored
            return true
          end

          sleep @interval
        end

        raise TimeoutError, @message ? @message.dup : "timed out after #{@timeout} seconds"
      end

      private

      def current_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end # Wait

    # Python/Java-style spelling: WebDriverWait.new(driver, timeout).until { ... }.
    # Wraps Wait so the driver is captured (the block/condition may take it or
    # close over it — matching mainstream's WebDriverWait(driver, n).until(cond)).
    class WebDriverWait
      def initialize(driver, timeout, interval: Wait::DEFAULT_INTERVAL, message: nil, ignore: nil)
        @driver = driver
        @wait = Wait.new(timeout: timeout, interval: interval, message: message, ignore: ignore)
      end

      # Poll +method+ (a callable taking the driver) or a block until truthy.
      def until(method = nil, &block)
        condition = method || block
        @wait.until { condition.call(@driver) }
      end

      def until_not(method = nil, &block)
        condition = method || block
        @wait.until_not { condition.call(@driver) }
      end
    end # WebDriverWait

    # A fluent W3C action builder. Queue pointer/key gestures with chained calls,
    # then #perform posts the whole sequence in ONE actions command via
    # Driver#perform_actions. This mirrors mainstream ActionChains/ActionBuilder
    # semantics but emits the W3C payload directly (this binding has no per-device
    # InputDevice classes — the wire shape is built here and handed to the engine).
    #
    #   driver.action.move_to(menu).click(item).perform
    #   driver.action.key_down(Keys::SHIFT).send_keys('abc').key_up(Keys::SHIFT).perform
    #
    # Actions / ActionChains are provided as aliases.
    class ActionBuilder
      W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf'

      def initialize(driver, async: false)
        @driver = driver
        @async = async
        @pointer = [] # pointer device tick list
        @key = []     # key device tick list
      end

      # ---- pointer gestures ----

      def move_to(element, x: 0, y: 0)
        @pointer << { 'type' => 'pointerMove', 'duration' => 100, 'x' => x, 'y' => y,
                      'origin' => { W3C_ELEMENT_KEY => element.id } }
        sync_lengths
        self
      end
      alias move_to_element move_to

      # Move to a viewport offset (no element origin) — origin defaults to viewport.
      def move_by(x, y)
        @pointer << { 'type' => 'pointerMove', 'duration' => 100, 'x' => x, 'y' => y,
                      'origin' => 'viewport' }
        sync_lengths
        self
      end
      alias move_by_offset move_by

      def click(element = nil)
        move_to(element) if element
        press_and_release(0)
        self
      end

      def context_click(element = nil)
        move_to(element) if element
        press_and_release(2)
        self
      end

      def double_click(element = nil)
        move_to(element) if element
        2.times { press_and_release(0) }
        self
      end

      def click_and_hold(element = nil)
        move_to(element) if element
        @pointer << { 'type' => 'pointerDown', 'button' => 0 }
        sync_lengths
        self
      end

      def release(element = nil)
        move_to(element) if element
        @pointer << { 'type' => 'pointerUp', 'button' => 0 }
        sync_lengths
        self
      end

      def drag_and_drop(source, target)
        click_and_hold(source)
        move_to(target)
        release
        self
      end

      # ---- key gestures ----

      def key_down(key, element = nil)
        click(element) if element
        @key << { 'type' => 'keyDown', 'value' => key }
        sync_lengths
        self
      end

      def key_up(key, _element = nil)
        @key << { 'type' => 'keyUp', 'value' => key }
        sync_lengths
        self
      end

      # send_keys accepts Strings, key Symbols (via Keys), and Arrays; each
      # character becomes a keyDown/keyUp pair.
      def send_keys(*keys)
        Keys.encode(keys).each do |chunk|
          chunk.each_char do |ch|
            @key << { 'type' => 'keyDown', 'value' => ch }
            @key << { 'type' => 'keyUp', 'value' => ch }
          end
        end
        sync_lengths
        self
      end

      def pause(seconds = 0)
        @pointer << { 'type' => 'pause', 'duration' => (seconds * 1000).to_i }
        sync_lengths
        self
      end

      # ---- terminal ----

      # The assembled W3C actions array (what #perform posts). Exposed so callers
      # and tests can inspect the exact wire shape without side effects.
      def to_a
        actions = []
        if @pointer.any? { |a| a['type'] != 'pause' }
          actions << { 'type' => 'pointer', 'id' => 'mouse',
                       'parameters' => { 'pointerType' => 'mouse' },
                       'actions' => @pointer }
        end
        if @key.any? { |a| a['type'] != 'pause' }
          actions << { 'type' => 'key', 'id' => 'keyboard', 'actions' => @key }
        end
        actions
      end

      # Post the queued gestures as one W3C actions command, then reset.
      def perform
        actions = to_a
        @driver.perform_actions(actions) unless actions.empty?
        clear_all_actions
        nil
      end

      def clear_all_actions
        @pointer = []
        @key = []
        self
      end

      private

      def press_and_release(button)
        @pointer << { 'type' => 'pointerDown', 'button' => button }
        @pointer << { 'type' => 'pointerUp', 'button' => button }
        sync_lengths
      end

      # W3C requires every device's tick list to be the same length; pad the
      # shorter one with zero-duration pauses so ticks on the two devices stay
      # aligned (skipped in async mode, where devices run independently).
      def sync_lengths
        return if @async

        n = [@pointer.length, @key.length].max
        @pointer << { 'type' => 'pause', 'duration' => 0 } while @pointer.length < n
        @key << { 'type' => 'pause', 'duration' => 0 } while @key.length < n
      end
    end # ActionBuilder

    # Authentic aliases: Actions is the class name some scripts reach for, and
    # ActionChains is the Python/JS spelling.
    Actions = ActionBuilder
    ActionChains = ActionBuilder

    # The <select> dropdown helper. Authentic Selenium-Ruby lives at
    # Selenium::WebDriver::Support::Select; drives a <select> WebElement by
    # finding and clicking its <option> children through this binding's seam.
    #
    #   Selenium::WebDriver::Support::Select.new(el).select_by(:text, 'Spain')
    module Support
      class Select
        # @param [WebElement] element the <select> element to wrap
        def initialize(element)
          tag_name = element.tag_name
          raise ArgumentError, "unexpected tag name #{tag_name.inspect}" unless tag_name.casecmp('select').zero?

          @element = element
          multi = element.attribute('multiple')
          @multi = ![nil, 'false'].include?(multi)
        end

        # @return [Boolean] whether multiple options may be selected
        def multiple?
          @multi
        end

        # @return [Array<WebElement>] all <option> children
        def options
          @element.find_elements(tag_name: 'option')
        end

        # @return [Array<WebElement>] the selected options
        def selected_options
          options.select(&:selected?)
        end

        # @raise [NoSuchElementError] if nothing is selected
        # @return [WebElement] the first selected option
        def first_selected_option
          option = options.find(&:selected?)
          return option if option

          raise NoSuchElementError, 'no options are selected'
        end

        # Select an option by :text (visible text), :value, or :index.
        #
        # @param [:text, :value, :index] how
        # @param [String, Integer] what
        def select_by(how, what)
          case how
          when :text  then select_by_text(what)
          when :value then select_by_value(what)
          when :index then select_by_index(what)
          else raise ArgumentError, "can't select options by #{how.inspect}"
          end
        end

        # Deselect an option by :text, :value, or :index (multi-select only).
        def deselect_by(how, what)
          case how
          when :text  then deselect_by_text(what)
          when :value then deselect_by_value(what)
          when :index then deselect_by_index(what)
          else raise ArgumentError, "can't deselect options by #{how.inspect}"
          end
        end

        # Select every option (multi-select only).
        def select_all
          raise UnsupportedOperationError, 'you may only select all options of a multi-select' unless multiple?

          options.each { |e| select_option(e) }
        end

        # Deselect every option (multi-select only).
        def deselect_all
          raise UnsupportedOperationError, 'you may only deselect all options of a multi-select' unless multiple?

          options.each { |e| deselect_option(e) }
        end

        private

        def select_by_text(text)
          opt = options.find { |o| o.text == text }
          return select_option(opt) if opt

          raise NoSuchElementError, "cannot locate element with text: #{text.inspect}"
        end

        def select_by_value(value)
          opts = options.select { |o| o.attribute('value') == value }
          return opts.each { |o| select_option(o) } unless opts.empty?

          raise NoSuchElementError, "cannot locate option with value: #{value.inspect}"
        end

        def select_by_index(index)
          opts = options
          if index >= 0 && index < opts.length
            return select_option(opts[index])
          end

          raise NoSuchElementError, "cannot locate element with index: #{index.inspect}"
        end

        def deselect_by_text(text)
          raise UnsupportedOperationError, 'you may only deselect option of a multi-select' unless multiple?

          opt = options.find { |o| o.text == text }
          return deselect_option(opt) if opt

          raise NoSuchElementError, "cannot locate element with text: #{text.inspect}"
        end

        def deselect_by_value(value)
          raise UnsupportedOperationError, 'you may only deselect option of a multi-select' unless multiple?

          opts = options.select { |o| o.attribute('value') == value }
          return opts.each { |o| deselect_option(o) } unless opts.empty?

          raise NoSuchElementError, "cannot locate option with value: #{value.inspect}"
        end

        def deselect_by_index(index)
          raise UnsupportedOperationError, 'you may only deselect option of a multi-select' unless multiple?

          opts = options
          if index >= 0 && index < opts.length
            return deselect_option(opts[index])
          end

          raise NoSuchElementError, "cannot locate element with index: #{index}"
        end

        def select_option(option)
          raise UnsupportedOperationError, 'You may not select a disabled option' unless option.enabled?

          option.click unless option.selected?
        end

        def deselect_option(option)
          option.click if option.selected?
        end
      end # Select
    end # Support
  end # WebDriver
end # Selenium
