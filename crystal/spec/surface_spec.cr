# surface_spec.cr — no-browser ABI-surface facts for the Crystal binding.
#
# Pins the pure, browser-free pieces of the full-feature surface: the Keys
# code-points + chord, the By factory family, and the Actions builder's W3C wire
# shape (assembled with no driver call). Needs only the .so link (for the module
# to load). Crystal's built-in `spec` framework.
require "spec"
require "json"
require "../src/selenium"

describe "Selenium ABI surface" do
  describe Selenium::Keys do
    it "carries the W3C PUA code points" do
      Selenium::Keys::NULL[0].ord.should eq(0xE000)
      Selenium::Keys::TAB[0].ord.should eq(0xE004)
      Selenium::Keys::ENTER[0].ord.should eq(0xE007)
      Selenium::Keys::ESCAPE[0].ord.should eq(0xE00C)
      Selenium::Keys::DIVIDE[0].ord.should eq(0xE029)
      Selenium::Keys::F1[0].ord.should eq(0xE031)
      Selenium::Keys::F12[0].ord.should eq(0xE03C)
      Selenium::Keys::META[0].ord.should eq(0xE03D)
    end

    it "aliases agree with their canonical key" do
      Selenium::Keys::BACK_SPACE.should eq(Selenium::Keys::BACKSPACE)
      Selenium::Keys::LEFT_CONTROL.should eq(Selenium::Keys::CONTROL)
      Selenium::Keys::ARROW_LEFT.should eq(Selenium::Keys::LEFT)
      Selenium::Keys::COMMAND.should eq(Selenium::Keys::META)
    end

    it "chord holds the modifier then releases with NULL" do
      s = Selenium::Keys.chord(Selenium::Keys::CONTROL, "a")
      chars = s.chars
      chars[0].to_s.should eq(Selenium::Keys::CONTROL)
      chars[1].should eq('a')
      chars[2].to_s.should eq(Selenium::Keys::NULL)
      chars.size.should eq(3)
    end
  end

  describe Selenium::By do
    it "every factory yields a Locator with the engine strategy string" do
      Selenium::By.id("x").strategy.should eq("id")
      Selenium::By.name("x").strategy.should eq("name")
      Selenium::By.css_selector("x").strategy.should eq("css selector")
      Selenium::By.class_name("x").strategy.should eq("class name")
      Selenium::By.tag_name("x").strategy.should eq("tag name")
      Selenium::By.link_text("x").strategy.should eq("link text")
      Selenium::By.partial_link_text("x").strategy.should eq("partial link text")
      Selenium::By.xpath("x").strategy.should eq("xpath")
    end
  end

  describe Selenium::Actions do
    # Actions#build assembles the W3C actions array with no driver call, so its
    # wire shape is unit-testable. A bare WebElement (driver + id) is enough for
    # the gesture builders, which only read the element's id.
    driver = Selenium::WebDriver.new("http://127.0.0.1:1")

    it "click builds move+down+up on the mouse device" do
      el = Selenium::WebElement.new(driver, "E1")
      built = Selenium::Actions.new(driver).click(el).build
      built.size.should eq(1)
      ptr = built[0]
      ptr["type"].as_s.should eq("pointer")
      ptr["id"].as_s.should eq("mouse")
      ptr.dig("parameters", "pointerType").as_s.should eq("mouse")
      acts = ptr["actions"].as_a
      acts.size.should eq(3)
      acts[0]["type"].as_s.should eq("pointerMove")
      acts[0].dig("origin", Selenium::W3C_ELEMENT_KEY).as_s.should eq("E1")
      acts[1]["type"].as_s.should eq("pointerDown")
      acts[1]["button"].as_i.should eq(0)
      acts[2]["type"].as_s.should eq("pointerUp")
    end

    it "context_click uses button 2" do
      built = Selenium::Actions.new(driver).context_click(Selenium::WebElement.new(driver, "E1")).build
      acts = built[0]["actions"].as_a
      acts[1]["button"].as_i.should eq(2)
      acts[2]["button"].as_i.should eq(2)
    end

    it "double_click emits two down+up pairs" do
      built = Selenium::Actions.new(driver).double_click.build
      acts = built[0]["actions"].as_a
      downs = acts.count { |a| a["type"].as_s == "pointerDown" }
      ups = acts.count { |a| a["type"].as_s == "pointerUp" }
      downs.should eq(2)
      ups.should eq(2)
    end

    it "drag_and_drop is hold+move+release" do
      src = Selenium::WebElement.new(driver, "SRC")
      tgt = Selenium::WebElement.new(driver, "TGT")
      built = Selenium::Actions.new(driver).drag_and_drop(src, tgt).build
      acts = built[0]["actions"].as_a
      acts[0]["type"].as_s.should eq("pointerMove")
      acts[0].dig("origin", Selenium::W3C_ELEMENT_KEY).as_s.should eq("SRC")
      acts[1]["type"].as_s.should eq("pointerDown")
      acts[2]["type"].as_s.should eq("pointerMove")
      acts[2].dig("origin", Selenium::W3C_ELEMENT_KEY).as_s.should eq("TGT")
      acts[3]["type"].as_s.should eq("pointerUp")
    end

    it "send_keys builds the key device with down+up per char" do
      built = Selenium::Actions.new(driver).send_keys("hi").build
      built.size.should eq(1)
      kbd = built[0]
      kbd["type"].as_s.should eq("key")
      kbd["id"].as_s.should eq("keyboard")
      acts = kbd["actions"].as_a
      acts.size.should eq(4)
      acts[0]["type"].as_s.should eq("keyDown")
      acts[0]["value"].as_s.should eq("h")
      acts[3]["value"].as_s.should eq("i")
    end

    it "special key_down/up carries the PUA code point" do
      built = Selenium::Actions.new(driver).key_down(Selenium::Keys::CONTROL).key_up(Selenium::Keys::CONTROL).build
      acts = built[0]["actions"].as_a
      acts[0]["value"].as_s.should eq("\u{E009}")
    end

    it "mixed devices are length-synced with pauses" do
      built = Selenium::Actions.new(driver).click(Selenium::WebElement.new(driver, "E1")).send_keys("x").build
      built.size.should eq(2)
      pointer = built.find { |d| d["type"].as_s == "pointer" }.not_nil!
      key = built.find { |d| d["type"].as_s == "key" }.not_nil!
      pointer["actions"].as_a.size.should eq(key["actions"].as_a.size)
    end

    it "a pause-only sequence emits no device" do
      Selenium::Actions.new(driver).pause(10).build.empty?.should be_true
    end
  end
end
