# frozen_string_literal: true

# No-browser FFI test: proves the Ruby Fiddle binding loads libselenium_core.so
# and marshals correctly, exercising the pure engine helpers and the transport
# error path. Needs only the .so (SELENIUM_CORE_LIB / bundled native/).

require 'minitest/autorun'
require 'json'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium_core'

class FFITest < Minitest::Test
  def test_route
    assert_equal 'POST /session/:sessionId/url', SeleniumCore.route('get')
    assert_equal '', SeleniumCore.route('nope')
  end

  def test_error_code
    assert_equal 17, SeleniumCore.error_code('no such element')
    assert_equal 0, SeleniumCore.error_code('')
  end

  def test_locator_css
    assert_equal({ 'using' => 'css selector', 'value' => 'div.foo' },
                 SeleniumCore.decode_by(SeleniumCore::By::CSS_SELECTOR, 'div.foo'))
  end

  def test_locator_id_rewrite
    assert_equal({ 'using' => 'css selector', 'value' => '*[id="main"]' },
                 SeleniumCore.decode_by(SeleniumCore::By::ID, 'main'))
  end

  def test_transport_failure
    err = assert_raises(SeleniumCore::WebDriverError) do
      SeleniumCore::WebDriver.chrome('http://127.0.0.1:1')
    end
    assert_equal(-1, err.code)
  end
end
