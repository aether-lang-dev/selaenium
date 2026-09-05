# frozen_string_literal: true

# No-browser unit test for the mainstream ABI facades added to the Ruby binding:
# navigate / switch_to / manage (+ Timeouts / Window / Alert), the canonical
# Element name, variadic send_keys, the extended error taxonomy, Chrome::Options,
# and the screenshot surface. Everything bottoms out on Driver#execute, so a
# RecordingDriver captures every (command, params) pair the facades issue — no
# chromedriver and no live .so calls needed.

require 'minitest/autorun'
require 'base64'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium-webdriver'

module SW
  M = Selenium::WebDriver
end

# Captures (command, params) and returns scripted values by command name so the
# facades can be driven without a remote end. Quacks like Driver#execute.
class RecordingDriver
  W3C_KEY = Selenium::WebDriver::W3C_ELEMENT_KEY

  attr_reader :calls

  def initialize(returns = {})
    @returns = returns
    @calls = []
  end

  def execute(command, params = {})
    @calls << [command, params]
    @returns.fetch(command, nil)
  end

  # execute_script is used by Element#submit; record and no-op.
  def execute_script(script, *args)
    @calls << ['executeScript', { 'script' => script, 'args' => args }]
    nil
  end

  def last = @calls.last
  def commands = @calls.map(&:first)

  def command(name)
    @calls.reverse.find { |c| c.first == name }
  end
end

class FacadeTest < Minitest::Test
  M = Selenium::WebDriver
  W3C_KEY = Selenium::WebDriver::W3C_ELEMENT_KEY

  # ---- Navigation -------------------------------------------------------------

  def test_navigation_issues_w3c_commands
    d = RecordingDriver.new
    nav = M::Navigation.new(d)
    nav.to('http://example.com')
    nav.back
    nav.forward
    nav.refresh

    assert_equal %w[get goBack goForward refresh], d.commands
    assert_equal({ 'url' => 'http://example.com' }, d.calls.first[1])
  end

  # ---- TargetLocator (switch_to) ---------------------------------------------

  def test_switch_to_window_and_frames
    d = RecordingDriver.new('newWindow' => { 'handle' => 'W2' })
    tl = M::TargetLocator.new(d)

    tl.window('W1')
    assert_equal ['switchToWindow', { 'handle' => 'W1' }], d.command('switchToWindow')

    tl.frame(0)
    assert_equal ['switchToFrame', { 'id' => 0 }], d.command('switchToFrame')

    tl.default_content
    assert_equal ['switchToFrame', { 'id' => nil }], d.command('switchToFrame')

    tl.parent_frame
    assert_equal 'switchToFrameParent', d.command('switchToFrameParent').first
  end

  def test_switch_to_frame_with_web_element
    d = RecordingDriver.new
    el = M::WebElement.new(d, 'EL9')
    M::TargetLocator.new(d).frame(el)
    assert_equal({ 'id' => { W3C_KEY => 'EL9' } }, d.command('switchToFrame')[1])
  end

  def test_switch_to_new_window
    d = RecordingDriver.new('newWindow' => { 'handle' => 'NW' })
    handle = M::TargetLocator.new(d).new_window(:tab)
    assert_equal 'NW', handle
    assert_equal ['newWindow', { 'type' => 'tab' }], d.command('newWindow')
    # It also switches focus to the new handle.
    assert_equal ['switchToWindow', { 'handle' => 'NW' }], d.command('switchToWindow')
  end

  def test_new_window_rejects_bad_type
    d = RecordingDriver.new('newWindow' => { 'handle' => 'x' })
    assert_raises(ArgumentError) { M::TargetLocator.new(d).new_window(:frame) }
  end

  def test_switch_to_active_element
    d = RecordingDriver.new('getActiveElement' => { W3C_KEY => 'AE' })
    el = M::TargetLocator.new(d).active_element
    assert_instance_of M::WebElement, el
    assert_equal 'AE', el.id
  end

  # ---- Alert ------------------------------------------------------------------

  def test_alert_facade
    d = RecordingDriver.new('getAlertText' => 'Are you sure?')
    alert = M::TargetLocator.new(d).alert
    # Construction fails fast by reading text.
    assert_equal 'getAlertText', d.calls.first.first

    assert_equal 'Are you sure?', alert.text
    alert.send_keys('hello')
    sk = d.command('setAlertValue')
    assert_equal 'hello', sk[1]['text']
    assert_equal %w[h e l l o], sk[1]['value']

    alert.accept
    assert_equal 'acceptAlert', d.command('acceptAlert').first
    alert.dismiss
    assert_equal 'dismissAlert', d.command('dismissAlert').first
  end

  # ---- Manager: cookies -------------------------------------------------------

  def test_manage_add_cookie_normalizes_keys
    d = RecordingDriver.new
    M::Manager.new(d).add_cookie(name: 'a', value: 'b', same_site: 'Strict', http_only: true)
    cookie = d.command('addCookie')[1]['cookie']
    assert_equal 'a', cookie['name']
    assert_equal 'b', cookie['value']
    assert_equal 'Strict', cookie['sameSite']
    assert_equal true, cookie['httpOnly']
    assert_equal false, cookie['secure'] # defaulted
  end

  def test_manage_add_cookie_requires_name_and_value
    d = RecordingDriver.new
    assert_raises(ArgumentError) { M::Manager.new(d).add_cookie(value: 'b') }
    assert_raises(ArgumentError) { M::Manager.new(d).add_cookie(name: 'a') }
  end

  def test_manage_cookie_named_and_delete
    d = RecordingDriver.new('getCookie' => { 'name' => 'flavor', 'value' => 'mint' })
    m = M::Manager.new(d)
    assert_equal 'mint', m.cookie_named('flavor')['value']
    assert_equal ['getCookie', { 'name' => 'flavor' }], d.command('getCookie')

    m.delete_cookie('flavor')
    assert_equal ['deleteCookie', { 'name' => 'flavor' }], d.command('deleteCookie')

    m.delete_all_cookies
    assert_equal 'deleteAllCookies', d.command('deleteAllCookies').first
    assert_raises(ArgumentError) { m.delete_cookie('') }
  end

  def test_manage_all_cookies
    d = RecordingDriver.new('getCookies' => [{ 'name' => 'x' }])
    assert_equal [{ 'name' => 'x' }], M::Manager.new(d).all_cookies
  end

  # ---- Manager: timeouts (SECONDS -> ms) -------------------------------------

  def test_manage_timeouts_seconds_to_ms
    d = RecordingDriver.new
    t = M::Manager.new(d).timeouts
    t.implicit_wait = 10
    t.script = 5
    t.page_load = 30

    assert_equal 'setTimeout', d.calls[0][0]
    assert_equal({ 'implicit' => 10_000 }, d.calls[0][1])
    assert_equal({ 'script' => 5_000 }, d.calls[1][1])
    assert_equal({ 'pageLoad' => 30_000 }, d.calls[2][1])
  end

  # ---- Manager: window --------------------------------------------------------

  def test_manage_window_maximize_and_rect
    d = RecordingDriver.new('getWindowRect' => { 'x' => 1, 'y' => 2, 'width' => 800, 'height' => 600 })
    w = M::Manager.new(d).window

    w.maximize
    assert_equal 'maximizeWindow', d.command('maximizeWindow').first
    w.minimize
    assert_equal 'minimizeWindow', d.command('minimizeWindow').first
    w.full_screen
    assert_equal 'fullscreenWindow', d.command('fullscreenWindow').first

    assert_equal 800, w.size['width']
    assert_equal({ 'x' => 1, 'y' => 2 }, w.position)

    w.size = { width: 1024, height: 768 }
    assert_equal({ 'width' => 1024, 'height' => 768 }, d.command('setWindowRect')[1])

    w.position = { x: 10, y: 20 }
    assert_equal({ 'x' => 10, 'y' => 20 }, d.command('setWindowRect')[1])

    w.rect = { x: 0, y: 0, width: 500, height: 400 }
    assert_equal({ 'x' => 0, 'y' => 0, 'width' => 500, 'height' => 400 }, d.command('setWindowRect')[1])
  end

  # ---- Element canonical name + methods --------------------------------------

  def test_element_canonical_name_resolves
    assert_same M::WebElement, M::Element
    el = M::Element.new(RecordingDriver.new, 'E1')
    assert_kind_of M::WebElement, el
    assert_kind_of M::Element, el
  end

  def test_element_send_keys_variadic
    d = RecordingDriver.new
    el = M::WebElement.new(d, 'E1')
    el.send_keys('tet', :arrow_left, 's')
    params = d.command('sendKeysToElement')[1]
    left = M::Keys[:arrow_left]
    assert_equal "tet#{left}s", params['text']
    assert_equal "tet#{left}s".chars, params['value']
    assert_equal 'E1', params['id']
  end

  def test_element_send_key_alias
    d = RecordingDriver.new
    M::WebElement.new(d, 'E1').send_key('x')
    assert_equal 'sendKeysToElement', d.command('sendKeysToElement').first
  end

  def test_element_css_value_location_size
    d = RecordingDriver.new(
      'getElementValueOfCssProperty' => 'rgb(0, 0, 0)',
      'getElementRect' => { 'x' => 5, 'y' => 6, 'width' => 10, 'height' => 20 }
    )
    el = M::WebElement.new(d, 'E1')
    assert_equal 'rgb(0, 0, 0)', el.css_value('color')
    assert_equal 'rgb(0, 0, 0)', el.style('color')
    assert_equal({ 'x' => 5, 'y' => 6 }, el.location)
    assert_equal({ 'height' => 20, 'width' => 10 }, el.size)
  end

  def test_element_find_elements_plural
    d = RecordingDriver.new('findChildElements' => [{ W3C_KEY => 'C1' }, { W3C_KEY => 'C2' }])
    els = M::WebElement.new(d, 'E1').find_elements(tag_name: 'li')
    assert_equal %w[C1 C2], els.map(&:id)
    assert_equal 'E1', d.command('findChildElements')[1]['id']
  end

  def test_element_screenshot_and_equality
    d = RecordingDriver.new('takeElementScreenshot' => 'BASE64PNG')
    el = M::WebElement.new(d, 'E1')
    assert_equal 'BASE64PNG', el.screenshot
    same = M::WebElement.new(d, 'E1')
    other = M::WebElement.new(d, 'E2')
    assert_equal el, same
    assert el.eql?(same)
    assert_equal el.hash, same.hash
    refute_equal el, other
  end

  def test_element_submit_uses_execute_script
    d = RecordingDriver.new
    M::WebElement.new(d, 'E1').submit
    call = d.command('executeScript')
    assert_match(/submitForm/, call[1]['script'])
  end

  # ---- Driver additions (via a light Driver-like double) ---------------------

  # A Driver subclass that stubs the FFI seam so the mainstream Driver additions
  # (window_handle, status, screenshot_as, save_screenshot, for) can be exercised
  # without opening a real session.
  class FakeDriver < Selenium::WebDriver::Driver
    attr_reader :calls

    def initialize(returns = {})
      @returns = returns
      @caps = { 'browserName' => 'chrome' }
      @calls = []
    end

    def execute(command, params = {})
      @calls << [command, params]
      @returns.fetch(command, nil)
    end
  end

  def test_driver_window_handle_alias
    d = FakeDriver.new('getCurrentWindowHandle' => 'H1')
    assert_equal 'H1', d.window_handle
    assert_equal 'H1', d.current_window_handle
  end

  def test_driver_status_and_capabilities
    d = FakeDriver.new('getStatus' => { 'ready' => true })
    assert_equal({ 'ready' => true }, d.status)
    assert_equal({ 'browserName' => 'chrome' }, d.capabilities)
  end

  def test_driver_close
    d = FakeDriver.new
    d.close
    assert_equal 'close', d.calls.last.first
  end

  def test_driver_screenshot_as_and_save
    png = "\x89PNG\r\n\x1A\n".b
    b64 = Base64.strict_encode64(png)
    d = FakeDriver.new('screenshot' => b64)
    assert_equal b64, d.screenshot_as(:base64)
    assert_equal png, d.screenshot_as(:png)

    path = File.join(Dir.tmpdir, "sel-#{Process.pid}.png")
    begin
      d.save_screenshot(path)
      assert_equal png, File.binread(path)
    ensure
      File.delete(path) if File.exist?(path)
    end
    d2 = FakeDriver.new('screenshot' => b64)
    assert_raises(M::UnsupportedOperationError) { d2.screenshot_as(:gif) }
  end

  def test_driver_facade_accessors_present
    d = FakeDriver.new
    assert_instance_of M::Navigation, d.navigate
    assert_instance_of M::TargetLocator, d.switch_to
    assert_instance_of M::Manager, d.manage
    # memoized
    assert_same d.navigate, d.navigate
    assert_same d.manage, d.manage
  end

  def test_driver_navigate_facade_reaches_get
    d = FakeDriver.new
    d.navigate.to('http://x')
    assert_equal ['get', { 'url' => 'http://x' }], d.calls.last
  end

  # ---- Error taxonomy ---------------------------------------------------------

  def test_new_error_classes_exist_under_error_module
    %i[DetachedShadowRootError InvalidElementStateError UnknownError NoSuchTargetError
       NoSuchShadowRootError InvalidCookieDomainError UnableToSetCookieError NoSuchAlertError
       ScriptTimeoutError MoveTargetOutOfBoundsError InsecureCertificateError InvalidArgumentError
       NoSuchCookieError UnableToCaptureScreenError InvalidSessionIdError UnexpectedAlertOpenError
       UnknownMethodError NoSuchDriverError].each do |name|
      assert M::Error.const_defined?(name), "Error::#{name} missing"
      # Flat and aliased class are the same object, and subclass WebDriverError.
      assert_same M.const_get(name), M::Error.const_get(name)
      assert_operator M::Error.const_get(name), :<, M::WebDriverError
    end
  end

  def test_code_to_exc_maps_new_codes
    # A representative sampling of the extended engine-code map.
    {
      7 => M::InvalidArgumentError,
      15 => M::NoSuchAlertError,
      16 => M::NoSuchCookieError,
      21 => M::ScriptTimeoutError,
      27 => M::UnexpectedAlertOpenError,
      30 => M::UnsupportedOperationError
    }.each do |code, klass|
      assert_equal klass, M::CODE_TO_EXC[code], "code #{code}"
    end
  end

  # ---- By class-method form ---------------------------------------------------

  def test_by_class_method_locators
    assert_equal({ id: 'x' }, M::By.id('x'))
    assert_equal({ name: 'n' }, M::By.name('n'))
    assert_equal({ css_selector: '.c' }, M::By.css_selector('.c'))
    assert_equal({ xpath: '//a' }, M::By.xpath('//a'))
    assert_equal({ class_name: 'k' }, M::By.class_name('k'))
    # :relative is a recognized finder symbol
    assert_equal 'relative', M::By.strategy_for(:relative)
  end

  # ---- Chrome::Options + .chrome(options:) path ------------------------------

  def test_chrome_options_to_capabilities
    o = M::Chrome::Options.new
    o.add_argument('--headless=new')
    o.add_argument('--no-sandbox')
    o.binary = '/opt/chrome'
    o.add_experimental_option('excludeSwitches', ['enable-automation'])
    o.add_option(prefs: { 'download.default_directory' => '/tmp' })

    caps = o.to_capabilities
    assert_equal 'chrome', caps['browserName']
    goog = caps['goog:chromeOptions']
    assert_equal ['--headless=new', '--no-sandbox'], goog['args']
    assert_equal '/opt/chrome', goog['binary']
    assert_equal ['enable-automation'], goog['excludeSwitches']
    assert_equal({ 'download.default_directory' => '/tmp' }, goog['prefs'])
  end

  def test_options_to_caps_accepts_object_and_hash
    o = M::Chrome::Options.new
    o.add_argument('--foo')
    from_obj = M.options_to_caps(o)
    assert_equal ['--foo'], from_obj['goog:chromeOptions']['args']

    raw = { 'goog:chromeOptions' => { 'args' => ['--bar'] } }
    assert_equal raw, M.options_to_caps(raw)
    assert_equal({}, M.options_to_caps(nil))
  end

  def test_chrome_constructor_accepts_options_object
    # Driver.chrome merges options.to_capabilities under browserName without
    # opening a session — stub the constructor to capture the caps it builds.
    captured = nil
    M::Driver.stub(:new, ->(_url, caps, **_kw) { captured = caps; :ok }) do
      o = M::Chrome::Options.new
      o.add_argument('--headless=new')
      assert_equal :ok, M::Driver.chrome('http://127.0.0.1:9515', options: o)
    end
    assert_equal 'chrome', captured['browserName']
    assert_equal ['--headless=new'], captured['goog:chromeOptions']['args']
  end
end

require 'tmpdir'
