# frozen_string_literal: true

# selenium_core — Selenium WebDriver for Ruby, re-glued to the shared pure-Aether
# WebDriver core. A thin Fiddle binding: the entire W3C protocol (command
# catalog, route table, path templating, By normalization, error decode, HTTP
# round-trip) lives ONCE in the in-repo Aether engine (core/selenium_core.ae)
# and is shared by every language binding via libselenium_core.so. This gem is
# the Ruby face — it carries no protocol logic.
#
#   require 'selenium_core'
#   driver = SeleniumCore::WebDriver.headless_chrome('http://127.0.0.1:9515')
#   driver.get('https://example.com')
#   puts driver.title
#   driver.find_element(SeleniumCore::By::CSS_SELECTOR, 'a').click
#   driver.quit

require_relative 'selenium_core/native'
require_relative 'selenium_core/webdriver'

module SeleniumCore
  VERSION = '0.1.0'

  # Pin the native library path (wins over discovery / SELENIUM_CORE_LIB).
  def self.configure_native_lib(path)
    Native.configure(path)
  end
end
