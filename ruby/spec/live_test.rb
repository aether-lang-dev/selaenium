# frozen_string_literal: true

# Live end-to-end test: a real headless Chrome session driven entirely through
# the pure-Aether engine from Ruby. The whole pipeline —
# Ruby -> Fiddle -> libselenium_core.so -> std.http.client -> chromedriver ->
# Chrome. Skips if chromedriver is absent.

require 'minitest/autorun'
require 'socket'
require 'cgi'
require 'json'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium_core'

class LiveTest < Minitest::Test
  HTML = '<html><head><title>Aether Selenium</title></head>' \
         '<body><h1 id="hdr">Hello</h1>' \
         '<a href="#" id="lnk" class="nav">click me</a>' \
         '<input id="box" name="q"/></body></html>'

  def setup
    @driver_bin = which('chromedriver')
    skip 'chromedriver not on PATH' unless @driver_bin
    @port = free_port
    @cd = spawn(@driver_bin, "--port=#{@port}", out: File::NULL, err: File::NULL)
    skip 'chromedriver did not come up' unless wait_up(@port)
  end

  def teardown
    return unless @cd

    Process.kill('TERM', @cd)
    Process.wait(@cd)
  rescue Errno::ESRCH, Errno::ECHILD
    # already gone
  end

  def test_live_chrome
    driver = SeleniumCore::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      refute_empty driver.session_id, 'no session id after newSession'

      # CGI.escape form-encodes spaces as "+"; a data: URL wants %20.
      page = 'data:text/html;charset=utf-8,' + CGI.escape(HTML).gsub('+', '%20')
      driver.get(page)
      assert_equal 'Aether Selenium', driver.title

      hdr = driver.find_element(SeleniumCore::By::ID, 'hdr')
      assert_equal 'Hello', hdr.text

      lnk = driver.find_element(SeleniumCore::By::CLASS_NAME, 'nav')
      assert_equal 'a', lnk.tag_name.downcase
      lnk.click

      box = driver.find_element(SeleniumCore::By::CSS_SELECTOR, '#box')
      box.send_keys('hello world')
      assert_equal 'hello world', box.property('value')

      assert_equal 42, driver.execute_script('return 40 + 2;')

      assert_raises(SeleniumCore::NoSuchElementError) do
        driver.find_element(SeleniumCore::By::ID, 'does-not-exist')
      end
    ensure
      driver.quit
    end
  end

  # WebDriver-BiDi over the same engine: subscribe to console log entries, emit
  # one via the classic script channel, and receive the event asynchronously —
  # the bidirectional half, driven from Ruby through the demux C ABI.
  def test_live_bidi
    driver = SeleniumCore::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      assert driver.bidi_available?, 'session negotiated no webSocketUrl'

      page = 'data:text/html;charset=utf-8,' + CGI.escape(HTML).gsub('+', '%20')
      driver.get(page)

      ack = driver.bidi.subscribe(SeleniumCore::BidiEvent::LOG_ENTRY_ADDED)
      assert_equal 'success', ack['type'], "subscribe ack=#{ack.inspect}"

      driver.execute_script("console.log('bidi-hello');")

      ev = driver.bidi.next_event(SeleniumCore::BidiEvent::LOG_ENTRY_ADDED, timeout_ms: 8000)
      refute_nil ev, 'no log.entryAdded event received'
      assert_equal SeleniumCore::BidiEvent::LOG_ENTRY_ADDED, ev['method']
      assert_includes ev.to_json, 'bidi-hello'

      status = driver.bidi.command('session.status')
      assert_equal 'success', status['type'], "status=#{status.inspect}"
    ensure
      driver.quit
    end
  end

  private

  def which(cmd)
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |dir|
      path = File.join(dir, cmd)
      return path if File.executable?(path) && !File.directory?(path)
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
end
