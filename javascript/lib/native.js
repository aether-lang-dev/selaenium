// Centralized koffi binding to the native Selenium core library.
//
// 1:1 with the `aether_sel_embed_*` C ABI exported by the in-repo
// `core/embed.ae` (the engine itself is `core/selenium_core.ae`). The opaque
// session handle is a `void*`; NULL means open failed. Every `char*` returned
// by the ABI is caller-owned and NUL-terminated — `takeString` decodes it into
// a JS string and then frees it via `aether_sel_embed_free_string`, per the
// ABI's ownership rule.
//
// Handle-based contract (matching the Aether side): N independent sessions can
// run concurrently in one process, each keyed by its own handle; every execute
// / accessor call takes that handle.

'use strict'

const fs = require('fs')
const path = require('path')
const koffi = require('koffi')

const LIB_BASE = 'selenium_core'

function fileName() {
  switch (process.platform) {
    case 'win32':
      return `${LIB_BASE}.dll`
    case 'darwin':
      return `lib${LIB_BASE}.dylib`
    default:
      return `lib${LIB_BASE}.so`
  }
}

let explicitPath = null
let loadedLib = null

/**
 * Pin an explicit path to the native library, used at first load. Wins over the
 * bundled `native/` default and the SELENIUM_CORE_LIB env override. No-op once
 * loaded.
 */
function configure(nativeLib) {
  if (nativeLib && !loadedLib) explicitPath = nativeLib
}

function resolveLibraryPath() {
  if (explicitPath && fs.existsSync(explicitPath)) return explicitPath
  const override = process.env.SELENIUM_CORE_LIB
  if (override && fs.existsSync(override)) return override
  const bundled = path.resolve(__dirname, '..', 'native', fileName())
  if (fs.existsSync(bundled)) return bundled
  return fileName()
}

function lib() {
  if (!loadedLib) loadedLib = koffi.load(resolveLibraryPath())
  return loadedLib
}

// Lazily bind a native function so a pinned explicit path takes effect.
function lazy(signature) {
  let f = null
  return (...args) => {
    if (!f) f = lib().func(signature)
    return f(...args)
  }
}

// ---- lifecycle ----
const open = lazy('void* aether_sel_embed_open(const char* base_url)')
const close = lazy('void aether_sel_embed_close(void* h)')

// ---- workhorse ----
const execute = lazy('int aether_sel_embed_execute(void* h, const char* name, const char* params_json)')

// ---- result accessors ----
const lastValue = lazy('void* aether_sel_embed_last_value(void* h)')
const lastStatus = lazy('int aether_sel_embed_last_status(void* h)')
const lastErrorCode = lazy('int aether_sel_embed_last_error_code(void* h)')
const lastError = lazy('void* aether_sel_embed_last_error(void* h)')
const sessionId = lazy('void* aether_sel_embed_session_id(void* h)')

// ---- pure helpers ----
const byLocator = lazy('void* aether_sel_embed_by_locator(const char* strategy, const char* value)')
const route = lazy('void* aether_sel_embed_route(const char* name)')
const buildRequest = lazy('void* aether_sel_embed_build_request(const char* name, const char* session_id, const char* params_json)')
const errorCode = lazy('int aether_sel_embed_error_code(const char* w3c_error)')

// ---- atom-backed commands (a shared JS atom run in-page by the engine) ----
// isDisplayed / getAttribute / relative-locator all execute the same JS atoms
// upstream Selenium ships, via the engine's executeScript path. Results drain
// through the usual last_value channel. char* args/returns go through void*.
const executeAtom = lazy(
  'int aether_sel_embed_execute_atom(void* h, const char* atom, const char* elem_id, const char* extra_json)',
)
const isDisplayed = lazy('int aether_sel_embed_is_displayed(void* h, const char* elem_id)')
const getAttribute = lazy('int aether_sel_embed_get_attribute(void* h, const char* elem_id, const char* name)')
const atomStrArg = lazy('void* aether_sel_embed_atom_str_arg(const char* s)')
const findRelative = lazy('int aether_sel_embed_find_relative(void* h, const char* base_css, const char* filters_json)')

// ---- TLS config (per session handle; set before newSession) ----
const setCa = lazy('void aether_sel_embed_set_ca(void* h, const char* ca_path)')
const setInsecure = lazy('void aether_sel_embed_set_insecure(void* h, int on)')

// ---- driver orchestration (spawn/adopt a driver process in-binding) ----
// An opaque driver handle, independent of the W3C session handle. launch_driver
// and ensure_driver return that handle (void*); driver_url returns a caller-owned
// char* (as void*, taken via takeString); driver_pid returns int.
const resolveDriver = lazy('void* aether_sel_embed_resolve_driver(const char* browser, const char* hint)')
const launchDriver = lazy('void* aether_sel_embed_launch_driver(const char* driver_path, int timeout_ms)')
const ensureDriver = lazy('void* aether_sel_embed_ensure_driver(const char* browser, const char* hint, int timeout_ms)')
const driverUrl = lazy('void* aether_sel_embed_driver_url(void* dh)')
const driverPid = lazy('int aether_sel_embed_driver_pid(void* dh)')
const stopDriver = lazy('void aether_sel_embed_stop_driver(void* dh)')

// ---- WebDriver-BiDi (over the session's webSocketUrl) ----
// An opaque BiDi channel handle, independent of the W3C session handle.
const bidiOpen = lazy('void* aether_sel_embed_bidi_open(const char* ws_url)')
const bidiClose = lazy('void aether_sel_embed_bidi_close(void* h)')
const bidiSend = lazy('int aether_sel_embed_bidi_send(void* h, int id, const char* method, const char* params_json)')
const bidiPump = lazy('int aether_sel_embed_bidi_pump(void* h, int timeout_ms)')
const bidiFd = lazy('int aether_sel_embed_bidi_fd(void* h)')
const bidiPollReply = lazy('void* aether_sel_embed_bidi_poll_reply(void* h, int id)')
const bidiPollEvent = lazy('void* aether_sel_embed_bidi_poll_event(void* h)')
const bidiLostEvents = lazy('int aether_sel_embed_bidi_lost_events(void* h)')
const bidiCancel = lazy('void aether_sel_embed_bidi_cancel(void* h, int id)')
const bidiSubscribe = lazy('void* aether_sel_embed_bidi_subscribe(void* h, int id, const char* events_csv, int timeout_ms)')
const bidiUnsubscribe = lazy('void* aether_sel_embed_bidi_unsubscribe(void* h, int id, const char* events_csv, int timeout_ms)')
const bidiWaitEvent = lazy('void* aether_sel_embed_bidi_wait_event(void* h, const char* method, int timeout_ms)')

// ---- typed BiDi convenience commands (char* replies returned as void*) ----
const bidiGetTree = lazy('void* aether_sel_embed_bidi_get_tree(void* h, int id, int timeout_ms)')
const bidiScriptEvaluate = lazy(
  'void* aether_sel_embed_bidi_script_evaluate(void* h, int id, const char* expr, const char* context_id, int timeout_ms)',
)
const bidiNavigate = lazy(
  'void* aether_sel_embed_bidi_navigate(void* h, int id, const char* context_id, const char* url, int timeout_ms)',
)

// ---- BiDi network interception (char* replies returned as void*) ----
const bidiNetworkAddIntercept = lazy(
  'void* aether_sel_embed_bidi_network_add_intercept(void* h, int id, const char* phases_csv, const char* url_pattern, int timeout_ms)',
)
const bidiNetworkRemoveIntercept = lazy(
  'void* aether_sel_embed_bidi_network_remove_intercept(void* h, int id, const char* intercept_id, int timeout_ms)',
)
const bidiNetworkContinueRequest = lazy(
  'void* aether_sel_embed_bidi_network_continue_request(void* h, int id, const char* request_id, int timeout_ms)',
)
const bidiNetworkFailRequest = lazy(
  'void* aether_sel_embed_bidi_network_fail_request(void* h, int id, const char* request_id, int timeout_ms)',
)
const bidiNetworkProvideResponse = lazy(
  'void* aether_sel_embed_bidi_network_provide_response(void* h, int id, const char* request_id, int status, const char* content_type, const char* body, int timeout_ms)',
)
const bidiNetworkContinueWithAuth = lazy(
  'void* aether_sel_embed_bidi_network_continue_with_auth(void* h, int id, const char* request_id, const char* username, const char* password, int timeout_ms)',
)
const bidiNetworkSetCacheBehavior = lazy(
  'void* aether_sel_embed_bidi_network_set_cache_behavior(void* h, int id, const char* behavior, int timeout_ms)',
)

// ---- string ownership ----
const freeString = lazy('void aether_sel_embed_free_string(void* s)')

function isNull(ptr) {
  return !ptr || koffi.address(ptr) === 0n
}

// Decode a caller-owned native char* into a JS string, then free it. "" on NULL.
function takeString(ptr) {
  if (isNull(ptr)) return ''
  try {
    return koffi.decode(ptr, 'char', -1)
  } finally {
    freeString(ptr)
  }
}

module.exports = {
  configure,
  open,
  close,
  execute,
  lastValue,
  lastStatus,
  lastErrorCode,
  lastError,
  sessionId,
  executeAtom,
  isDisplayed,
  getAttribute,
  atomStrArg,
  findRelative,
  byLocator,
  route,
  buildRequest,
  errorCode,
  setCa,
  setInsecure,
  resolveDriver,
  launchDriver,
  ensureDriver,
  driverUrl,
  driverPid,
  stopDriver,
  bidiOpen,
  bidiClose,
  bidiSend,
  bidiPump,
  bidiFd,
  bidiPollReply,
  bidiPollEvent,
  bidiLostEvents,
  bidiCancel,
  bidiSubscribe,
  bidiUnsubscribe,
  bidiWaitEvent,
  bidiGetTree,
  bidiScriptEvaluate,
  bidiNavigate,
  bidiNetworkAddIntercept,
  bidiNetworkRemoveIntercept,
  bidiNetworkContinueRequest,
  bidiNetworkFailRequest,
  bidiNetworkProvideResponse,
  bidiNetworkContinueWithAuth,
  bidiNetworkSetCacheBehavior,
  takeString,
  isNull,
}
