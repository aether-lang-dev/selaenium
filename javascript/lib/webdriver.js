// The ergonomic Node WebDriver surface — a thin layer over the shared Aether
// core, shaped to PERFECT ABI parity with mainstream selenium-webdriver (npm):
//
//   const { Builder, By, until, Key } = require('selenium-webdriver')
//   const driver = new Builder().forBrowser('chrome').build()
//   await driver.get('https://example.com')
//   console.log(await driver.getTitle())
//   await driver.findElement(By.css('a')).click()
//   await driver.wait(until.titleContains('Example'), 5000)
//   await driver.quit()
//
// ASYNC ABI OVER A BLOCKING CORE (the design point): the engine's execute() is a
// blocking FFI round-trip (koffi calls block), so there is no real async I/O.
// But the PUBLIC surface is async/Promise-returning EXACTLY like upstream —
// every WebDriver/WebElement/Navigation/Options/TargetLocator/Alert method is
// `async` (or returns a resolved Promise), so `await` works throughout and an
// unmodified mainstream script runs unchanged. The blocking `_execute` stays
// under the hood; its result is wrapped in a resolved Promise.
//
// Upstream getters-vs-methods: mainstream uses async METHODS (getTitle(),
// getCurrentUrl(), getText(), getRect(), …), not getters. Those are the ABI
// here. The former synchronous getters (title, currentUrl, text, …) are kept as
// DEPRECATED synchronous aliases for this port's own earlier callers; new code
// must use the async methods.
//
// One source of truth: the flat driver methods (get/back/addCookie/…) issue the
// commands; the mainstream facades (navigate()/manage()/switchTo()) delegate to
// the same seam. This binding carries NO protocol logic — every command is one
// native.execute() call plus JSON marshalling.

'use strict'

const native = require('./native')
const by = require('./by')
const error = require('./error')
const input = require('./input')
const { By, RelativeBy, checkedLocator } = by
const { WebDriverError } = error

// The W3C element-reference key: a findElement result is
// { "element-6066-11e4-a52e-4f735466cecf": "<id>" }.
const W3C_ELEMENT_KEY = 'element-6066-11e4-a52e-4f735466cecf'

// Unpack a By locator into the engine's normalized { using, value }. The engine
// rewrites id/name/class name to CSS. NO engine change.
function decodeBy(locator) {
  return JSON.parse(native.takeString(native.byLocator(locator.using, locator.value)))
}

//////////////////////////////////////////////////////////////////////////////
//  Wait conditions (upstream Condition / WebElementCondition)
//////////////////////////////////////////////////////////////////////////////

// A condition polled by driver.wait(). `fn(driver)` returns (or resolves to) a
// truthy value to finish the wait, or a falsy value to keep polling. Matches
// upstream webdriver.Condition.
class Condition {
  constructor(message, fn) {
    this.description_ = 'Waiting ' + message
    this.fn = fn
  }
  description() {
    return this.description_
  }
}

// A Condition whose truthy resolution is a WebElement (driver.wait() then
// returns a WebElementPromise). Matches upstream webdriver.WebElementCondition.
class WebElementCondition extends Condition {
  constructor(message, fn) {
    super(message, fn)
  }
}

//////////////////////////////////////////////////////////////////////////////
//  WebElement
//////////////////////////////////////////////////////////////////////////////

// A located element. Every command-issuing method is async (returns a Promise),
// matching upstream. The blocking seam is `_execute` on the driver.
class WebElement {
  constructor(driver, id) {
    this._driver = driver
    this._id = id
  }

  // Upstream getId() returns a Promise<string>. Kept as a method (not a getter).
  getId() {
    return Promise.resolve(this._id)
  }

  // DEPRECATED: the raw id. Use getId() (async) — the upstream ABI. Retained for
  // this port's earlier callers and internal serialization.
  get id() {
    return this._id
  }

  // The W3C element reference for wire/serialization use.
  [Symbol.for('selenium.serialize')]() {
    return { [W3C_ELEMENT_KEY]: this._id }
  }

  getDriver() {
    return this._driver
  }

  _exec(command, params = {}) {
    return this._driver._execute(command, { ...params, id: this._id })
  }

  async click() {
    return this._exec('clickElement')
  }
  async clear() {
    return this._exec('clearElement')
  }
  async sendKeys(...args) {
    const keys = []
    for (const arg of await Promise.all(args)) {
      const type = typeof arg
      if (type === 'number') keys.push(...String(arg))
      else if (type === 'string') keys.push(...arg)
      else throw new TypeError('each key must be a number or string; got ' + type)
    }
    const text = keys.join('')
    return this._exec('sendKeysToElement', { text, value: keys })
  }
  async getText() {
    return this._exec('getElementText')
  }
  async getTagName() {
    return this._exec('getElementTagName')
  }
  async getCssValue(cssStyleProperty) {
    return this._exec('getElementValueOfCssProperty', { propertyName: cssStyleProperty })
  }
  async getRect() {
    return this._exec('getElementRect')
  }
  async isDisplayed() {
    // The isDisplayed atom, run in-page by the engine — the real visibility
    // algorithm, not a naive style check.
    return !!this._driver._atomBool('isDisplayed', this._id)
  }
  async getAttribute(name) {
    // The classic getAttribute(name): property-or-attribute (boolean attrs,
    // live properties like value/checked), via the shared engine atom. Use
    // getDomAttribute() for the raw W3C DOM attribute.
    return this._driver._atomGetAttribute(this._id, name)
  }
  async getDomAttribute(name) {
    return this._exec('getDomAttribute', { name })
  }
  async getProperty(name) {
    return this._exec('getElementProperty', { name })
  }
  async isEnabled() {
    return !!this._exec('isElementEnabled')
  }
  async isSelected() {
    return !!this._exec('isElementSelected')
  }
  async submit() {
    const script =
      'var form = arguments[0];\n' +
      'while (form.nodeName != "FORM" && form.parentNode) { form = form.parentNode; }\n' +
      "if (!form) { throw Error('Unable to find containing form element'); }\n" +
      "if (!form.ownerDocument) { throw Error('Unable to find owning document'); }\n" +
      "var e = form.ownerDocument.createEvent('Event');\n" +
      "e.initEvent('submit', true, true);\n" +
      'if (form.dispatchEvent(e)) { HTMLFormElement.prototype.submit.call(form) }\n'
    return this._driver.executeScript(script, this)
  }
  async takeScreenshot() {
    return this._exec('takeElementScreenshot')
  }

  // Scope a search to this element's subtree (findElement returns a thenable
  // WebElementPromise, so both `await el.findElement(...)` and chaining work).
  findElement(locator) {
    return newWebElementPromise(
      this._driver,
      (async () => {
        const loc = checkedLocator(locator)
        if (typeof loc === 'function') {
          return this._driver._resolveElementFn(loc, this)
        }
        const decoded = decodeBy(loc)
        const result = this._driver._execute('findChildElement', {
          id: this._id,
          using: decoded.using,
          value: decoded.value,
        })
        return new WebElement(this._driver, result[W3C_ELEMENT_KEY])
      })(),
    )
  }

  async findElements(locator) {
    const loc = checkedLocator(locator)
    if (typeof loc === 'function') {
      return this._driver._resolveElementsFn(loc, this)
    }
    const decoded = decodeBy(loc)
    const result = this._driver._execute('findChildElements', {
      id: this._id,
      using: decoded.using,
      value: decoded.value,
    })
    return (result || []).map((e) => new WebElement(this._driver, e[W3C_ELEMENT_KEY]))
  }
}

// A WebElement that is ALSO awaitable — upstream returns this from findElement so
// both `await driver.findElement(...)` and `driver.findElement(...).click()`
// work. Built from a Promise<WebElement>: it forwards then/catch/finally to that
// promise and proxies every WebElement method to the resolved element.
function newWebElementPromise(driver, elementPromise) {
  const wep = new WebElement(driver, undefined)
  wep.then = elementPromise.then.bind(elementPromise)
  wep.catch = elementPromise.catch.bind(elementPromise)
  wep.finally = elementPromise.finally.bind(elementPromise)
  wep.getId = () => elementPromise.then((el) => el.getId())
  const proxy = (name) => {
    wep[name] = (...args) => elementPromise.then((el) => el[name](...args))
  }
  ;[
    'click',
    'clear',
    'sendKeys',
    'getText',
    'getTagName',
    'getCssValue',
    'getRect',
    'isDisplayed',
    'getAttribute',
    'getDomAttribute',
    'getProperty',
    'isEnabled',
    'isSelected',
    'submit',
    'takeScreenshot',
    'findElement',
    'findElements',
  ].forEach(proxy)
  return wep
}

//////////////////////////////////////////////////////////////////////////////
//  Facades: Navigation / Options / Window / TargetLocator / Alert
//////////////////////////////////////////////////////////////////////////////

// driver.navigate() — the mainstream navigation facade. Delegates to the flat
// driver methods (get/back/forward/refresh), which are the one source of truth.
class Navigation {
  constructor(driver) {
    this.driver_ = driver
  }
  to(url) {
    return this.driver_.get(url)
  }
  back() {
    return this.driver_.back()
  }
  forward() {
    return this.driver_.forward()
  }
  refresh() {
    return this.driver_.refresh()
  }
}

// driver.manage().window() — the mainstream window facade.
class Window {
  constructor(driver) {
    this.driver_ = driver
  }
  getRect() {
    return this.driver_.getWindowRect()
  }
  setRect(rect) {
    return this.driver_.setWindowRect(rect)
  }
  maximize() {
    return this.driver_.maximizeWindow()
  }
  minimize() {
    return this.driver_.minimizeWindow()
  }
  fullscreen() {
    return this.driver_.fullscreenWindow()
  }
  async getSize() {
    const rect = await this.driver_.getWindowRect()
    return { width: rect.width, height: rect.height }
  }
  async setSize({ x = 0, y = 0, width = 0, height = 0 }) {
    return this.driver_.setWindowRect({ x, y, width, height })
  }
}

// driver.manage() — the mainstream cookie/timeout/window facade. Delegates to
// the flat driver methods.
class Options {
  constructor(driver) {
    this.driver_ = driver
  }
  addCookie({ name, value, path, domain, secure, httpOnly, expiry, sameSite }) {
    if (/[;=]/.test(name)) {
      throw new error.InvalidArgumentError('Invalid cookie name "' + name + '"')
    }
    if (/;/.test(value)) {
      throw new error.InvalidArgumentError('Invalid cookie value "' + value + '"')
    }
    if (typeof expiry === 'number') {
      expiry = Math.floor(expiry)
    } else if (expiry instanceof Date) {
      expiry = Math.floor(expiry.getTime() / 1000)
    }
    if (sameSite && !['Strict', 'Lax', 'None'].includes(sameSite)) {
      throw new error.InvalidArgumentError(
        `Invalid sameSite cookie value '${sameSite}'. It should be one of "Lax", "Strict" or "None"`,
      )
    }
    return this.driver_.addCookie({
      name,
      value,
      path,
      domain,
      secure: !!secure,
      httpOnly: !!httpOnly,
      expiry,
      sameSite,
    })
  }
  deleteAllCookies() {
    return this.driver_.deleteAllCookies()
  }
  deleteCookie(name) {
    return this.driver_.deleteCookie(name)
  }
  getCookies() {
    return this.driver_.getCookies()
  }
  getCookie(name) {
    return this.driver_.getCookie(name)
  }
  getTimeouts() {
    return Promise.resolve(this.driver_._execute('getTimeouts'))
  }
  setTimeouts({ script, pageLoad, implicit } = {}) {
    const timeouts = {}
    if (typeof script === 'number') timeouts.script = script
    if (typeof pageLoad === 'number') timeouts.pageLoad = pageLoad
    if (typeof implicit === 'number') timeouts.implicit = implicit
    return this.driver_.setTimeouts(timeouts)
  }
  window() {
    return new Window(this.driver_)
  }
}

// driver.switchTo() — the mainstream focus-switching facade. Delegates to the
// flat driver methods; alert() returns an Alert (with accept/dismiss/getText/
// sendKeys). All returns are awaitable.
class TargetLocator {
  constructor(driver) {
    this.driver_ = driver
  }
  activeElement() {
    return newWebElementPromise(
      this.driver_,
      (async () => {
        const result = this.driver_._execute('getActiveElement')
        return new WebElement(this.driver_, result[W3C_ELEMENT_KEY])
      })(),
    )
  }
  async defaultContent() {
    return this.driver_._execute('switchToFrame', { id: null })
  }
  async frame(id) {
    let frameReference = id
    if (typeof id === 'string') {
      try {
        frameReference = { [W3C_ELEMENT_KEY]: (await this.driver_.findElement(By.id(id))).id }
      } catch (_) {
        frameReference = { [W3C_ELEMENT_KEY]: (await this.driver_.findElement(By.name(id))).id }
      }
    } else if (id instanceof WebElement) {
      frameReference = { [W3C_ELEMENT_KEY]: id.id }
    }
    return this.driver_._execute('switchToFrame', { id: frameReference })
  }
  async parentFrame() {
    return this.driver_._execute('switchToFrameParent')
  }
  async window(nameOrHandle) {
    return this.driver_.switchToWindow(nameOrHandle)
  }
  async newWindow(typeHint = 'tab') {
    const value = this.driver_._execute('newWindow', { type: typeHint })
    return this.driver_.switchToWindow(value.handle)
  }
  // The open alert/confirm/prompt. Touches its text first (raising a
  // NoSuchAlertError-style error if none is present), as mainstream.
  async alert() {
    const text = this.driver_._execute('getAlertText')
    return new Alert(this.driver_, text)
  }
}

// A JavaScript alert/confirm/prompt handle, reached via
// driver.switchTo().alert(). Every method is awaitable.
class Alert {
  constructor(driver, text) {
    this.driver_ = driver
    this.text_ = text
  }
  getText() {
    return Promise.resolve(this.text_)
  }
  async accept() {
    return this.driver_._execute('acceptAlert')
  }
  async dismiss() {
    return this.driver_._execute('dismissAlert')
  }
  async sendKeys(text) {
    return this.driver_._execute('setAlertValue', { text, value: Array.from(text) })
  }
}

//////////////////////////////////////////////////////////////////////////////
//  WebDriver
//////////////////////////////////////////////////////////////////////////////

class WebDriver {
  // `options` may carry TLS trust config: { caPath, insecure }. caPath pins a
  // private-CA bundle; insecure skips verification entirely (self-signed
  // dev/staging Grid — trust the host out-of-band). Both land on the handle
  // BEFORE newSession (the first request).
  constructor(commandExecutor, capabilities, { caPath = null, insecure = false } = {}) {
    this._handle = native.open(commandExecutor)
    if (native.isNull(this._handle)) {
      throw new WebDriverError('failed to open session handle', -1)
    }
    if (caPath) native.setCa(this._handle, caPath)
    if (insecure) native.setInsecure(this._handle, 1)
    // Request a BiDi channel so `.bidi` is available on demand; the channel
    // itself is opened lazily (a classic script never opens the WebSocket).
    const caps = { ...capabilities, webSocketUrl: true }
    const result = this._execute('newSession', { capabilities: { alwaysMatch: caps } })
    // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
    this._wsUrl = (result && result.capabilities && result.capabilities.webSocketUrl) || ''
    this._capabilities = (result && result.capabilities) || caps
    this._bidi = null
  }

  static chrome(commandExecutor = 'http://127.0.0.1:9515', options = null, tls = {}) {
    const caps = { browserName: 'chrome' }
    if (options) Object.assign(caps, options)
    return new WebDriver(commandExecutor, caps, tls)
  }

  static headlessChrome(commandExecutor = 'http://127.0.0.1:9515') {
    return WebDriver.chrome(commandExecutor, {
      'goog:chromeOptions': {
        args: ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
      },
    })
  }

  // The FFI seam: one command by name with a params object. BLOCKS (koffi), then
  // returns the decoded `value` payload synchronously, or throws a typed error.
  // Public methods wrap this in a resolved Promise to present the async ABI.
  _execute(command, params = {}) {
    const rc = native.execute(this._handle, command, JSON.stringify(params))
    if (rc !== 0) {
      const code = native.lastErrorCode(this._handle)
      const message = native.takeString(native.lastError(this._handle))
      if (rc === -1 && code === 0) {
        throw new WebDriverError(message || 'transport failure', -1)
      }
      error.raiseFor(code, message)
    }
    const raw = native.takeString(native.lastValue(this._handle))
    if (raw === '') return null
    return JSON.parse(raw)
  }

  // ---- atom-backed commands (a shared JS atom run in-page via the engine) ----
  _atomResult(rc) {
    if (rc !== 0) {
      const code = native.lastErrorCode(this._handle)
      const message = native.takeString(native.lastError(this._handle))
      if (rc === -1 && code === 0) {
        throw new WebDriverError(message || 'transport failure', -1)
      }
      error.raiseFor(code, message)
    }
    const raw = native.takeString(native.lastValue(this._handle))
    if (raw === '') return null
    return JSON.parse(raw)
  }

  _atomBool(verb, elementId) {
    return !!this._atomResult(native[verb](this._handle, elementId))
  }

  _atomGetAttribute(elementId, name) {
    return this._atomResult(native.getAttribute(this._handle, elementId, name))
  }

  // Run a By.js-style locator function against a context, normalizing its result
  // to a single WebElement (upstream findElementInternal_).
  async _resolveElementFn(locatorFn, context) {
    let result = await locatorFn(context)
    if (Array.isArray(result)) {
      if (result.length === 0) {
        throw new error.NoSuchElementError('Cannot locate an element with provided parameters')
      }
      result = result[0]
    }
    if (!(result instanceof WebElement)) {
      throw new TypeError('Custom locator did not return a WebElement')
    }
    return result
  }

  async _resolveElementsFn(locatorFn, context) {
    let result
    try {
      result = await locatorFn(context)
    } catch (ex) {
      if (ex instanceof error.NoSuchElementError) return []
      throw ex
    }
    if (result instanceof WebElement) return [result]
    if (!Array.isArray(result)) return []
    return result.filter((item) => item instanceof WebElement)
  }

  // Relative locators: elements matching baseCss filtered by spatial relation to
  // anchors, nearest first. Each filter is an object
  // { kind: 'above'|'below'|'left'|'right'|'near', sel: '<css>' } ('near' also
  // accepts 'dist'). Returns an array of WebElement. (This binding's own
  // relative-locator entry point; mainstream's locateWith(...)/RelativeBy is
  // also accepted by findElement/findElements.)
  findRelative(baseCss, ...filters) {
    const rc = native.findRelative(this._handle, baseCss, JSON.stringify(filters))
    const refs = this._atomResult(rc) || []
    return refs.map((r) => new WebElement(this, r[W3C_ELEMENT_KEY]))
  }

  // Resolve a RelativeBy through the engine's find-relative atom. The base is a
  // CSS selector; each filter carries a { kind, args:[locator] } — the anchor
  // locator's CSS value is passed as `sel`.
  _findRelativeBy(relativeBy, wantAll) {
    const root = relativeBy.root
    const baseCss = root['css selector'] || root.css || Object.values(root)[0]
    const filters = relativeBy.filters.map((f) => {
      const anchor = f.args[0] || {}
      const sel = anchor['css selector'] || anchor.css || Object.values(anchor)[0]
      return { kind: f.kind, sel }
    })
    const rc = native.findRelative(this._handle, baseCss, JSON.stringify(filters))
    const refs = this._atomResult(rc) || []
    const els = refs.map((r) => new WebElement(this, r[W3C_ELEMENT_KEY]))
    if (wantAll) return els
    if (els.length === 0) {
      throw new error.NoSuchElementError('Cannot locate an element with provided parameters')
    }
    return els[0]
  }

  // ---- session / capabilities ----
  getCapabilities() {
    return Promise.resolve(this._capabilities)
  }
  getSession() {
    return Promise.resolve({ id: this.sessionId, capabilities: this._capabilities })
  }

  // ---- navigation (flat: the source of truth) ----
  async get(url) {
    return this._execute('get', { url })
  }
  async getCurrentUrl() {
    return this._execute('getCurrentUrl')
  }
  async getTitle() {
    return this._execute('getTitle')
  }
  async getPageSource() {
    return this._execute('getPageSource')
  }
  async back() {
    return this._execute('goBack')
  }
  async forward() {
    return this._execute('goForward')
  }
  async refresh() {
    return this._execute('refresh')
  }

  // DEPRECATED synchronous getters (this port's earlier ABI). Use the async
  // methods above — the mainstream ABI. Kept as trivial aliases.
  get currentUrl() {
    return this._execute('getCurrentUrl')
  }
  get title() {
    return this._execute('getTitle')
  }
  get pageSource() {
    return this._execute('getPageSource')
  }

  // ---- elements ----
  // findElement(locator) — one locator arg (mainstream). Returns a
  // WebElementPromise: awaitable AND chainable (driver.findElement(...).click()).
  findElement(locator) {
    return newWebElementPromise(
      this,
      (async () => {
        const loc = checkedLocator(locator)
        if (loc instanceof RelativeBy) {
          return this._findRelativeBy(loc, false)
        }
        if (typeof loc === 'function') {
          return this._resolveElementFn(loc, this)
        }
        const result = this._execute('findElement', decodeBy(loc))
        return new WebElement(this, result[W3C_ELEMENT_KEY])
      })(),
    )
  }

  async findElements(locator) {
    const loc = checkedLocator(locator)
    if (loc instanceof RelativeBy) {
      return this._findRelativeBy(loc, true)
    }
    if (typeof loc === 'function') {
      return this._resolveElementsFn(loc, this)
    }
    let result
    try {
      result = this._execute('findElements', decodeBy(loc))
    } catch (ex) {
      if (ex instanceof error.NoSuchElementError) return []
      throw ex
    }
    return (result || []).map((e) => new WebElement(this, e[W3C_ELEMENT_KEY]))
  }

  // ---- script ----
  async executeScript(script, ...args) {
    if (typeof script === 'function') {
      script = 'return (' + script + ').apply(null, arguments);'
    }
    return this._execute('executeScript', { script, args: args.map(toWireArg) })
  }
  async executeAsyncScript(script, ...args) {
    if (typeof script === 'function') {
      script = 'return (' + script + ').apply(null, arguments);'
    }
    return this._execute('executeAsyncScript', { script, args: args.map(toWireArg) })
  }

  // ---- wait / actions (mainstream) ----
  // Poll a condition until it yields a truthy value or `timeout` ms elapse. The
  // engine holds no thread, so the loop lives here in JS over the blocking
  // calls. Accepts a Condition, a WebElementCondition (returns a
  // WebElementPromise), a raw function(driver), or a promise. Mirrors upstream
  // WebDriver.wait.
  wait(condition, timeout = 0, message = undefined, pollTimeout = 200) {
    if (typeof timeout !== 'number' || timeout < 0) {
      throw new TypeError('timeout must be a number >= 0: ' + timeout)
    }
    if (typeof pollTimeout !== 'number' || pollTimeout < 0) {
      throw new TypeError('pollTimeout must be a number >= 0: ' + pollTimeout)
    }

    if (condition && typeof condition.then === 'function') {
      return new Promise((resolve, reject) => {
        if (!timeout) {
          resolve(condition)
          return
        }
        const start = Date.now()
        const timer = setTimeout(() => {
          reject(
            new error.TimeoutError(
              `${message ? message + '\n' : ''}Timed out waiting for promise to resolve after ${
                Date.now() - start
              }ms`,
            ),
          )
        }, timeout)
        Promise.resolve(condition).then(
          (value) => {
            clearTimeout(timer)
            resolve(value)
          },
          (err) => {
            clearTimeout(timer)
            reject(err)
          },
        )
      })
    }

    let fn = condition
    if (condition instanceof Condition) {
      message = message || condition.description()
      fn = condition.fn
    }
    if (typeof fn !== 'function') {
      throw new TypeError(
        'Wait condition must be a promise-like object, function, or a Condition object',
      )
    }

    const driver = this
    const result = new Promise((resolve, reject) => {
      const startTime = Date.now()
      const pollCondition = () => {
        Promise.resolve()
          .then(() => fn(driver))
          .then(
            (value) => {
              const elapsed = Date.now() - startTime
              if (value) {
                resolve(value)
              } else if (timeout && elapsed >= timeout) {
                reject(
                  new error.TimeoutError(
                    `${message ? message + '\n' : ''}Wait timed out after ${elapsed}ms`,
                  ),
                )
              } else {
                setTimeout(pollCondition, pollTimeout)
              }
            },
            reject,
          )
      }
      pollCondition()
    })

    if (condition instanceof WebElementCondition) {
      return newWebElementPromise(
        this,
        result.then((value) => {
          if (!(value instanceof WebElement)) {
            throw new TypeError(
              'WebElementCondition did not resolve to a WebElement: ' +
                Object.prototype.toString.call(value),
            )
          }
          return value
        }),
      )
    }
    return result
  }

  sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  // The mainstream action builder (keyboard/pointer/wheel gestures). perform()
  // drives the engine's blocking actions command.
  actions(options) {
    return new input.Actions(this, options || undefined)
  }

  // ---- windows (flat: the source of truth) ----
  async getAllWindowHandles() {
    return this._execute('getWindowHandles')
  }
  async getWindowHandle() {
    return this._execute('getCurrentWindowHandle')
  }
  async close() {
    return this._execute('close')
  }
  async switchToWindow(handle) {
    return this._execute('switchToWindow', { handle })
  }
  setWindowRect(rect) {
    return Promise.resolve(this._execute('setWindowRect', rect))
  }
  getWindowRect() {
    return Promise.resolve(this._execute('getWindowRect'))
  }
  maximizeWindow() {
    return Promise.resolve(this._execute('maximizeWindow'))
  }
  minimizeWindow() {
    return Promise.resolve(this._execute('minimizeWindow'))
  }
  fullscreenWindow() {
    return Promise.resolve(this._execute('fullscreenWindow'))
  }

  // DEPRECATED synchronous getters. Use getAllWindowHandles()/getWindowHandle().
  get windowHandles() {
    return this._execute('getWindowHandles')
  }
  get currentWindowHandle() {
    return this._execute('getCurrentWindowHandle')
  }

  // ---- cookies (flat: the source of truth) ----
  async addCookie(cookie) {
    return this._execute('addCookie', { cookie })
  }
  async getCookies() {
    return this._execute('getCookies')
  }
  async getCookie(name) {
    return this._execute('getCookie', { name })
  }
  async deleteCookie(name) {
    return this._execute('deleteCookie', { name })
  }
  async deleteAllCookies() {
    return this._execute('deleteAllCookies')
  }

  // ---- actions (flat, low-level W3C) ----
  async performActions(actions) {
    return this._execute('actions', { actions })
  }
  async clearActions() {
    return this._execute('clearActions')
  }

  // ---- alerts (flat: the source of truth) ----
  async acceptAlert() {
    return this._execute('acceptAlert')
  }
  async dismissAlert() {
    return this._execute('dismissAlert')
  }
  async getAlertText() {
    return this._execute('getAlertText')
  }
  async sendAlertText(text) {
    return this._execute('setAlertValue', { text, value: Array.from(text) })
  }
  // DEPRECATED synchronous getter. Use switchTo().alert() / getAlertText().
  get alertText() {
    return this._execute('getAlertText')
  }

  // ---- timeouts (flat: the source of truth) ----
  async setTimeouts(timeouts) {
    return this._execute('setTimeout', timeouts)
  }
  async setPageLoadTimeout(ms) {
    return this._execute('setTimeout', { pageLoad: ms })
  }
  async setScriptTimeout(ms) {
    return this._execute('setTimeout', { script: ms })
  }
  async implicitlyWait(ms) {
    return this._execute('setTimeout', { implicit: ms })
  }

  // ---- screenshots ----
  async takeScreenshot() {
    return this._execute('screenshot')
  }
  // DEPRECATED alias for takeScreenshot() (this port's earlier name).
  async screenshotBase64() {
    return this._execute('screenshot')
  }

  // Print the current page to PDF (base64), mainstream driver.printPage(options).
  // options is the W3C print params object (scale/background/page/margin/…);
  // {} prints with defaults.
  async printPage(options = {}) {
    return this._execute('printPage', options)
  }

  // ---- facades (mainstream; delegate to the flat methods) ----
  manage() {
    return new Options(this)
  }
  navigate() {
    return new Navigation(this)
  }
  switchTo() {
    return new TargetLocator(this)
  }

  // ---- WebDriver-BiDi ----
  // The event-driven BiDi surface for this session, lazily opened over the
  // negotiated webSocketUrl. Throws if the remote end granted no BiDi URL.
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

  bidiAvailable() {
    return !!this._wsUrl
  }

  // ---- lifecycle ----
  get sessionId() {
    return native.takeString(native.sessionId(this._handle))
  }
  async quit() {
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

// Serialize a script argument: a WebElement (or WebElementPromise) becomes its
// W3C element reference; everything else passes through. Matches upstream's
// toWireValue for elements (executeScript wraps element args as {element-key}).
function toWireArg(arg) {
  if (arg instanceof WebElement) {
    return { [W3C_ELEMENT_KEY]: arg.id }
  }
  return arg
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
  AUTH_REQUIRED: 'network.authRequired',
  RESPONSE_STARTED: 'network.responseStarted',
  RESPONSE_COMPLETED: 'network.responseCompleted',
  FETCH_ERROR: 'network.fetchError',
  REALM_CREATED: 'script.realmCreated',
  REALM_DESTROYED: 'script.realmDestroyed',
  MESSAGE: 'script.message',
}

// The event-driven BiDi channel for a session (over the demux C ABI).
//
// NOTE ON SYNC vs ASYNC: unlike the classic surface above (async ABI over a
// blocking core), the BiDi channel remains SYNCHRONOUS. It is an advanced,
// binding-specific surface with no mainstream selenium-webdriver equivalent
// method-for-method (upstream ships bidi/* modules with a different shape), so
// there is no upstream ABI to match here; the blocking round-trips stay visible.
class BiDi {
  constructor(handle) {
    this._handle = handle
    this._nextId = 1
  }

  _id() {
    return this._nextId++
  }

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

  nextEvent(method, timeoutMs = 5000) {
    const raw = native.takeString(native.bidiWaitEvent(this._handle, method, timeoutMs))
    return raw ? JSON.parse(raw) : null
  }

  command(method, params = {}, timeoutMs = 10000) {
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
    throw new error.TimeoutError(`BiDi command timed out: ${method}`, 0)
  }

  getTree(timeoutMs = 10000) {
    const raw = native.takeString(native.bidiGetTree(this._handle, this._id(), timeoutMs))
    return raw ? JSON.parse(raw) : {}
  }

  topContext(timeoutMs = 10000) {
    const contexts = (this.getTree(timeoutMs).result || {}).contexts || []
    return contexts.length ? contexts[0].context : null
  }

  evaluate(expression, timeoutMs = 30000) {
    const ctx = this.topContext(timeoutMs)
    if (!ctx) {
      throw new WebDriverError('no browsing context for script.evaluate', 0)
    }
    const raw = native.takeString(
      native.bidiScriptEvaluate(this._handle, this._id(), expression, ctx, timeoutMs),
    )
    return raw ? JSON.parse(raw) : {}
  }

  evaluateValue(expression, timeoutMs = 30000) {
    const result = this.evaluate(expression, timeoutMs).result || {}
    const inner = result.result || {}
    return inner.value
  }

  navigate(url, timeoutMs = 30000) {
    const ctx = this.topContext(timeoutMs)
    if (!ctx) {
      throw new WebDriverError('no browsing context for navigate', 0)
    }
    const raw = native.takeString(native.bidiNavigate(this._handle, this._id(), ctx, url, timeoutMs))
    return raw ? JSON.parse(raw) : {}
  }

  addIntercept(phasesCsv = 'beforeRequestSent', urlPattern = '', timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkAddIntercept(this._handle, this._id(), phasesCsv, urlPattern, timeoutMs),
    )
    const reply = raw ? JSON.parse(raw) : {}
    return (reply.result || {}).intercept || null
  }

  removeIntercept(interceptId, timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkRemoveIntercept(this._handle, this._id(), interceptId, timeoutMs),
    )
    return raw ? JSON.parse(raw) : {}
  }

  continueRequest(requestId, timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkContinueRequest(this._handle, this._id(), requestId, timeoutMs),
    )
    return raw ? JSON.parse(raw) : {}
  }

  failRequest(requestId, timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkFailRequest(this._handle, this._id(), requestId, timeoutMs),
    )
    return raw ? JSON.parse(raw) : {}
  }

  provideResponse(requestId, { status = 200, contentType = '', body = '', timeoutMs = 10000 } = {}) {
    const raw = native.takeString(
      native.bidiNetworkProvideResponse(
        this._handle,
        this._id(),
        requestId,
        status,
        contentType,
        body,
        timeoutMs,
      ),
    )
    return raw ? JSON.parse(raw) : {}
  }

  continueWithAuth(requestId, username, password, timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkContinueWithAuth(
        this._handle,
        this._id(),
        requestId,
        username,
        password,
        timeoutMs,
      ),
    )
    return raw ? JSON.parse(raw) : {}
  }

  setCacheBehavior(behavior = 'bypass', timeoutMs = 10000) {
    const raw = native.takeString(
      native.bidiNetworkSetCacheBehavior(this._handle, this._id(), behavior, timeoutMs),
    )
    return raw ? JSON.parse(raw) : {}
  }

  static eventRequestId(event) {
    return (((event || {}).params || {}).request || {}).request || null
  }

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

// ---- driver orchestration (spawn / adopt a driver process in-binding) --------
function resolveDriver(browser = 'chrome', hint = '') {
  return native.takeString(native.resolveDriver(browser, hint))
}

class DriverProcess {
  constructor(handle) {
    this._handle = handle
  }
  get url() {
    return this._handle && !native.isNull(this._handle)
      ? native.takeString(native.driverUrl(this._handle))
      : ''
  }
  get pid() {
    return this._handle && !native.isNull(this._handle) ? native.driverPid(this._handle) : 0
  }
  stop() {
    if (this._handle && !native.isNull(this._handle)) {
      native.stopDriver(this._handle)
      this._handle = null
    }
  }
}

function launchDriver(driverPath, timeoutMs = 15000) {
  const h = native.launchDriver(driverPath, timeoutMs)
  return native.isNull(h) ? null : new DriverProcess(h)
}

function ensureDriver(browser = 'chrome', hint = '', timeoutMs = 15000) {
  const h = native.ensureDriver(browser, hint, timeoutMs)
  return native.isNull(h) ? null : new DriverProcess(h)
}

// A Chrome session that spawns its own chromedriver via the engine — no driver
// on PATH, no Grid. The driver process is stopped on quit().
class LocalChrome extends WebDriver {
  constructor(options = null, { hint = '', timeoutMs = 15000, caPath = null, insecure = false } = {}) {
    const proc = ensureDriver('chrome', hint, timeoutMs)
    if (proc === null) {
      throw new WebDriverError('could not resolve/launch chromedriver', -1)
    }
    const caps = { browserName: 'chrome' }
    if (options) Object.assign(caps, options)
    super(proc.url, caps, { caPath, insecure })
    this._proc = proc
  }
  async quit() {
    try {
      await super.quit()
    } finally {
      this._proc.stop()
    }
  }
}

// The Selenium 4.x session entry-point. Chain forBrowser/usingServer, then
// build() returns a WebDriver:
//
//   const driver = new Builder().forBrowser('chrome').usingServer(url).build()
//
// With NO usingServer(url), build() launches the engine's own chromedriver.
//
// DEVIATION FROM UPSTREAM: upstream build() returns a ThenableWebDriver whose
// session creation is async. Here session creation is a blocking FFI call, so
// build() returns a ready WebDriver synchronously (its subsequent methods are
// all async, matching upstream). `await new Builder()...build()` still works —
// awaiting a non-thenable yields it unchanged.
class Builder {
  constructor() {
    this._browser = 'chrome'
    this._server = null
    this._capabilities = {}
    this._tls = {}
  }
  forBrowser(name) {
    this._browser = name
    return this
  }
  usingServer(url) {
    this._server = url
    return this
  }
  withCapabilities(caps) {
    Object.assign(this._capabilities, caps)
    return this
  }
  usingTls(tls) {
    this._tls = tls
    return this
  }
  build() {
    const options = Object.keys(this._capabilities).length ? this._capabilities : null
    if (this._server) {
      const caps = { browserName: this._browser }
      if (options) Object.assign(caps, options)
      return new WebDriver(this._server, caps, this._tls)
    }
    if (this._browser !== 'chrome') {
      throw new WebDriverError(
        `Builder without usingServer() only supports 'chrome' (got '${this._browser}')`,
        -1,
      )
    }
    return new LocalChrome(options, this._tls)
  }
}

// ---- pure engine helpers ----
function route(command) {
  return native.takeString(native.route(command))
}
function errorCode(w3cError) {
  return native.errorCode(w3cError)
}
function locator(byStrategy, value) {
  return native.takeString(native.byLocator(byStrategy, value))
}

module.exports = {
  Builder,
  WebDriver,
  WebElement,
  Condition,
  WebElementCondition,
  Navigation,
  Options,
  Window,
  TargetLocator,
  Alert,
  BiDi,
  BidiEvent,
  DriverProcess,
  LocalChrome,
  resolveDriver,
  launchDriver,
  ensureDriver,
  route,
  errorCode,
  locator,
  W3C_ELEMENT_KEY,
}
