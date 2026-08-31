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

      # Typed BiDi convenience commands: getTree / script.evaluate / navigate.
      ctx = driver.bidi.top_context
      refute_nil ctx, 'top_context should resolve a browsing context id'

      assert_equal 42, driver.bidi.evaluate_value('6*7'),
                   'script.evaluate should compute 6*7 == 42'
      # A promise the classic execute_script channel cannot await:
      assert_equal 42, driver.bidi.evaluate_value('Promise.resolve(41+1)'),
                   'script.evaluate should await the resolved promise to 42'

      # BiDi network interception: intercept all requests at beforeRequestSent,
      # trigger a fetch, receive the paused-request event, then release it.
      driver.bidi.subscribe(SeleniumCore::BidiEvent::BEFORE_REQUEST_SENT)
      ic = driver.bidi.add_intercept(url_pattern: '')
      refute_nil ic, 'add_intercept should return an intercept id'

      driver.execute_script("fetch('https://example.com/blocked').catch(function(){});")

      ev = driver.bidi.next_event(SeleniumCore::BidiEvent::BEFORE_REQUEST_SENT, timeout_ms: 8000)
      refute_nil ev, 'no network.beforeRequestSent event received'

      rid = SeleniumCore::BiDi.event_request_id(ev)
      refute_nil rid, 'event should carry a request id'

      assert_equal 'success', driver.bidi.continue_request(rid)['type'],
                   'continue_request should succeed'

      # BiDi request mocking: fulfill a paused request with a mock response
      # (never hits the network) and prove the page reads the mocked body.
      driver.execute_script("window.__mock='';fetch('https://example.com/api').then(function(r){return r.text()}).then(function(t){window.__mock=t}).catch(function(){});")
      ev2 = driver.bidi.next_event(SeleniumCore::BidiEvent::BEFORE_REQUEST_SENT, timeout_ms: 8000)
      rid2 = SeleniumCore::BiDi.event_request_id(ev2)
      resp = driver.bidi.provide_response(rid2, status: 200, content_type: 'text/plain', body: 'MOCKED-BODY')
      assert_equal 'success', resp['type']
      got = ''
      25.times { got = driver.execute_script('return window.__mock;').to_s; break if got.include?('MOCKED-BODY'); sleep 0.2 }
      assert got.include?('MOCKED-BODY'), "page did not receive mock: #{got}"
    ensure
      driver.quit
    end
  end

  # Atom-backed commands (isDisplayed / getAttribute / relative locators) run as
  # JS atoms via executeScript — no W3C HTTP endpoint — proven against real Chrome.
  ATOMS_HTML = '<html><head><title>Atoms</title></head><body>' \
               "<h1 id='hdr'>Header</h1>" \
               "<button id='btn'>Go</button>" \
               "<p id='gone' style='display:none'>hidden</p>" \
               "<a id='lnk' href='https://example.com/x'>link</a>" \
               '</body></html>'

  def test_live_atoms
    driver = SeleniumCore::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      page = 'data:text/html;charset=utf-8,' + CGI.escape(ATOMS_HTML).gsub('+', '%20')
      driver.get(page)

      assert driver.find_element(SeleniumCore::By::ID, 'hdr').displayed?,
             '#hdr should be displayed'
      refute driver.find_element(SeleniumCore::By::ID, 'gone').displayed?,
             '#gone (display:none) should not be displayed'

      href = driver.find_element(SeleniumCore::By::ID, 'lnk').attribute('href')
      assert_includes href, 'example.com/x', "unexpected href: #{href.inspect}"

      below = driver.find_relative('button', { kind: 'below', sel: '#hdr' })
      assert_operator below.size, :>=, 1, 'expected >= 1 button below #hdr'
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
