# frozen_string_literal: true

# selenium-webdriver — Selenium WebDriver for Ruby, re-glued to the shared
# pure-Aether WebDriver core. A thin Fiddle binding: the entire W3C protocol
# (command catalog, route table, path templating, By normalization, error
# decode, HTTP round-trip) lives ONCE in the in-repo Aether engine
# (core/selenium_core.ae) and is shared by every language binding via
# libselenium_core.so. This gem is the Ruby face — it carries no protocol logic.
#
#   require 'selenium-webdriver'
#   driver = Selenium::WebDriver.for(:chrome)
#   driver.get('https://example.com')
#   puts driver.title
#   driver.find_element(css: 'a').click
#   driver.quit

require_relative 'selenium/native'
require_relative 'selenium/webdriver'

module Selenium
  module WebDriver
    VERSION = '0.1.0'

    # Session dispatcher — authentic Selenium `Selenium::WebDriver.for(:chrome)`.
    # Maps a browser symbol to the matching constructor. :chrome spawns its own
    # chromedriver via the engine (LocalChrome); pass command_executor: to drive
    # a running chromedriver/Grid instead.
    def self.for(browser, command_executor: nil, **opts)
      case browser.to_sym
      when :chrome
        if command_executor
          WebDriver.chrome(command_executor, **opts)
        else
          WebDriver.local_chrome(**opts)
        end
      else
        raise WebDriverError, "unsupported browser: #{browser.inspect}"
      end
    end

    # Pin the native library path (wins over discovery / SELENIUM_CORE_LIB).
    def self.configure_native_lib(path)
      Native.configure(path)
    end
  end
end
