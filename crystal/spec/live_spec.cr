# live_spec.cr — LIVE browser facts for the Crystal binding.
#
# The other Crystal specs are no-browser surface facts: they prove the shadow
# finders and the firefox factory EXIST, which stays green even when the code
# behind them is broken. These drive real browsers through the engine so the
# shadow-DOM path and the firefox() factory are actually executed.
#
# Both legs self-orchestrate through the engine's driver ABI (resolve_driver +
# ensure_driver, docs/Driver-Orchestration-ABI.md) — no driver on PATH and no
# Grid required — and use `data:` pages, so no content server is needed.
require "spec"
require "../src/selenium"

# The engine resolves (and if need be downloads) the driver; empty means it
# genuinely could not, which is the only reason to skip.
private def driver_for(browser : String) : Selenium::DriverProcess?
  return nil if Selenium.resolve_driver(browser).empty?
  Selenium.ensure_driver(browser, "", 20_000)
end

describe "live browser" do
  it "drives a real shadow root through Chrome" do
    proc = driver_for("chrome")
    if proc.nil?
      pending! "engine cannot resolve a chromedriver"
    end
    begin
      d = Selenium::WebDriver.headless_chrome(proc.url)
      begin
        d.session_id.should_not be_empty
        d.get("data:text/html,<!doctype html><title>CrystalLive</title>" \
              "<h1 id=\"hdr\">plain</h1><div id=\"host\"></div>")
        d.title.should eq("CrystalLive")

        # Host an open shadow root, then reach an element INSIDE it — the
        # getShadowRoot -> findElementFromShadowRoot round trip, for real.
        d.execute_script(
          "var h=document.getElementById('host');" \
          "var r=h.attachShadow({mode:'open'});" \
          "r.innerHTML='<p id=\"sinner\">crystal-shadow</p>';")

        host = d.find_element(Selenium::By.id("host"))
        shadow = host.shadow_root
        inner = shadow.find_element(Selenium::By.css_selector("#sinner"))
        inner.text.should eq("crystal-shadow")
        shadow.find_elements(Selenium::By.css_selector("p")).size.should eq(1)

        # A non-host element has no shadow root: W3C code 19.
        expect_raises(Selenium::WebDriverError) do
          d.find_element(Selenium::By.id("hdr")).shadow_root
        end
      ensure
        d.quit
      end
    ensure
      proc.stop
    end
  end

  it "opens a real Firefox session through the firefox factory" do
    proc = driver_for("firefox")
    if proc.nil?
      pending! "engine cannot resolve a geckodriver"
    end
    begin
      d = Selenium::WebDriver.headless_firefox(proc.url)
      begin
        d.session_id.should_not be_empty
        d.get("data:text/html,<!doctype html><title>Aether Firefox</title>" \
              "<h1 id=\"hdr\">Hello FF</h1>")
        d.title.should eq("Aether Firefox")
        d.find_element(Selenium::By.id("hdr")).text.should eq("Hello FF")
      ensure
        d.quit
      end
    ensure
      proc.stop
    end
  end
end
