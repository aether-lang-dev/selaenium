# ffi_spec.cr — no-browser FFI facts for the Crystal binding.
#
# Proves Crystal drives the engine's flat C ABI directly (via the LibSel `lib`
# block) and that the shared engine helpers marshal correctly. Needs only the .so
# (linked via ldflags / -L native). Crystal's built-in `spec` framework.
require "spec"
require "../src/selenium"

describe Selenium do
  it "route" do
    Selenium.route("get").should eq("POST /session/:sessionId/url")
    Selenium.route("nope").should eq("")
  end

  it "error_code" do
    Selenium.error_code("no such element").should eq(17)
    Selenium.error_code("").should eq(0)
  end

  it "locator css" do
    Selenium.locator(Selenium::By::CSS, "div.foo")
      .should eq("{\"using\":\"css selector\",\"value\":\"div.foo\"}")
  end

  it "locator id rewrite" do
    Selenium.locator(Selenium::By::ID, "main").should contain("*[id=")
  end

  it "By factory yields a Locator carrying strategy + value" do
    loc = Selenium::By.id("hdr")
    loc.strategy.should eq("id")
    loc.value.should eq("hdr")
  end

  it "By.class_name maps to the W3C 'class name'" do
    Selenium::By.class_name("btn").strategy.should eq("class name")
    Selenium::By::CLASS_NAME.should eq("class name")
  end

  it "transport failure -> code -1" do
    d = Selenium::WebDriver.new("http://127.0.0.1:1")
    threw = false
    begin
      d.execute("newSession", "{}")
    rescue e : Selenium::WebDriverError
      threw = e.code == -1
    end
    threw.should be_true
  end
end
