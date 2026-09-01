# selenium_core.cr — the Crystal binding over the shared Aether engine.
#
# Crystal binds the engine's flat C ABI (aether_sel_embed_*) DIRECTLY via a `lib`
# block — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is resolved at link time via the
# ldflags below (the .tests.ae stages native/ and passes -L/-rpath through
# SELENIUM_CORE_LIB / the shard build flags). This file is the idiomatic Crystal
# surface: a `By` enum-like module, caller-owned-string handling, a typed error,
# and a `WebDriver` with the W3C operations.

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

module SeleniumCore
  # By strategies (the same string values the engine's by_locator expects).
  module By
    ID                = "id"
    NAME              = "name"
    CSS               = "css selector"
    CLASS_NAME        = "className"
    TAG_NAME          = "tag name"
    LINK_TEXT         = "link text"
    PARTIAL_LINK_TEXT = "partial link text"
    XPATH             = "xpath"
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
        msg = SeleniumCore.take(LibSel.last_error(@handle))
        code = LibSel.last_error_code(@handle)
        raise WebDriverError.new(msg, (rc == -1 && code == 0) ? -1 : code)
      end
      SeleniumCore.take(LibSel.last_value(@handle))
    end

    def quit
      execute("quit", "{}") rescue nil
    end

    def session_id : String
      SeleniumCore.take(LibSel.session_id(@handle))
    end
  end
end
