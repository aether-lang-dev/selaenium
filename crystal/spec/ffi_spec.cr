# ffi_spec.cr — no-browser FFI facts for the Crystal binding.
#
# Proves Crystal drives the engine's flat C ABI directly (via the LibSel `lib`
# block) and that the shared engine helpers marshal correctly. Needs only the .so
# (linked via ldflags / -L native). Crystal's built-in `spec` framework.
require "spec"
require "../src/selenium_core"

describe SeleniumCore do
  it "route" do
    SeleniumCore.route("get").should eq("POST /session/:sessionId/url")
    SeleniumCore.route("nope").should eq("")
  end

  it "error_code" do
    SeleniumCore.error_code("no such element").should eq(17)
    SeleniumCore.error_code("").should eq(0)
  end

  it "locator css" do
    SeleniumCore.locator(SeleniumCore::By::CSS, "div.foo")
      .should eq("{\"using\":\"css selector\",\"value\":\"div.foo\"}")
  end

  it "locator id rewrite" do
    SeleniumCore.locator(SeleniumCore::By::ID, "main").should contain("*[id=")
  end

  it "transport failure -> code -1" do
    d = SeleniumCore::WebDriver.new("http://127.0.0.1:1")
    threw = false
    begin
      d.execute("newSession", "{}")
    rescue e : SeleniumCore::WebDriverError
      threw = e.code == -1
    end
    threw.should be_true
  end
end
