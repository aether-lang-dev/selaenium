// The ergonomic Node WebDriver surface — a thin layer over the Aether core.
//
// NOTE: the calls are SYNCHRONOUS. The engine's execute() is a blocking FFI
// round-trip (koffi calls block), so this binding exposes a synchronous API
// rather than faking promises around a blocking call. This differs from the
// upstream selenium-webdriver (which is async over an async HTTP client), but
// it is the honest shape for a linked-in synchronous core and keeps the binding
// a pure marshalling layer. Carries NO protocol logic — every command is one
// native.execute() call plus JSON marshalling.

'use strict'

const native = require('./native')

// The W3C element-reference key: a findElement result is
// { "element-6066-11e4-a52e-4f735466cecf": "<id>" }.
const W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf'

// Locator strategies. Values match the engine's by_locator strategy strings;
// id/name/className are rewritten to CSS in the engine.
const By = {
  ID: 'id',
  NAME: 'name',
  CSS_SELECTOR: 'css selector',
  CLASS_NAME: 'className',
  TAG_NAME: 'tag name',
  LINK_TEXT: 'link text',
  PARTIAL_LINK_TEXT: 'partial link text',
  XPATH: 'xpath',
}

class WebDriverError extends Error {
  constructor(message = '', code = 0) {
    super(message)
    this.name = 'WebDriverError'
    this.code = code
  }
}
class NoSuchElementError extends WebDriverError {}
class StaleElementReferenceError extends WebDriverError {}
class ElementClickInterceptedError extends WebDriverError {}
class ElementNotInteractableError extends WebDriverError {}
class InvalidSelectorError extends WebDriverError {}
class TimeoutError extends WebDriverError {}
class JavascriptError extends WebDriverError {}
class UnknownCommandError extends WebDriverError {}

// Engine integer error codes -> error class (see core error_code()).
const CODE_TO_EXC = {
  3: ElementClickInterceptedError,
  4: ElementNotInteractableError,
  11: InvalidSelectorError,
  13: JavascriptError,
  17: NoSuchElementError,
  21: TimeoutError,
  23: StaleElementReferenceError,
  24: TimeoutError,
  28: UnknownCommandError,
}

function raiseFor(code, message) {
  const Ctor = CODE_TO_EXC[code] || WebDriverError
  throw new Ctor(message, code)
}

function decodeBy(by, value) {
  return JSON.parse(native.takeString(native.byLocator(by, value)))
}

class WebElement {
  constructor(driver, id) {
    this._driver = driver
    this._id = id
  }

  get id() {
    return this._id
  }

  _exec(command, params = {}) {
    return this._driver._execute(command, { ...params, id: this._id })
  }

  click() {
    this._exec('clickElement')
  }
  clear() {
    this._exec('clearElement')
  }
  sendKeys(text) {
    this._exec('sendKeysToElement', { text, value: Array.from(text) })
  }
  get text() {
    return this._exec('getElementText')
  }
  get tagName() {
    return this._exec('getElementTagName')
  }
  getAttribute(name) {
    return this._exec('getDomAttribute', { name })
  }
  getProperty(name) {
    return this._exec('getElementProperty', { name })
  }
  isEnabled() {
    return !!this._exec('isElementEnabled')
  }
  isSelected() {
    return !!this._exec('isElementSelected')
  }
  get rect() {
    return this._exec('getElementRect')
  }
}

class WebDriver {
  constructor(commandExecutor, capabilities) {
    this._handle = native.open(commandExecutor)
    if (native.isNull(this._handle)) {
      throw new WebDriverError('failed to open session handle', -1)
    }
    // Request a BiDi channel so `.bidi` is available on demand; the channel
    // itself is opened lazily (a classic script never opens the WebSocket).
    const caps = { ...capabilities, webSocketUrl: true }
    const result = this._execute('newSession', { capabilities: { alwaysMatch: caps } })
    // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
    this._wsUrl = (result && result.capabilities && result.capabilities.webSocketUrl) || ''
    this._bidi = null
  }

  static chrome(commandExecutor = 'http://127.0.0.1:9515', options = null) {
    const caps = { browserName: 'chrome' }
    if (options) Object.assign(caps, options)
    return new WebDriver(commandExecutor, caps)
  }

  static headlessChrome(commandExecutor = 'http://127.0.0.1:9515') {
    return WebDriver.chrome(commandExecutor, {
      'goog:chromeOptions': {
        args: ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
      },
    })
  }

  // The FFI seam: one command by name with a params object. Returns the decoded
  // `value` payload, or throws a typed WebDriverError.
  _execute(command, params = {}) {
    const rc = native.execute(this._handle, command, JSON.stringify(params))
    if (rc !== 0) {
      const code = native.lastErrorCode(this._handle)
      const message = native.takeString(native.lastError(this._handle))
      if (rc === -1 && code === 0) {
        throw new WebDriverError(message || 'transport failure', -1)
      }
      raiseFor(code, message)
    }
    const raw = native.takeString(native.lastValue(this._handle))
    if (raw === '') return null
    return JSON.parse(raw)
  }

  // ---- navigation ----
  get(url) {
    this._execute('get', { url })
  }
  get currentUrl() {
    return this._execute('getCurrentUrl')
  }
  get title() {
    return this._execute('getTitle')
  }
  get pageSource() {
    return this._execute('getPageSource')
  }
  back() {
    this._execute('goBack')
  }
  forward() {
    this._execute('goForward')
  }
  refresh() {
    this._execute('refresh')
  }

  // ---- elements ----
  findElement(by, value) {
    const result = this._execute('findElement', decodeBy(by, value))
    return new WebElement(this, result[W3C_ELEMENT_KEY])
  }
  findElements(by, value) {
    const result = this._execute('findElements', decodeBy(by, value))
    return result.map((e) => new WebElement(this, e[W3C_ELEMENT_KEY]))
  }

  // ---- script ----
  executeScript(script, ...args) {
    return this._execute('executeScript', { script, args })
  }

  // ---- windows ----
  get windowHandles() {
    return this._execute('getWindowHandles')
  }
  get currentWindowHandle() {
    return this._execute('getCurrentWindowHandle')
  }
  setWindowRect(rect) {
    return this._execute('setWindowRect', rect)
  }
  getWindowRect() {
    return this._execute('getWindowRect')
  }
  maximizeWindow() {
    this._execute('maximizeWindow')
  }

  // ---- cookies ----
  addCookie(cookie) {
    this._execute('addCookie', { cookie })
  }
  getCookies() {
    return this._execute('getCookies')
  }
  getCookie(name) {
    return this._execute('getCookie', { name })
  }
  deleteCookie(name) {
    this._execute('deleteCookie', { name })
  }
  deleteAllCookies() {
    this._execute('deleteAllCookies')
  }

  // ---- actions ----
  performActions(actions) {
    this._execute('actions', { actions })
  }
  clearActions() {
    this._execute('clearActions')
  }

  // ---- timeouts ----
  setTimeouts(timeouts) {
    this._execute('setTimeout', timeouts)
  }

  // ---- screenshots ----
  screenshotBase64() {
    return this._execute('screenshot')
  }

  // ---- WebDriver-BiDi ----
  // The event-driven BiDi surface for this session, lazily opened over the
  // negotiated webSocketUrl. Throws if the remote end granted no BiDi URL.
  //
  //   driver.bidi.subscribe('log.entryAdded')
  //   driver.get(url)
  //   const ev = driver.bidi.nextEvent('log.entryAdded', 5000)
  get bidi() {
    if (this._bidi === null) {
      if (!this._wsUrl) {
        throw new WebDriverError('BiDi not available: the session negotiated no webSocketUrl', 0)
      }
      const handle = native.bidiOpen(this._wsUrl)
      if (native.isNull(handle)) {
        throw new WebDriverError('BiDi channel failed to open', -1)
      }
      this._bidi = new BiDi(handle)
    }
    return this._bidi
  }

  // True if this session can use BiDi (a webSocketUrl was negotiated).
  bidiAvailable() {
    return !!this._wsUrl
  }

  // ---- lifecycle ----
  get sessionId() {
    return native.takeString(native.sessionId(this._handle))
  }
  quit() {
    try {
      if (this._bidi !== null) {
        this._bidi.close()
        this._bidi = null
      }
      this._execute('quit')
    } finally {
      this._closeHandle()
    }
  }
  _closeHandle() {
    if (this._handle && !native.isNull(this._handle)) {
      native.close(this._handle)
      this._handle = null
    }
  }
}

// The common WebDriver-BiDi event names (W3C spec). Pass to
// driver.bidi.subscribe(...) and match in nextEvent(...).
const BidiEvent = {
  LOG_ENTRY_ADDED: 'log.entryAdded',
  CONTEXT_CREATED: 'browsingContext.contextCreated',
  CONTEXT_DESTROYED: 'browsingContext.contextDestroyed',
  NAVIGATION_STARTED: 'browsingContext.navigationStarted',
  DOM_CONTENT_LOADED: 'browsingContext.domContentLoaded',
  LOAD: 'browsingContext.load',
  DOWNLOAD_WILL_BEGIN: 'browsingContext.downloadWillBegin',
  BEFORE_REQUEST_SENT: 'network.beforeRequestSent',
  RESPONSE_STARTED: 'network.responseStarted',
  RESPONSE_COMPLETED: 'network.responseCompleted',
  FETCH_ERROR: 'network.fetchError',
  REALM_CREATED: 'script.realmCreated',
  REALM_DESTROYED: 'script.realmDestroyed',
  MESSAGE: 'script.message',
}

// The event-driven BiDi channel for a session (over the demux C ABI).
//
// Commands and events multiplex over one WebSocket via the engine's shape-C
// demux (a single reader routes replies to an id table and events to a bounded
// queue), so replies stay correlated while events stream. Command ids are
// supplied automatically from a monotonic per-channel counter. The calls are
// SYNCHRONOUS blocking FFI round-trips, matching the rest of this binding.
class BiDi {
  constructor(handle) {
    this._handle = handle
    this._nextId = 1
  }

  _id() {
    return this._nextId++
  }

  // session.subscribe to one or more event names; wait for the ack. Returns the
  // parsed ack payload. After this, matching events arrive on the queue (drain
  // via nextEvent).
  subscribe(...events) {
    const csv = events.join(',')
    const raw = native.takeString(native.bidiSubscribe(this._handle, this._id(), csv, 10000))
    return raw ? JSON.parse(raw) : {}
  }

  unsubscribe(...events) {
    const csv = events.join(',')
    const raw = native.takeString(native.bidiUnsubscribe(this._handle, this._id(), csv, 10000))
    return raw ? JSON.parse(raw) : {}
  }

  // Block until an event whose method matches arrives, or timeout. Returns the
  // parsed event object, or null on timeout/close. (Subscribe first.)
  nextEvent(method, timeoutMs = 5000) {
    const raw = native.takeString(native.bidiWaitEvent(this._handle, method, timeoutMs))
    return raw ? JSON.parse(raw) : null
  }

  // Issue any BiDi command and return its parsed reply payload. Lets a caller
  // reach BiDi methods with no dedicated wrapper (script.evaluate,
  // browsingContext.captureScreenshot, network.*, …).
  command(method, params = {}, timeoutMs = 10000) {
    // send + pump until this id's reply arrives (the engine's convenience).
    const cid = this._id()
    if (native.bidiSend(this._handle, cid, method, JSON.stringify(params)) !== 0) {
      throw new WebDriverError(`BiDi send failed: ${method}`, -1)
    }
    let waited = 0
    const step = 50
    while (waited < timeoutMs) {
      const reply = native.takeString(native.bidiPollReply(this._handle, cid))
      if (reply) return JSON.parse(reply)
      if (native.bidiPump(this._handle, step) < 0) break
      waited += step
    }
    throw new TimeoutError(`BiDi command timed out: ${method}`, 0)
  }

  // How many events the bounded queue has dropped since the last call (then
  // resets) — so a consumer knows it missed events.
  lostEvents() {
    return native.bidiLostEvents(this._handle)
  }

  close() {
    if (this._handle && !native.isNull(this._handle)) {
      native.bidiClose(this._handle)
      this._handle = null
    }
  }
}

// ---- pure engine helpers ----
function route(command) {
  return native.takeString(native.route(command))
}
function errorCode(w3cError) {
  return native.errorCode(w3cError)
}
function locator(by, value) {
  return native.takeString(native.byLocator(by, value))
}

module.exports = {
  By,
  WebDriver,
  WebElement,
  BiDi,
  BidiEvent,
  WebDriverError,
  NoSuchElementError,
  StaleElementReferenceError,
  ElementClickInterceptedError,
  ElementNotInteractableError,
  InvalidSelectorError,
  TimeoutError,
  JavascriptError,
  UnknownCommandError,
  route,
  errorCode,
  locator,
}
