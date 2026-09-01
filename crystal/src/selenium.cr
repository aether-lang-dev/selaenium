# selenium.cr — the Crystal binding over the shared Aether engine.
#
# Crystal binds the engine's flat C ABI (aether_sel_embed_*) DIRECTLY via a `lib`
# block — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is resolved at link time via the
# ldflags below (the .tests.ae stages native/ and passes -L/-rpath through
# SELENIUM_CORE_LIB / the shard build flags). This file is the idiomatic Crystal
# surface: a `By` factory (Selenium 4.x shape), caller-owned-string handling, a
# typed error, and a `WebDriver` with the W3C operations.

require "json"

@[Link(ldflags: "-lselenium_core")]
lib LibSel
  fun open = aether_sel_embed_open(base_url : LibC::Char*) : Void*
  fun close = aether_sel_embed_close(h : Void*) : Void
  fun execute = aether_sel_embed_execute(h : Void*, name : LibC::Char*, params_json : LibC::Char*) : LibC::Int
  fun last_value = aether_sel_embed_last_value(h : Void*) : LibC::Char*
  fun last_error_code = aether_sel_embed_last_error_code(h : Void*) : LibC::Int
  fun last_error = aether_sel_embed_last_error(h : Void*) : LibC::Char*
  fun session_id = aether_sel_embed_session_id(h : Void*) : LibC::Char*
  fun by_locator = aether_sel_embed_by_locator(strategy : LibC::Char*, value : LibC::Char*) : LibC::Char*
  fun route = aether_sel_embed_route(name : LibC::Char*) : LibC::Char*
  fun error_code = aether_sel_embed_error_code(w3c_error : LibC::Char*) : LibC::Int
  fun free_string = aether_sel_embed_free_string(s : LibC::Char*) : LibC::Char*
end

module Selenium
  # A locator carrying a (strategy, value) pair — what `By.id("x")` returns and
  # what `WebDriver#find_element` takes (Selenium 4.x one-arg find).
  struct Locator
    getter strategy : String
    getter value : String

    def initialize(@strategy : String, @value : String)
    end
  end

  # By: a factory returning a `Locator`, mirroring Java's `By.id("x")`. The
  # strategy strings are the same values the engine's by_locator expects.
  # CLASS_NAME is the W3C "class name" (not "className").
  module By
    # Strategy-name constants (kept for the legacy two-arg find and for callers
    # that build a locator string via `Selenium.locator`).
    ID                = "id"
    NAME              = "name"
    CSS               = "css selector"
    CLASS_NAME        = "class name"
    TAG_NAME          = "tag name"
    LINK_TEXT         = "link text"
    PARTIAL_LINK_TEXT = "partial link text"
    XPATH             = "xpath"

    def self.id(value : String) : Locator
      Locator.new("id", value)
    end

    def self.name(value : String) : Locator
      Locator.new("name", value)
    end

    def self.css_selector(value : String) : Locator
      Locator.new("css selector", value)
    end

    def self.class_name(value : String) : Locator
      Locator.new("class name", value)
    end

    def self.tag_name(value : String) : Locator
      Locator.new("tag name", value)
    end

    def self.link_text(value : String) : Locator
      Locator.new("link text", value)
    end

    def self.partial_link_text(value : String) : Locator
      Locator.new("partial link text", value)
    end

    def self.xpath(value : String) : Locator
      Locator.new("xpath", value)
    end
  end

  # A typed WebDriver error (-1 = transport failure).
  class WebDriverError < Exception
    getter code : Int32

    def initialize(@message : String, @code : Int32)
      super(@message)
    end
  end

  # Take ownership of an engine-returned C string: copy to a Crystal String, then
  # free it via the engine's allocator (never LibC.free).
  private def self.take(ptr : LibC::Char*) : String
    return "" if ptr.null?
    s = String.new(ptr)
    LibSel.free_string(ptr)
    s
  end

  # ---- pure engine helpers (no session) — shared with every binding ----

  def self.route(command : String) : String
    take(LibSel.route(command))
  end

  def self.error_code(w3c_error : String) : Int32
    LibSel.error_code(w3c_error)
  end

  def self.locator(by : String, value : String) : String
    take(LibSel.by_locator(by, value))
  end

  # ---- session ----

  class WebDriver
    # Open a session bound to a remote-end URL. No I/O until execute("newSession").
    def initialize(command_executor : String)
      @handle = LibSel.open(command_executor)
    end

    def finalize
      LibSel.close(@handle)
    end

    # Run a command by name with JSON params; return the result value (raw JSON),
    # raising a typed WebDriverError on a protocol/transport error.
    def execute(name : String, params_json : String = "{}") : String
      rc = LibSel.execute(@handle, name, params_json)
      if rc != 0
        msg = Selenium.take(LibSel.last_error(@handle))
        code = LibSel.last_error_code(@handle)
        raise WebDriverError.new(msg, (rc == -1 && code == 0) ? -1 : code)
      end
      Selenium.take(LibSel.last_value(@handle))
    end

    # Find one element by a `By` locator (Selenium 4.x one-arg find):
    #   driver.find_element(Selenium::By.id("hdr"))
    # Returns the opaque W3C element id string. Raises WebDriverError(17) when
    # the response carries no element reference.
    def find_element(locator : Locator) : String
      params = Selenium.locator(locator.strategy, locator.value)
      v = execute("findElement", params)
      eid = extract_element_id(v)
      raise WebDriverError.new("element reference key missing", 17) if eid.nil?
      eid
    end

    # Find all elements matching a `By` locator; returns their element ids.
    def find_elements(locator : Locator) : Array(String)
      params = Selenium.locator(locator.strategy, locator.value)
      v = execute("findElements", params)
      parsed = JSON.parse(v)
      out = [] of String
      parsed.as_a.each do |el|
        id = el[W3C_ELEMENT_KEY]?
        out << id.as_s if id
      end
      out
    end

    def quit
      execute("quit", "{}") rescue nil
    end

    def session_id : String
      Selenium.take(LibSel.session_id(@handle))
    end

    W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

    private def extract_element_id(value_json : String) : String?
      parsed = JSON.parse(value_json)
      id = parsed[W3C_ELEMENT_KEY]?
      id ? id.as_s : nil
    end
  end
end
