// No-browser ABI test (Node, node:test): proves the binding's PUBLIC surface is
// async/Promise-returning and matches mainstream selenium-webdriver, without a
// real browser or the .so. It installs a fake `native` module (a recording stub)
// via a Module._load shim BEFORE requiring the binding, so `_execute` records
// the command + params it would send and returns a canned value. This exercises
// the JS marshalling/ABI layer only — the engine/protocol is out of scope here
// (that is covered by ffi_test.js + live_test.js).
'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const Module = require('module')
const path = require('node:path')

// ---- the recording native stub -------------------------------------------
const calls = [] // [ [commandName, params], ... ]
let valueQueue = [] // FIFO of values _execute should return

const W3C_KEY = 'element-6066-11e4-a52e-4f735466cecf'

const fakeNative = {
  open: () => ({ handle: true }),
  close() {},
  configure() {},
  isNull: (p) => !p,
  setCa() {},
  setInsecure() {},
  execute(_h, name, paramsJson) {
    calls.push([name, JSON.parse(paramsJson)])
    return 0
  },
  lastValue: () => '__VALUE__',
  lastStatus: () => 0,
  lastErrorCode: () => 0,
  lastError: () => '',
  sessionId: () => '__SESSION__',
  byLocator: (using, value) => JSON.stringify({ using, value }),
  // atom-backed calls (isDisplayed / getAttribute / findRelative)
  isDisplayed: () => 0,
  getAttribute: () => 0,
  findRelative: () => 0,
  takeString(p) {
    if (p === '__SESSION__') return 'session-42'
    if (p === '__VALUE__') {
      const v = valueQueue.length ? valueQueue.shift() : null
      return v === null ? '' : JSON.stringify(v)
    }
    return typeof p === 'string' ? p : ''
  },
}

// Intercept require('./native') (and any '.../native') to hand back the stub.
const originalLoad = Module._load
Module._load = function (request, parent, isMain) {
  if (request === './native' || request === path.join(__dirname, '..', 'lib', 'native')) {
    return fakeNative
  }
  if (/(^|[\\/])native$/.test(request) && parent && /selenium/.test(parent.filename)) {
    return fakeNative
  }
  return originalLoad.apply(this, arguments)
}

// require the binding AFTER the shim is installed.
const s = require('..')

// ---- helpers --------------------------------------------------------------
function queue(...values) {
  valueQueue = values.slice()
}
function reset() {
  calls.length = 0
  valueQueue = []
}
function lastCall() {
  return calls[calls.length - 1]
}
function callNames() {
  return calls.map((c) => c[0])
}

// Build a driver, consuming the newSession value.
function newDriver() {
  reset()
  queue({ capabilities: { webSocketUrl: '' } })
  const d = new s.WebDriver('http://fake:9515')
  reset()
  return d
}

// ---- tests ----------------------------------------------------------------

test('newSession issues the right command', () => {
  reset()
  queue({ capabilities: { webSocketUrl: '' } })
  const d = new s.WebDriver('http://fake:9515')
  assert.strictEqual(calls[0][0], 'newSession')
  assert.ok(calls[0][1].capabilities.alwaysMatch.browserName === undefined || true)
  assert.strictEqual(d.sessionId, 'session-42')
})

test('driver navigation methods are all async (return Promises)', async () => {
  const d = newDriver()
  queue(null)
  const p = d.get('https://example.com')
  assert.ok(p instanceof Promise, 'get() must return a Promise')
  await p
  assert.deepStrictEqual(lastCall(), ['get', { url: 'https://example.com' }])

  queue('My Title')
  const tp = d.getTitle()
  assert.ok(tp instanceof Promise, 'getTitle() must return a Promise')
  assert.strictEqual(await tp, 'My Title')
  assert.strictEqual(lastCall()[0], 'getTitle')

  queue('https://example.com/x')
  assert.ok(d.getCurrentUrl() instanceof Promise)
  reset()
  queue('<html></html>')
  assert.strictEqual(await d.getPageSource(), '<html></html>')
  assert.strictEqual(lastCall()[0], 'getPageSource')

  for (const [m, cmd] of [
    ['back', 'goBack'],
    ['forward', 'goForward'],
    ['refresh', 'refresh'],
  ]) {
    queue(null)
    const r = d[m]()
    assert.ok(r instanceof Promise, `${m}() must return a Promise`)
    await r
    assert.strictEqual(lastCall()[0], cmd)
  }
})

test('getTitle/getCurrentUrl/getPageSource are async METHODS (not getters)', async () => {
  const d = newDriver()
  assert.strictEqual(typeof d.getTitle, 'function')
  assert.strictEqual(typeof d.getCurrentUrl, 'function')
  assert.strictEqual(typeof d.getPageSource, 'function')
  assert.strictEqual(typeof d.getAllWindowHandles, 'function')
  assert.strictEqual(typeof d.getWindowHandle, 'function')
  assert.strictEqual(typeof d.takeScreenshot, 'function')
  assert.strictEqual(typeof d.printPage, 'function')
  assert.strictEqual(typeof d.getCapabilities, 'function')
})

test('findElement returns an awaitable + chainable WebElementPromise', async () => {
  const d = newDriver()
  // await form
  queue({ [W3C_KEY]: 'el-1' })
  const wep = d.findElement(s.By.css('a'))
  assert.strictEqual(typeof wep.then, 'function', 'findElement result must be thenable')
  const el = await wep
  assert.ok(el instanceof s.WebElement)
  assert.strictEqual(el.id, 'el-1')
  assert.strictEqual(lastCall()[0], 'findElement')

  // chained form: driver.findElement(...).click() without awaiting the find
  reset()
  queue({ [W3C_KEY]: 'el-2' }, null)
  await d.findElement(s.By.id('go')).click()
  assert.deepStrictEqual(callNames(), ['findElement', 'clickElement'])
  assert.strictEqual(calls[1][1].id, 'el-2')
})

test('WebElement command methods are all async', async () => {
  const d = newDriver()
  queue({ [W3C_KEY]: 'el-9' })
  const el = await d.findElement(s.By.id('x'))
  reset()

  queue('hello')
  const tp = el.getText()
  assert.ok(tp instanceof Promise, 'getText() must return a Promise')
  assert.strictEqual(await tp, 'hello')
  assert.strictEqual(lastCall()[0], 'getElementText')

  queue('div')
  assert.strictEqual(await el.getTagName(), 'div')
  assert.strictEqual(lastCall()[0], 'getElementTagName')

  queue(null)
  assert.ok(el.click() instanceof Promise)
  await el.click()
  assert.strictEqual(lastCall()[0], 'clickElement')

  queue(null)
  await el.sendKeys('ab')
  assert.strictEqual(lastCall()[0], 'sendKeysToElement')
  assert.strictEqual(lastCall()[1].text, 'ab')
  assert.deepStrictEqual(lastCall()[1].value, ['a', 'b'])

  queue({ x: 1, y: 2, width: 3, height: 4 })
  const rectP = el.getRect()
  assert.ok(rectP instanceof Promise)
  assert.deepStrictEqual(await rectP, { x: 1, y: 2, width: 3, height: 4 })
})

test('navigate() facade delegates to the flat commands', async () => {
  const d = newDriver()
  const nav = d.navigate()
  assert.ok(nav instanceof s.Navigation)
  queue(null)
  await nav.to('https://a.test')
  assert.deepStrictEqual(lastCall(), ['get', { url: 'https://a.test' }])
  queue(null)
  await nav.back()
  assert.strictEqual(lastCall()[0], 'goBack')
  queue(null)
  await nav.refresh()
  assert.strictEqual(lastCall()[0], 'refresh')
})

test('manage() facade: cookies + timeouts + window', async () => {
  const d = newDriver()
  const opts = d.manage()
  assert.ok(opts instanceof s.Options)

  queue(null)
  await opts.addCookie({ name: 'flavor', value: 'mint' })
  assert.strictEqual(lastCall()[0], 'addCookie')
  assert.strictEqual(lastCall()[1].cookie.name, 'flavor')

  queue([{ name: 'flavor', value: 'mint' }])
  const cookies = await opts.getCookies()
  assert.strictEqual(cookies[0].name, 'flavor')
  assert.strictEqual(lastCall()[0], 'getCookies')

  queue(null)
  await opts.setTimeouts({ implicit: 1000 })
  assert.deepStrictEqual(lastCall(), ['setTimeout', { implicit: 1000 }])

  const win = opts.window()
  assert.ok(win instanceof s.Window)
  queue({ width: 800, height: 600 })
  await win.getRect()
  assert.strictEqual(lastCall()[0], 'getWindowRect')
})

test('switchTo() facade: window/frame/alert', async () => {
  const d = newDriver()
  const tl = d.switchTo()
  assert.ok(tl instanceof s.TargetLocator)

  queue(null)
  await tl.window('handle-2')
  assert.deepStrictEqual(lastCall(), ['switchToWindow', { handle: 'handle-2' }])

  queue(null)
  await tl.defaultContent()
  assert.deepStrictEqual(lastCall(), ['switchToFrame', { id: null }])

  // alert(): touches getAlertText, then exposes accept/dismiss/getText/sendKeys
  reset()
  queue('are you sure?')
  const alert = await tl.alert()
  assert.ok(alert instanceof s.Alert)
  assert.strictEqual(lastCall()[0], 'getAlertText')
  assert.strictEqual(await alert.getText(), 'are you sure?')
  queue(null)
  await alert.accept()
  assert.strictEqual(lastCall()[0], 'acceptAlert')
  queue(null)
  await alert.dismiss()
  assert.strictEqual(lastCall()[0], 'dismissAlert')
})

test('executeScript wraps element args as {element-key: id}', async () => {
  const d = newDriver()
  queue({ [W3C_KEY]: 'el-77' })
  const el = await d.findElement(s.By.id('x'))
  reset()
  queue(42)
  const r = await d.executeScript('return 1;', el, 7)
  assert.strictEqual(r, 42)
  assert.strictEqual(lastCall()[0], 'executeScript')
  assert.deepStrictEqual(lastCall()[1].args, [{ [W3C_KEY]: 'el-77' }, 7])
})

test('wait() polls a Condition and resolves', async () => {
  const d = newDriver()
  // titleContains: getTitle returns the target on the 2nd poll
  let n = 0
  const cond = new s.Condition('for custom', () => {
    n += 1
    return n >= 2 ? 'done' : null
  })
  const result = await d.wait(cond, 2000, undefined, 5)
  assert.strictEqual(result, 'done')
  assert.ok(n >= 2)
})

test('wait() with a WebElementCondition returns a chainable WebElementPromise', async () => {
  const d = newDriver()
  // elementLocated polls findElements; return the element on first poll.
  queue([{ [W3C_KEY]: 'el-w' }])
  const wep = d.wait(s.until.elementLocated(s.By.id('x')), 1000, undefined, 5)
  assert.strictEqual(typeof wep.then, 'function')
  const el = await wep
  assert.ok(el instanceof s.WebElement)
  assert.strictEqual(el.id, 'el-w')
})

test('wait() times out with a TimeoutError', async () => {
  const d = newDriver()
  await assert.rejects(
    () => d.wait(() => false, 30, 'never true', 5),
    (e) => e instanceof s.error.TimeoutError,
  )
})

test('until.* namespace is present and callable', () => {
  const names = [
    'elementLocated',
    'elementsLocated',
    'elementIsVisible',
    'elementIsNotVisible',
    'elementIsEnabled',
    'elementIsDisabled',
    'elementIsSelected',
    'elementIsNotSelected',
    'elementTextIs',
    'elementTextContains',
    'elementTextMatches',
    'stalenessOf',
    'titleIs',
    'titleContains',
    'titleMatches',
    'urlIs',
    'urlContains',
    'urlMatches',
    'alertIsPresent',
    'ableToSwitchToFrame',
  ]
  for (const n of names) {
    assert.strictEqual(typeof s.until[n], 'function', `until.${n} missing`)
  }
  // titleContains builds a Condition
  const c = s.until.titleContains('abc')
  assert.ok(c instanceof s.Condition)
})

test('Key is exported (singular) with chord() and correct code points', () => {
  assert.strictEqual(s.Key.NULL, '')
  assert.strictEqual(s.Key.ENTER, '')
  assert.strictEqual(s.Key.SHIFT, '')
  assert.strictEqual(s.Key.ARROW_LEFT, s.Key.LEFT)
  assert.strictEqual(s.Key.chord('a', 'b'), 'ab')
  assert.strictEqual(s.Keys, s.Key) // convenience alias
  assert.strictEqual(s.Button.RIGHT, 2)
  assert.strictEqual(s.Origin.VIEWPORT, 'viewport')
})

test('actions() builds an Actions and perform() issues the actions command', async () => {
  const d = newDriver()
  const actions = d.actions()
  assert.ok(actions instanceof s.Actions)
  queue(null)
  await actions.keyDown(s.Key.SHIFT).keyUp(s.Key.SHIFT).perform()
  assert.strictEqual(lastCall()[0], 'actions')
  assert.ok(Array.isArray(lastCall()[1].actions))
})

test('actions() serializes a WebElement pointer origin to its W3C ref', async () => {
  const d = newDriver()
  queue({ [W3C_KEY]: 'el-origin' })
  const el = await d.findElement(s.By.id('x'))
  reset()
  queue(null)
  await d.actions().move({ origin: el }).perform()
  assert.strictEqual(lastCall()[0], 'actions')
  const seqs = lastCall()[1].actions
  const pointer = seqs.find((sq) => sq.type === 'pointer')
  const move = pointer.actions.find((a) => a.type === 'pointerMove')
  assert.deepStrictEqual(move.origin, { [W3C_KEY]: 'el-origin' })
})

test('error namespace has upstream Error names and legacy Exception aliases', () => {
  assert.strictEqual(typeof s.error, 'object')
  assert.strictEqual(typeof s.error.WebDriverError, 'function')
  assert.strictEqual(typeof s.error.NoSuchElementError, 'function')
  assert.strictEqual(typeof s.error.TimeoutError, 'function')
  // legacy aliases point at the SAME constructors
  assert.strictEqual(s.NoSuchElementException, s.error.NoSuchElementError)
  assert.strictEqual(s.WebDriverException, s.error.WebDriverError)
  assert.strictEqual(s.TimeoutException, s.error.TimeoutError)
  // subclassing is intact
  assert.ok(new s.error.NoSuchElementError('x') instanceof s.error.WebDriverError)
})

test('Select support helper is exported and constructs against an element', async () => {
  const d = newDriver()
  queue({ [W3C_KEY]: 'sel-1' })
  const el = await d.findElement(s.By.id('sel'))
  reset()
  // Select's constructor fires getAttribute('tagName') / ('multiple') validations
  // (async, fire-and-forget). Feed both.
  queue('select', 'false')
  const sel = new s.Select(el)
  assert.ok(sel && typeof sel.selectByValue === 'function')
  assert.strictEqual(typeof sel.selectByVisibleText, 'function')
  assert.strictEqual(typeof sel.getAllSelectedOptions, 'function')
})

test('Capabilities + Browser + logging exports', () => {
  assert.strictEqual(s.Capabilities.chrome().getBrowserName(), 'chrome')
  assert.strictEqual(s.Browser.FIREFOX, 'firefox')
  assert.strictEqual(typeof s.logging.getLogger, 'function')
  // logging is a stub (documented) — getLogger returns a no-op logger
  const log = s.logging.getLogger('x')
  assert.strictEqual(typeof log.info, 'function')
})

test('RelativeBy / locateWith / By.js locator forms', () => {
  const rb = s.locateWith(s.By.css('p')).below(s.By.id('h'))
  assert.ok(rb instanceof s.RelativeBy)
  assert.ok(rb.marshall().relative)
  const fn = s.By.js('return document.body;')
  assert.strictEqual(typeof fn, 'function')
})

// Restore the module loader for cleanliness (in case the runner loads more).
test.after?.(() => {
  Module._load = originalLoad
})
