# frozen_string_literal: true

# Third-party consumer example. Requires the INSTALLED `selenium-webdriver` gem (from
# a clean GEM_HOME — NOT the source tree, no -Ilib) and proves the bundled
# engine .so loads and drives the protocol, with SELENIUM_CORE_LIB unset so only
# the gem's own bundled native/ can satisfy the load.
#
# Modes (ARGV[0]):
#   ffi       — no browser: load the .so, exercise the pure engine helpers and a
#               transport-error round-trip. Always runnable.
#   discovery — like ffi, but asserts the .so was found by the gem's own bundled
#               native/ discovery (no env var, no explicit path).
#   live      — real headless Chrome if chromedriver is on PATH; skips otherwise.

require 'selenium-webdriver'
require 'json'
require 'socket'
require 'cgi'

def check_installed
  path = $LOADED_FEATURES.find { |f| f.end_with?('selenium-webdriver.rb') }
  # Must resolve from the isolated gem dir, NOT the repo's ruby/lib.
  if path.nil? || path.include?("#{File::SEPARATOR}ruby#{File::SEPARATOR}lib#{File::SEPARATOR}")
    abort "FAIL: loaded selenium-webdriver from #{path.inspect}, not the installed gem"
  end
end

def mode_ffi
  check_installed
  raise 'route mismatch' unless Selenium::WebDriver.route('get') == 'POST /session/:sessionId/url'
  raise 'error_code mismatch' unless Selenium::WebDriver.error_code('no such element') == 17
  loc = Selenium::WebDriver.decode_by(Selenium::WebDriver::By::ID, 'main')
  raise "locator mismatch: #{loc}" unless loc == { 'using' => 'css selector', 'value' => '*[id="main"]' }
  begin
    Selenium::WebDriver.chrome('http://127.0.0.1:1')
    abort 'FAIL: expected transport failure'
  rescue Selenium::WebDriver::WebDriverError => e
    abort "FAIL: wrong transport code #{e.code}" unless e.code == -1
  end
  puts 'consumer(ffi): OK — installed gem loaded its bundled .so and marshalled'
end

def mode_discovery
  abort 'FAIL: SELENIUM_CORE_LIB set; discovery must run without it' if ENV['SELENIUM_CORE_LIB'] && !ENV['SELENIUM_CORE_LIB'].empty?
  check_installed
  gem_root = File.dirname($LOADED_FEATURES.find { |f| f.end_with?('selenium-webdriver.rb') })
  native = File.join(gem_root, 'selenium', 'native')
  abort "FAIL: no bundled native/ at #{native}" unless Dir.exist?(native)
  abort 'FAIL: bundled native/ has no shared library' unless Dir[File.join(native, '*.{so,dylib,dll}')].any?
  raise 'route mismatch' unless Selenium::WebDriver.route('newSession') == 'POST /session'
  puts 'consumer(discovery): OK — zero-config bundled-.so discovery works'
end

def which(cmd)
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |dir|
    p = File.join(dir, cmd)
    return p if File.executable?(p) && !File.directory?(p)
  end
  nil
end

def free_port
  s = TCPServer.new('127.0.0.1', 0)
  port = s.addr[1]
  s.close
  port
end

def wait_up(port, timeout = 10.0)
  deadline = Time.now + timeout
  while Time.now < deadline
    begin
      TCPSocket.new('127.0.0.1', port).close
      return true
    rescue Errno::ECONNREFUSED
      sleep 0.1
    end
  end
  false
end

def mode_live
  driver = which('chromedriver')
  if driver.nil?
    puts 'consumer(live): SKIPPED — chromedriver not on PATH'
    return
  end
  check_installed
  port = free_port
  cd = spawn(driver, "--port=#{port}", out: File::NULL, err: File::NULL)
  begin
    unless wait_up(port)
      puts 'consumer(live): SKIPPED — chromedriver did not come up'
      return
    end
    d = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{port}")
    begin
      html = '<html><head><title>Installed</title></head><body><h1 id="h">Hi</h1></body></html>'
      d.get('data:text/html;charset=utf-8,' + CGI.escape(html).gsub('+', '%20'))
      abort "FAIL: title=#{d.title}" unless d.title == 'Installed'
      abort 'FAIL: text' unless d.find_element(Selenium::WebDriver::By::ID, 'h').text == 'Hi'
      puts 'consumer(live): OK — installed gem drove real headless Chrome'
    ensure
      d.quit
    end
  ensure
    begin
      Process.kill('TERM', cd)
      Process.wait(cd)
    rescue Errno::ESRCH, Errno::ECHILD
      # gone
    end
  end
end

mode = ARGV[0] || 'ffi'
case mode
when 'ffi'       then mode_ffi
when 'discovery' then mode_discovery
when 'live'      then mode_live
else abort "unknown mode: #{mode}"
end
