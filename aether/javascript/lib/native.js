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
  byLocator,
  route,
  buildRequest,
  errorCode,
  takeString,
  isNull,
}
