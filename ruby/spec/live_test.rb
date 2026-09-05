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
require 'selenium-webdriver'

class LiveTest < Minitest::Test
  HTML = '<html><head><title>Aether Selenium</title></head>' \
         '<body><h1 id="hdr">Hello</h1>' \
         '<a href="#" id="lnk" class="nav">click me</a>' \
         '<input id="box" name="q"/></body></html>'

  def setup
    # The driver-orchestration test spawns its OWN chromedriver via the engine
    # (the whole point is not relying on one on PATH), so it skips this shared
    # PATH-based chromedriver harness.
    return if name == 'test_live_driver_orchestration'

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
    # Selenium::WebDriver.for(:chrome, command_executor:) dispatches to a Chrome
    # session against the running chromedriver (headless options passed through).
    driver = Selenium::WebDriver.for(:chrome, command_executor: "http://127.0.0.1:#{@port}",
                                              options: {
                                                'goog:chromeOptions' => {
                                                  'args' => ['--headless=new', '--no-sandbox',
                                                             '--disable-gpu', '--disable-dev-shm-usage']
                                                }
                                              })
    begin
      refute_empty driver.session_id, 'no session id after newSession'

      # CGI.escape form-encodes spaces as "+"; a data: URL wants %20.
      page = 'data:text/html;charset=utf-8,' + CGI.escape(HTML).gsub('+', '%20')
      driver.get(page)
      assert_equal 'Aether Selenium', driver.title

      # Authentic Ruby keyword-hash finder form.
      hdr = driver.find_element(id: 'hdr')
      assert_equal 'Hello', hdr.text

      # Authentic Ruby symbol finder form (:class -> "class name").
      lnk = driver.find_element(:class, 'nav')
      assert_equal 'a', lnk.tag_name.downcase
      lnk.click

      # By:: constant form (kept as an extra) + symbol :css form.
      box = driver.find_element(Selenium::WebDriver::By::CSS_SELECTOR, '#box')
      box.send_keys('hello world')
      assert_equal 'hello world', box.property('value')
      assert_equal box, driver.find_element(css: '#box')

      assert_equal 42, driver.execute_script('return 40 + 2;')

      driver.set_script_timeout(10_000)
      assert_equal 7, driver.execute_async_script('arguments[arguments.length - 1](3 + 4);')

      assert_raises(Selenium::WebDriver::NoSuchElementError) do
        driver.find_element(Selenium::WebDriver::By::ID, 'does-not-exist')
      end
    ensure
      driver.quit
    end
  end

  # Driver orchestration over the engine: resolve + spawn a chromedriver
  # in-binding (no chromedriver on PATH, no Grid), drive a page through the
  # self-launched driver, and tear the process down — the ensure_driver ->
  # driver_url -> open -> stop_driver flow the C-ABI exposes for FFI bindings.
  def test_live_driver_orchestration
    # Resolve only — self-skip if the engine can't produce a driver here
    # (offline + empty cache). Same self-skip the reference bindings use.
    path = Selenium::WebDriver.resolve_driver('chrome')
    skip 'engine cannot resolve a chromedriver (offline, no cache)' if path.empty?
    assert File.file?(path), "resolve_driver returned a non-file: #{path.inspect}"

    # ensure_driver spawns it; the handle exposes url + pid, independent of any
    # W3C session.
    proc = Selenium::WebDriver.ensure_driver('chrome')
    refute_nil proc, 'ensure_driver returned nil'
    begin
      assert proc.url.start_with?('http'), "driver url=#{proc.url.inspect}"
      assert_operator proc.pid, :>, 0, "driver pid=#{proc.pid}"
    ensure
      proc.stop
      assert_equal 0, proc.pid, 'stop_driver should clear the handle'
    end

    # LocalChrome ties it together: spawn its own driver, run a session, and stop
    # the driver on quit — the whole point of the orchestration ABI.
    chrome_opts = { 'args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'] }
    chrome_bin = ENV.fetch('SEL_CHROME_BINARY', nil)
    chrome_opts['binary'] = chrome_bin if chrome_bin && !chrome_bin.empty?
    driver = Selenium::WebDriver.local_chrome(options: { 'goog:chromeOptions' => chrome_opts })
    begin
      refute_empty driver.session_id, 'no session id from LocalChrome'

      page = 'data:text/html;charset=utf-8,' + CGI.escape(HTML).gsub('+', '%20')
      driver.get(page)
      assert_equal 'Aether Selenium', driver.title
      assert_equal 'Hello', driver.find_element(Selenium::WebDriver::By::ID, 'hdr').text
    ensure
      driver.quit
    end
  end

  # WebDriver-BiDi over the same engine: subscribe to console log entries, emit
  # one via the classic script channel, and receive the event asynchronously —
  # the bidirectional half, driven from Ruby through the demux C ABI.
  def test_live_bidi
    driver = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      assert driver.bidi_available?, 'session negotiated no webSocketUrl'

      page = 'data:text/html;charset=utf-8,' + CGI.escape(HTML).gsub('+', '%20')
      driver.get(page)

      ack = driver.bidi.subscribe(Selenium::WebDriver::BidiEvent::LOG_ENTRY_ADDED)
      assert_equal 'success', ack['type'], "subscribe ack=#{ack.inspect}"

      driver.execute_script("console.log('bidi-hello');")

      ev = driver.bidi.next_event(Selenium::WebDriver::BidiEvent::LOG_ENTRY_ADDED, timeout_ms: 8000)
      refute_nil ev, 'no log.entryAdded event received'
      assert_equal Selenium::WebDriver::BidiEvent::LOG_ENTRY_ADDED, ev['method']
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
      driver.bidi.subscribe(Selenium::WebDriver::BidiEvent::BEFORE_REQUEST_SENT)
      ic = driver.bidi.add_intercept(url_pattern: '')
      refute_nil ic, 'add_intercept should return an intercept id'

      driver.execute_script("fetch('https://example.com/blocked').catch(function(){});")

      ev = driver.bidi.next_event(Selenium::WebDriver::BidiEvent::BEFORE_REQUEST_SENT, timeout_ms: 8000)
      refute_nil ev, 'no network.beforeRequestSent event received'

      rid = Selenium::WebDriver::BiDi.event_request_id(ev)
      refute_nil rid, 'event should carry a request id'

      assert_equal 'success', driver.bidi.continue_request(rid)['type'],
                   'continue_request should succeed'

      # BiDi request mocking: fulfill a paused request with a mock response
      # (never hits the network) and prove the page reads the mocked body.
      driver.execute_script("window.__mock='';fetch('https://example.com/api').then(function(r){return r.text()}).then(function(t){window.__mock=t}).catch(function(){});")
      ev2 = driver.bidi.next_event(Selenium::WebDriver::BidiEvent::BEFORE_REQUEST_SENT, timeout_ms: 8000)
      rid2 = Selenium::WebDriver::BiDi.event_request_id(ev2)
      resp = driver.bidi.provide_response(rid2, status: 200, content_type: 'text/plain', body: 'MOCKED-BODY')
      assert_equal 'success', resp['type']
      got = ''
      25.times { got = driver.execute_script('return window.__mock;').to_s; break if got.include?('MOCKED-BODY'); sleep 0.2 }
      assert got.include?('MOCKED-BODY'), "page did not receive mock: #{got}"

      # BiDi network.setCacheBehavior: bypass the HTTP cache, then restore it.
      assert_equal 'success', driver.bidi.set_cache_behavior('bypass')['type'],
                   'set_cache_behavior("bypass") should succeed'
      assert_equal 'success', driver.bidi.set_cache_behavior('default')['type'],
                   'set_cache_behavior("default") should succeed'
    ensure
      driver.quit
    end
  end

  # BiDi network.continueWithAuth: intercept the authRequired phase, catch the
  # Basic-Auth challenge Chrome raises for a protected fetch, answer it with
  # credentials, and prove the page reads the protected body — the full
  # authRequired -> provideCredentials round-trip.
  def test_live_bidi_auth
    server, srv_port = basic_auth_server
    driver = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      assert driver.bidi_available?, 'session negotiated no webSocketUrl'

      origin = "http://127.0.0.1:#{srv_port}"
      driver.get("#{origin}/")

      driver.bidi.subscribe(Selenium::WebDriver::BidiEvent::AUTH_REQUIRED)
      ic = driver.bidi.add_intercept(phases: 'authRequired')
      refute_nil ic, 'add_intercept(authRequired) should return an intercept id'

      # The protected fetch (same-origin) pauses at the 401 challenge; stash its
      # eventual body in window.__auth.
      driver.execute_script(
        "window.__auth='';fetch('/secret')" \
        '.then(function(r){return r.text()}).then(function(t){window.__auth=t})' \
        ".catch(function(e){window.__auth='ERR:'+e});"
      )

      ev = driver.bidi.next_event(Selenium::WebDriver::BidiEvent::AUTH_REQUIRED, timeout_ms: 8000)
      refute_nil ev, 'no network.authRequired event received'
      assert_equal Selenium::WebDriver::BidiEvent::AUTH_REQUIRED, ev['method']
      rid = Selenium::WebDriver::BiDi.event_request_id(ev)
      refute_nil rid, "event should carry a request id: #{ev.inspect}"

      ack = driver.bidi.continue_with_auth(rid, BASIC_AUTH_USER, BASIC_AUTH_PASS)
      assert_equal 'success', ack['type'], "continue_with_auth=#{ack.inspect}"

      got = ''
      40.times { got = driver.execute_script('return window.__auth;').to_s; break unless got.empty?; sleep 0.2 }
      assert got.include?('THE-SECRET'), "page did not read the protected body: #{got.inspect}"
    ensure
      driver.quit
      server.close
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
    driver = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      page = 'data:text/html;charset=utf-8,' + CGI.escape(ATOMS_HTML).gsub('+', '%20')
      driver.get(page)

      assert driver.find_element(Selenium::WebDriver::By::ID, 'hdr').displayed?,
             '#hdr should be displayed'
      refute driver.find_element(Selenium::WebDriver::By::ID, 'gone').displayed?,
             '#gone (display:none) should not be displayed'

      href = driver.find_element(Selenium::WebDriver::By::ID, 'lnk').attribute('href')
      assert_includes href, 'example.com/x', "unexpected href: #{href.inspect}"

      below = driver.find_relative('button', { kind: 'below', sel: '#hdr' })
      assert_operator below.size, :>=, 1, 'expected >= 1 button below #hdr'
    ensure
      driver.quit
    end
  end

  # The convenience tier end-to-end against real Chrome: an explicit Wait, a
  # Support::Select over a <select>, and an Actions pointer gesture — the three
  # additions exercised through the same engine seam the rest of the binding uses.
  CONV_HTML = '<html><head><title>Convenience</title></head><body>' \
              "<select id='color'>" \
              "<option value='r'>Red</option>" \
              "<option value='g'>Green</option>" \
              "<option value='b'>Blue</option>" \
              '</select>' \
              "<button id='btn' onclick=\"document.getElementById('out').textContent='clicked'\">Go</button>" \
              "<span id='out'>idle</span>" \
              '<script>' \
              "setTimeout(function(){var d=document.createElement('div');" \
              "d.id='later';d.textContent='ready';document.body.appendChild(d);}, 400);" \
              '</script>' \
              '</body></html>'

  def test_live_convenience_tier
    driver = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      page = 'data:text/html;charset=utf-8,' + CGI.escape(CONV_HTML).gsub('+', '%20')
      driver.get(page)

      # Wait: the #later div is injected 400ms after load — poll until it appears.
      wait = Selenium::WebDriver::Wait.new(timeout: 5, interval: 0.1)
      later = wait.until { driver.find_element(id: 'later') }
      assert_equal 'ready', later.text

      # Wait raises TimeoutError when the condition never holds.
      quick = Selenium::WebDriver::Wait.new(timeout: 0.3, interval: 0.05)
      assert_raises(Selenium::WebDriver::TimeoutError) do
        quick.until { driver.find_elements(id: 'never-ever').first }
      end

      # Select: drive the <select> by text / value / index; read back the choice.
      select = Selenium::WebDriver::Support::Select.new(driver.find_element(id: 'color'))
      refute select.multiple?

      select.select_by(:text, 'Green')
      assert_equal 'Green', select.first_selected_option.text
      assert_equal 'g', select.first_selected_option.attribute('value')

      select.select_by(:value, 'b')
      assert_equal 'Blue', select.first_selected_option.text

      select.select_by(:index, 0)
      assert_equal 'Red', select.first_selected_option.text

      assert_raises(Selenium::WebDriver::NoSuchElementError) { select.select_by(:text, 'Purple') }

      # Actions: a pointer click gesture on the button, built as a W3C actions
      # sequence and posted through driver.action.perform.
      btn = driver.find_element(id: 'btn')
      driver.action.click(btn).perform
      assert_equal 'clicked', driver.find_element(id: 'out').text
    ensure
      driver.quit
    end
  end

  # The mainstream ABI facades end-to-end against real Chrome: navigate,
  # switch_to (window/new_window/frame/default_content/alert), manage (cookies /
  # timeouts / window), the canonical Element name, variadic send_keys,
  # screenshot_as, and the Chrome::Options -> .chrome(options:) path — all
  # additive over the same engine seam the flat methods use.
  FACADE_HTML = '<html><head><title>Facades</title></head><body>' \
                "<h1 id='hdr'>Hello</h1>" \
                "<input id='box' name='q'/>" \
                "<button id='al' onclick=\"window.__ok=confirm('sure?')\">alert</button>" \
                '</body></html>'

  def test_live_facades
    # Chrome::Options object flowing through .chrome(options:) — the mainstream
    # construction path (add_argument + to_capabilities).
    opts = Selenium::WebDriver::Chrome::Options.new
    ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'].each { |a| opts.add_argument(a) }
    caps = opts.to_capabilities
    # Keep the modal open for the switch_to.alert round-trip (the W3C default is
    # "dismiss and notify", which auto-dismisses before we can read it).
    caps['unhandledPromptBehavior'] = 'ignore'
    driver = Selenium::WebDriver.chrome("http://127.0.0.1:#{@port}", options: caps)
    begin
      page = 'data:text/html;charset=utf-8,' + CGI.escape(FACADE_HTML).gsub('+', '%20')

      # navigate facade
      driver.navigate.to(page)
      assert_equal 'Facades', driver.title

      # Element canonical name + variadic send_keys
      box = driver.find_element(id: 'box')
      assert_instance_of Selenium::WebDriver::Element, box
      box.send_keys('ab', :arrow_left, 'c') # -> "acb"
      assert_equal 'acb', box.property('value')

      # manage.timeouts (SECONDS) and manage.window
      driver.manage.timeouts.implicit_wait = 1
      driver.manage.window.maximize
      rect = driver.manage.window.rect
      assert rect['width'].positive?

      # manage cookies through the facade (delete-all works on any origin; the
      # add/read round-trip needs an http:// origin — covered in surface_test).
      driver.manage.delete_all_cookies

      # switch_to.new_window (a real second tab), then window(handle) back
      original = driver.window_handle
      driver.switch_to.new_window(:tab)
      refute_equal original, driver.window_handle
      driver.switch_to.window(original)
      assert_equal original, driver.window_handle

      # switch_to.alert -> Alert (accept)
      driver.navigate.to(page)
      driver.find_element(id: 'al').click
      alert = driver.switch_to.alert
      refute_empty alert.text
      alert.accept

      # screenshot_as(:png) yields real PNG bytes
      png = driver.screenshot_as(:png)
      assert_equal "\x89PNG".b, png[0, 4].b

      # driver.status reports a ready remote end
      refute_nil driver.status
    ensure
      driver.quit
    end
  end

  private

  BASIC_AUTH_USER = 'neo'
  BASIC_AUTH_PASS = 'trinity'

  # A tiny in-process HTTP server: a landing page at /, and a Basic-Auth-
  # protected /secret that 401s (with a WWW-Authenticate challenge) until the
  # right credentials arrive — the challenge Chrome surfaces as authRequired.
  # Raw TCPServer thread (no webrick dependency), mirroring the Python harness.
  def basic_auth_server
    require 'base64'
    expected = 'Basic ' + Base64.strict_encode64("#{BASIC_AUTH_USER}:#{BASIC_AUTH_PASS}")
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    Thread.new do
      loop do
        begin
          conn = server.accept
        rescue IOError, Errno::EBADF
          break # server closed
        end
        Thread.new(conn) do |c|
          request_line = c.gets.to_s
          headers = {}
          while (line = c.gets) && line != "\r\n"
            k, v = line.split(':', 2)
            headers[k.to_s.strip.downcase] = v.to_s.strip if v
          end
          path = request_line.split(' ')[1].to_s
          if path == '/secret'
            if headers['authorization'] == expected
              body = 'THE-SECRET'
              c.write "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
            else
              body = 'denied'
              c.write "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"matrix\"\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
            end
          else
            body = '<!doctype html><title>Auth</title><h1>landing</h1>'
            c.write "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
          end
        rescue StandardError
          # best-effort test server
        ensure
          c.close rescue nil
        end
      end
    end
    [server, port]
  end

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
