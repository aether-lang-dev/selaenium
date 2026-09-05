# frozen_string_literal: true

# No-browser unit test for the convenience tier (Wait / Select / Actions / Keys).
# Everything here is pure Ruby over the binding's seam, so it needs no
# chromedriver and no live .so calls — Wait polls a block, Select drives stub
# option elements, Actions assembles the W3C payload, and Keys is a constant map.
# Requiring selenium-webdriver only loads the .so lazily (never touched here).

require 'minitest/autorun'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium-webdriver'

module SW
  include Selenium::WebDriver rescue nil
end

class ConvenienceTest < Minitest::Test
  W3C_KEY = Selenium::WebDriver::W3C_ELEMENT_KEY

  # ---- Keys: code points must match the W3C private-use values exactly ----

  def test_keys_code_points_match_w3c
    k = Selenium::WebDriver::Keys::KEYS
    {
      null: 0xE000, cancel: 0xE001, help: 0xE002, backspace: 0xE003, tab: 0xE004,
      clear: 0xE005, return: 0xE006, enter: 0xE007, shift: 0xE008, control: 0xE009,
      alt: 0xE00A, pause: 0xE00B, escape: 0xE00C, space: 0xE00D, page_up: 0xE00E,
      page_down: 0xE00F, end: 0xE010, home: 0xE011, left: 0xE012, up: 0xE013,
      right: 0xE014, down: 0xE015, insert: 0xE016, delete: 0xE017, semicolon: 0xE018,
      equals: 0xE019, numpad0: 0xE01A, numpad9: 0xE023, multiply: 0xE024, add: 0xE025,
      separator: 0xE026, subtract: 0xE027, decimal: 0xE028, divide: 0xE029,
      f1: 0xE031, f12: 0xE03C, meta: 0xE03D, zenkaku_hankaku: 0xE040,
      right_shift: 0xE050, right_control: 0xE051, right_alt: 0xE052, right_meta: 0xE053,
      numpad_page_up: 0xE054, numpad_delete: 0xE05D
    }.each do |sym, cp|
      assert_equal cp, k.fetch(sym).ord, "code point mismatch for #{sym}"
    end
  end

  def test_keys_aliases_share_code_points
    k = Selenium::WebDriver::Keys::KEYS
    assert_equal k[:shift],        k[:left_shift]
    assert_equal k[:control],      k[:left_control]
    assert_equal k[:alt],          k[:left_alt]
    assert_equal k[:meta],         k[:command]
    assert_equal k[:meta],         k[:left_meta]
    assert_equal k[:right_alt],    k[:options]
    assert_equal k[:right_control], k[:function]
    assert_equal k[:enter],        k[:numpad_enter]
    assert_equal k[:multiply],     k[:numpad_multiply]
  end

  def test_keys_uppercase_constants_match_map
    assert_equal Selenium::WebDriver::Keys::KEYS[:enter], Selenium::WebDriver::Keys::ENTER
    assert_equal Selenium::WebDriver::Keys::KEYS[:f12],   Selenium::WebDriver::Keys::F12
    assert_equal Selenium::WebDriver::Keys::KEYS[:meta],  Selenium::WebDriver::Keys::META
    assert_equal Selenium::WebDriver::Keys::KEYS[:shift], Selenium::WebDriver::Keys::SHIFT
  end

  def test_keys_lookup_and_encode
    enter = Selenium::WebDriver::Keys::KEYS[:enter]
    shift = Selenium::WebDriver::Keys::KEYS[:shift]
    null  = Selenium::WebDriver::Keys::KEYS[:null]

    assert_equal enter, Selenium::WebDriver::Keys[:enter]
    assert_raises(Selenium::WebDriver::UnsupportedOperationError) { Selenium::WebDriver::Keys[:nope] }

    # A chord Array is joined and NUL-terminated; symbols map through Keys;
    # plain strings pass through unchanged.
    encoded = Selenium::WebDriver::Keys.encode(['ab', :enter, [:shift, 'a']])
    assert_equal ['ab', enter, "#{shift}a#{null}"], encoded
  end

  # ---- Wait: returns on truthy, raises TimeoutError on timeout ----

  def test_wait_returns_truthy_result
    wait = Selenium::WebDriver::Wait.new(timeout: 2, interval: 0.01)
    calls = 0
    result = wait.until { (calls += 1) >= 3 ? :ready : false }
    assert_equal :ready, result
    assert_operator calls, :>=, 3
  end

  def test_wait_raises_timeout
    wait = Selenium::WebDriver::Wait.new(timeout: 0.1, interval: 0.02)
    err = assert_raises(Selenium::WebDriver::TimeoutError) { wait.until { false } }
    assert_match(/timed out/, err.message)
  end

  def test_wait_swallows_ignored_exception_until_timeout
    wait = Selenium::WebDriver::Wait.new(timeout: 0.1, interval: 0.02)
    err = assert_raises(Selenium::WebDriver::TimeoutError) do
      wait.until { raise Selenium::WebDriver::NoSuchElementError, 'not yet' }
    end
    # The last swallowed error is appended to the timeout message.
    assert_match(/not yet/, err.message)
  end

  def test_wait_does_not_swallow_unignored_exception
    wait = Selenium::WebDriver::Wait.new(timeout: 1, interval: 0.01)
    assert_raises(ArgumentError) { wait.until { raise ArgumentError, 'boom' } }
  end

  def test_webdriverwait_alias_passes_driver
    seen = nil
    w = Selenium::WebDriver::WebDriverWait.new(:the_driver, 1, interval: 0.01)
    result = w.until { |drv| seen = drv; :ok }
    assert_equal :the_driver, seen
    assert_equal :ok, result
  end

  # ---- Select: picks the right option via stub elements ----

  # A stub <option>: records clicks, reports text/value/selected/enabled.
  class StubOption
    attr_reader :clicks
    def initialize(text:, value:, selected: false, enabled: true)
      @text = text
      @value = value
      @selected = selected
      @enabled = enabled
      @clicks = 0
    end

    def tag_name = 'option'
    def text = @text
    def attribute(name) = (name == 'value' ? @value : nil)
    def selected? = @selected
    def enabled? = @enabled
    def click
      @clicks += 1
      @selected = !@selected # clicking toggles selection, like a real <option>
    end
  end

  # A stub <select>: hands back its options for find_elements(tag_name: 'option').
  class StubSelect
    def initialize(options:, multiple: false)
      @options = options
      @multiple = multiple
    end

    def tag_name = 'select'
    def attribute(name) = (name == 'multiple' ? (@multiple ? 'true' : nil) : nil)
    def find_elements(how)
      raise "unexpected finder #{how.inspect}" unless how == { tag_name: 'option' }

      @options
    end
  end

  def build_select(multiple: false)
    opts = [
      StubOption.new(text: 'Red',   value: 'r'),
      StubOption.new(text: 'Green', value: 'g'),
      StubOption.new(text: 'Blue',  value: 'b')
    ]
    [Selenium::WebDriver::Support::Select.new(StubSelect.new(options: opts, multiple: multiple)), opts]
  end

  def test_select_rejects_non_select_tag
    assert_raises(ArgumentError) do
      Selenium::WebDriver::Support::Select.new(StubOption.new(text: 'x', value: 'x'))
    end
  end

  def test_select_by_text
    sel, opts = build_select
    sel.select_by(:text, 'Green')
    assert_equal 1, opts[1].clicks
    assert_equal 0, opts[0].clicks
    assert_equal 0, opts[2].clicks
    assert opts[1].selected?
  end

  def test_select_by_value
    sel, opts = build_select
    sel.select_by(:value, 'b')
    assert_equal 1, opts[2].clicks
    assert opts[2].selected?
  end

  def test_select_by_index
    sel, opts = build_select
    sel.select_by(:index, 0)
    assert_equal 1, opts[0].clicks
    assert opts[0].selected?
  end

  def test_select_missing_option_raises
    sel, = build_select
    assert_raises(Selenium::WebDriver::NoSuchElementError) { sel.select_by(:text, 'Purple') }
    assert_raises(Selenium::WebDriver::NoSuchElementError) { sel.select_by(:value, 'z') }
    assert_raises(Selenium::WebDriver::NoSuchElementError) { sel.select_by(:index, 9) }
  end

  def test_select_skips_already_selected
    opts = [StubOption.new(text: 'Red', value: 'r', selected: true)]
    sel = Selenium::WebDriver::Support::Select.new(StubSelect.new(options: opts))
    sel.select_by(:text, 'Red')
    assert_equal 0, opts[0].clicks, 'an already-selected option must not be clicked'
  end

  def test_select_disabled_option_raises
    opts = [StubOption.new(text: 'Red', value: 'r', enabled: false)]
    sel = Selenium::WebDriver::Support::Select.new(StubSelect.new(options: opts))
    assert_raises(Selenium::WebDriver::UnsupportedOperationError) { sel.select_by(:text, 'Red') }
  end

  def test_single_select_rejects_deselect_all
    sel, = build_select(multiple: false)
    assert_raises(Selenium::WebDriver::UnsupportedOperationError) { sel.deselect_all }
  end

  def test_multi_select_first_selected_and_selected_options
    opts = [
      StubOption.new(text: 'A', value: 'a', selected: true),
      StubOption.new(text: 'B', value: 'b'),
      StubOption.new(text: 'C', value: 'c', selected: true)
    ]
    sel = Selenium::WebDriver::Support::Select.new(StubSelect.new(options: opts, multiple: true))
    assert sel.multiple?
    assert_equal 'A', sel.first_selected_option.text
    assert_equal %w[A C], sel.selected_options.map(&:text)
  end

  # ---- Actions: build the correct W3C payload ----

  # A stub element and stub driver that capture the actions payload posted.
  StubElement = Struct.new(:id)
  class RecordingDriver
    attr_reader :posted
    def perform_actions(actions) = (@posted = actions)
  end

  def test_actions_click_payload
    el = StubElement.new('E1')
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).click(el).perform

    assert_equal(
      [{
        'type' => 'pointer', 'id' => 'mouse',
        'parameters' => { 'pointerType' => 'mouse' },
        'actions' => [
          { 'type' => 'pointerMove', 'duration' => 100, 'x' => 0, 'y' => 0,
            'origin' => { W3C_KEY => 'E1' } },
          { 'type' => 'pointerDown', 'button' => 0 },
          { 'type' => 'pointerUp', 'button' => 0 }
        ]
      }],
      driver.posted
    )
  end

  def test_actions_context_click_uses_button_2
    el = StubElement.new('E9')
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).context_click(el).perform
    ptr = driver.posted.first['actions']
    assert_equal 2, ptr[1]['button']
    assert_equal 2, ptr[2]['button']
  end

  def test_actions_send_keys_payload_and_key_device
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).send_keys('hi').perform

    key_dev = driver.posted.find { |d| d['type'] == 'key' }
    refute_nil key_dev, 'expected a key virtual device'
    assert_equal 'keyboard', key_dev['id']
    assert_equal(
      [
        { 'type' => 'keyDown', 'value' => 'h' },
        { 'type' => 'keyUp',   'value' => 'h' },
        { 'type' => 'keyDown', 'value' => 'i' },
        { 'type' => 'keyUp',   'value' => 'i' }
      ],
      key_dev['actions']
    )
    # No pointer device when only keys were queued.
    assert_nil driver.posted.find { |d| d['type'] == 'pointer' }
  end

  def test_actions_key_down_up_with_modifier
    driver = RecordingDriver.new
    shift = Selenium::WebDriver::Keys::SHIFT
    Selenium::WebDriver::ActionBuilder.new(driver)
                                      .key_down(shift).send_keys('a').key_up(shift).perform
    key_dev = driver.posted.find { |d| d['type'] == 'key' }
    types = key_dev['actions'].map { |a| [a['type'], a['value']] }
    assert_equal(
      [['keyDown', shift], ['keyDown', 'a'], ['keyUp', 'a'], ['keyUp', shift]],
      types
    )
  end

  def test_actions_ticks_are_length_synced_across_devices
    # A pointer move + a key press must leave both device tick-lists equal length
    # (W3C requirement) — the shorter is padded with pauses.
    el = StubElement.new('E2')
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).move_to(el).key_down('a').perform
    ptr = driver.posted.find { |d| d['type'] == 'pointer' }['actions']
    key = driver.posted.find { |d| d['type'] == 'key' }['actions']
    assert_equal ptr.length, key.length, 'device tick lists must be the same length'
  end

  def test_actions_drag_and_drop_payload
    src = StubElement.new('S')
    dst = StubElement.new('D')
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).drag_and_drop(src, dst).perform
    ptr = driver.posted.first['actions']
    kinds = ptr.map { |a| a['type'] }
    assert_equal %w[pointerMove pointerDown pointerMove pointerUp], kinds
    assert_equal({ W3C_KEY => 'S' }, ptr[0]['origin'])
    assert_equal({ W3C_KEY => 'D' }, ptr[2]['origin'])
  end

  def test_actions_empty_perform_posts_nothing
    driver = RecordingDriver.new
    Selenium::WebDriver::ActionBuilder.new(driver).perform
    assert_nil driver.posted, 'an empty action chain must post nothing'
  end

  def test_actions_perform_resets_builder
    el = StubElement.new('E3')
    driver = RecordingDriver.new
    a = Selenium::WebDriver::ActionBuilder.new(driver)
    a.click(el).perform
    driver.instance_variable_set(:@posted, nil)
    a.perform # nothing queued after the reset
    assert_nil driver.posted
  end

  def test_actions_alias_names
    assert_equal Selenium::WebDriver::ActionBuilder, Selenium::WebDriver::Actions
    assert_equal Selenium::WebDriver::ActionBuilder, Selenium::WebDriver::ActionChains
  end
end
