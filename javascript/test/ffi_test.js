// No-browser FFI test: proves the JS koffi binding loads libselenium_core.so and
// marshals correctly, exercising the pure engine helpers and the transport error
// path. Needs only the .so (SELENIUM_CORE_LIB / bundled native/). Uses node:test
// (no jest).
'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const s = require('..')

test('route', () => {
  assert.strictEqual(s.route('get'), 'POST /session/:sessionId/url')
  assert.strictEqual(s.route('nope'), '')
})

test('errorCode', () => {
  assert.strictEqual(s.errorCode('no such element'), 17)
  assert.strictEqual(s.errorCode(''), 0)
})

test('locator css', () => {
  assert.deepStrictEqual(JSON.parse(s.locator(s.By.CSS_SELECTOR, 'div.foo')), {
    using: 'css selector',
    value: 'div.foo',
  })
})

test('locator id rewrite', () => {
  assert.deepStrictEqual(JSON.parse(s.locator(s.By.ID, 'main')), {
    using: 'css selector',
    value: '*[id="main"]',
  })
})

test('transport failure', () => {
  assert.throws(
    () => s.WebDriver.chrome('http://127.0.0.1:1'),
    (e) => e instanceof s.WebDriverError && e.code === -1,
  )
})
