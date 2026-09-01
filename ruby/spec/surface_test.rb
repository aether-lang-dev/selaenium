# frozen_string_literal: true

# Live surface-coverage test (Ruby): cookies, navigation history, windows, W3C
# actions, screenshot, and execute_script return shapes against a real headless
# Chrome served by a local WEBrick server (so cookies/navigation have a real
# http:// origin). Skips if chromedriver is absent.

require 'minitest/autorun'
require 'socket'
require 'base64'
require 'webrick'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'selenium-webdriver'

class SurfaceTest < Minitest::Test
  PAGE_ONE = '<!doctype html><title>Page One</title>' \
             '<h1 id="hdr">One</h1><a id="go" href="/two">to two</a>' \
             '<button id="btn" onclick="document.getElementById(\'hdr\').textContent=\'clicked\'">b</button>'
  PAGE_TWO = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>'

  def setup
    @driver_bin = which('chromedriver')
    skip 'chromedriver not on PATH' unless @driver_bin

    @web = WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0,
                                   Logger: WEBrick::Log.new(File::NULL),
                                   AccessLog: [])
    @web.mount_proc('/') do |req, res|
      res.content_type = 'text/html; charset=utf-8'
      res.body = req.path.start_with?('/two') ? PAGE_TWO : PAGE_ONE
    end
    @web_port = @web.config[:Port]
    @web_thread = Thread.new { @web.start }

    @port = free_port
    @cd = spawn(@driver_bin, "--port=#{@port}", out: File::NULL, err: File::NULL)
    skip 'chromedriver did not come up' unless wait_up(@port)
  end

  def teardown
    @web&.shutdown
    @web_thread&.join(2)
    return unless @cd

    Process.kill('TERM', @cd)
    Process.wait(@cd)
  rescue Errno::ESRCH, Errno::ECHILD
    # gone
  end

  def test_surface
    base = "http://127.0.0.1:#{@web_port}"
    d = Selenium::WebDriver.headless_chrome("http://127.0.0.1:#{@port}")
    begin
      d.get("#{base}/one")
      assert_equal 'Page One', d.title

      # navigation history
      d.find_element(Selenium::WebDriver::By::ID, 'go').click
      assert_equal 'Page Two', d.title
      d.back
      assert_equal 'Page One', d.title
      d.forward
      assert_equal 'Page Two', d.title
      d.back

      # cookies
      d.delete_all_cookies
      d.add_cookie('name' => 'flavor', 'value' => 'mint')
      assert_equal 'mint', d.cookie('flavor')['value']
      assert(d.cookies.any? { |c| c['name'] == 'flavor' })
      d.delete_cookie('flavor')
      refute(d.cookies.any? { |c| c['name'] == 'flavor' })

      # windows
      handles = d.window_handles
      assert handles.length >= 1
      assert_includes handles, d.current_window_handle
      d.set_window_rect('width' => 900, 'height' => 650)
      assert_equal 900, d.window_rect['width']

      # execute_script shapes
      assert_equal 42, d.execute_script('return 6*7;')
      assert_equal 'hi', d.execute_script("return 'hi';")
      assert_equal [1, 2, 3], d.execute_script('return [1,2,3];')
      assert_equal({ 'a' => 1 }, d.execute_script('return {a:1};'))
      assert_equal 42, d.execute_script('return arguments[0]+arguments[1];', 40, 2)

      # W3C actions: pointer click on the button.
      btn = d.find_element(Selenium::WebDriver::By::ID, 'btn')
      rect = btn.rect
      cx = (rect['x'] + rect['width'] / 2).to_i
      cy = (rect['y'] + rect['height'] / 2).to_i
      d.perform_actions([{
                          'type' => 'pointer', 'id' => 'mouse',
                          'parameters' => { 'pointerType' => 'mouse' },
                          'actions' => [
                            { 'type' => 'pointerMove', 'duration' => 0, 'x' => cx, 'y' => cy },
                            { 'type' => 'pointerDown', 'button' => 0 },
                            { 'type' => 'pointerUp', 'button' => 0 }
                          ]
                        }])
      assert_equal 'clicked', d.find_element(Selenium::WebDriver::By::ID, 'hdr').text
      d.clear_actions

      # screenshot -> PNG
      raw = Base64.decode64(d.screenshot_base64)
      assert_equal "\x89PNG".b, raw[0, 4].b
    ensure
      d.quit
    end
  end

  private

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
end
