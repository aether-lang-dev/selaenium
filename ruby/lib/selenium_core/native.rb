# frozen_string_literal: true

require 'fiddle'
require 'rbconfig'

module SeleniumCore
  # Raw Fiddle binding over the native Selenium core library (the
  # +aether_sel_embed_*+ C ABI exported by +core/embed.ae+, built on the pure
  # -Aether +core/selenium_core.ae+ engine). 1:1 with the C symbols; everything
  # idiomatic lives a layer up in {SeleniumCore::WebDriver}.
  #
  # Handle-based contract (matching the Aether side): N independent WebDriver
  # sessions can run concurrently in one process, each keyed by its own handle;
  # every execute / accessor call takes that handle.
  #
  # Returned +char*+ values are caller-owned and NUL-terminated; copy them to a
  # Ruby String and free them with +free_string+. {.take_string} does exactly
  # that and is the only safe way to read a returned string.
  module Native
    module_function

    # Pin an explicit path to the native library, used at first load. Backs the
    # first-class +native_lib=+ argument; wins over the bundled-+native/+ default
    # and the +SELENIUM_CORE_LIB+ env override. No-op once already loaded.
    def configure(path)
      @explicit_path = path if path && !path.empty? && @lib.nil?
    end

    def library_candidates
      candidates = []
      candidates << @explicit_path if @explicit_path && !@explicit_path.empty?
      override = ENV.fetch('SELENIUM_CORE_LIB', nil)
      candidates << override if override && !override.empty?
      candidates << File.join(__dir__, 'native', library_filename)
      candidates << library_filename
      candidates
    end

    def library_filename
      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/ then 'selenium_core.dll'
      when /darwin/             then 'libselenium_core.dylib'
      else                           'libselenium_core.so'
      end
    end

    def open_library
      last_error = nil
      library_candidates.each do |path|
        return Fiddle.dlopen(path)
      rescue Fiddle::DLError => e
        last_error = e
      end
      raise LoadError,
            "could not load native Selenium core library " \
            "(tried: #{library_candidates.join(', ')}): #{last_error}"
    end

    VOIDP = Fiddle::TYPE_VOIDP
    INT   = Fiddle::TYPE_INT
    VOID  = Fiddle::TYPE_VOID

    # (ruby_name, c_symbol, return_type, [arg_types])
    BINDINGS = [
      [:open,            'aether_sel_embed_open',            VOIDP, [VOIDP]],
      [:close,           'aether_sel_embed_close',           VOID,  [VOIDP]],
      [:execute,         'aether_sel_embed_execute',         INT,   [VOIDP, VOIDP, VOIDP]],
      [:last_value,      'aether_sel_embed_last_value',      VOIDP, [VOIDP]],
      [:last_status,     'aether_sel_embed_last_status',     INT,   [VOIDP]],
      [:last_error_code, 'aether_sel_embed_last_error_code', INT,   [VOIDP]],
      [:last_error,      'aether_sel_embed_last_error',      VOIDP, [VOIDP]],
      [:session_id,      'aether_sel_embed_session_id',      VOIDP, [VOIDP]],
      [:by_locator,      'aether_sel_embed_by_locator',      VOIDP, [VOIDP, VOIDP]],
      [:route,           'aether_sel_embed_route',           VOIDP, [VOIDP]],
      [:build_request,   'aether_sel_embed_build_request',   VOIDP, [VOIDP, VOIDP, VOIDP]],
      [:error_code,      'aether_sel_embed_error_code',      INT,   [VOIDP]],
      # ---- atom-backed commands (isDisplayed/getAttribute/relative locators, run in-page) ----
      [:execute_atom,    'aether_sel_embed_execute_atom',    INT,   [VOIDP, VOIDP, VOIDP, VOIDP]],
      [:is_displayed,    'aether_sel_embed_is_displayed',    INT,   [VOIDP, VOIDP]],
      [:get_attribute,   'aether_sel_embed_get_attribute',   INT,   [VOIDP, VOIDP, VOIDP]],
      [:atom_str_arg,    'aether_sel_embed_atom_str_arg',    VOIDP, [VOIDP]],
      [:find_relative,   'aether_sel_embed_find_relative',   INT,   [VOIDP, VOIDP, VOIDP]],
      # ---- WebDriver-BiDi (over the session's webSocketUrl) ----
      [:bidi_open,        'aether_sel_embed_bidi_open',        VOIDP, [VOIDP]],
      [:bidi_close,       'aether_sel_embed_bidi_close',       VOID,  [VOIDP]],
      [:bidi_send,        'aether_sel_embed_bidi_send',        INT,   [VOIDP, INT, VOIDP, VOIDP]],
      [:bidi_pump,        'aether_sel_embed_bidi_pump',        INT,   [VOIDP, INT]],
      [:bidi_fd,          'aether_sel_embed_bidi_fd',          INT,   [VOIDP]],
      [:bidi_poll_reply,  'aether_sel_embed_bidi_poll_reply',  VOIDP, [VOIDP, INT]],
      [:bidi_poll_event,  'aether_sel_embed_bidi_poll_event',  VOIDP, [VOIDP]],
      [:bidi_lost_events, 'aether_sel_embed_bidi_lost_events', INT,   [VOIDP]],
      [:bidi_cancel,      'aether_sel_embed_bidi_cancel',      VOID,  [VOIDP, INT]],
      [:bidi_subscribe,   'aether_sel_embed_bidi_subscribe',   VOIDP, [VOIDP, INT, VOIDP, INT]],
      [:bidi_unsubscribe, 'aether_sel_embed_bidi_unsubscribe', VOIDP, [VOIDP, INT, VOIDP, INT]],
      [:bidi_wait_event,  'aether_sel_embed_bidi_wait_event',  VOIDP, [VOIDP, VOIDP, INT]],
      # ---- typed BiDi convenience commands (reply JSON, caller frees via take_string) ----
      [:bidi_get_tree,        'aether_sel_embed_bidi_get_tree',        VOIDP, [VOIDP, INT, INT]],
      [:bidi_script_evaluate, 'aether_sel_embed_bidi_script_evaluate', VOIDP, [VOIDP, INT, VOIDP, VOIDP, INT]],
      [:bidi_navigate,        'aether_sel_embed_bidi_navigate',        VOIDP, [VOIDP, INT, VOIDP, VOIDP, INT]],
      # ---- BiDi network interception (observe / release / block requests) ----
      [:bidi_network_add_intercept,     'aether_sel_embed_bidi_network_add_intercept',     VOIDP, [VOIDP, INT, VOIDP, VOIDP, INT]],
      [:bidi_network_remove_intercept,  'aether_sel_embed_bidi_network_remove_intercept',  VOIDP, [VOIDP, INT, VOIDP, INT]],
      [:bidi_network_continue_request,  'aether_sel_embed_bidi_network_continue_request',  VOIDP, [VOIDP, INT, VOIDP, INT]],
      [:bidi_network_fail_request,      'aether_sel_embed_bidi_network_fail_request',      VOIDP, [VOIDP, INT, VOIDP, INT]],
      [:bidi_network_provide_response,  'aether_sel_embed_bidi_network_provide_response',  VOIDP, [VOIDP, INT, VOIDP, INT, VOIDP, VOIDP, INT]],
      [:free_string,     'aether_sel_embed_free_string',     VOID,  [VOIDP]]
    ].freeze

    def lib
      @lib ||= open_library
    end

    def functions
      @functions ||= BINDINGS.each_with_object({}) do |(name, sym, ret, args), acc|
        acc[name] = Fiddle::Function.new(lib[sym], args, ret)
      end
    end

    def call(name, *args)
      functions.fetch(name).call(*args)
    end

    # Copy a caller-owned native +char*+ into a Ruby String, then free the
    # original pointer per the ABI ownership rule. Returns "" for NULL.
    def take_string(ptr)
      return '' if ptr.nil? || (ptr.respond_to?(:null?) && ptr.null?)

      str = ptr.to_s
      call(:free_string, ptr)
      str
    end
  end
end
