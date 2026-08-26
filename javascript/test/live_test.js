// Live end-to-end + surface test (Node): a real headless Chrome session driven
// through the pure-Aether engine from JS. The whole pipeline — Node -> koffi ->
// libselenium_core.so -> std.http.client -> chromedriver -> Chrome. Skips if
// chromedriver is absent. Uses node:test.
//
// IMPORTANT: the binding's FFI calls are SYNCHRONOUS and block the Node event
// loop, so the content server the browser fetches from MUST live in a SEPARATE
// process (test/content_server.js) — an in-process server could not answer while
// a d.get() blocks. chromedriver + the content server are both started (and
// waited on) BEFORE any blocking FFI call, using async I/O; from newSession
// onward everything is synchronous.
'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const net = require('node:net')
const path = require('node:path')
const { spawn, execFileSync } = require('node:child_process')

const s = require('..')

function which(cmd) {
  for (const dir of (process.env.PATH || '').split(':')) {
    try {
      execFileSync('test', ['-x', `${dir}/${cmd}`])
      return `${dir}/${cmd}`
    } catch {
      /* not here */
    }
  }
  return null
}

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer()
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address()
      srv.close(() => resolve(port))
    })
    srv.on('error', reject)
  })
}

function waitUp(port, timeoutMs = 10000) {
  return new Promise((resolve) => {
    const deadline = Date.now() + timeoutMs
    const tryOnce = () => {
      const sock = net.connect(port, '127.0.0.1')
      sock.on('connect', () => {
        sock.destroy()
        resolve(true)
      })
      sock.on('error', () => {
        sock.destroy()
        if (Date.now() > deadline) resolve(false)
        else setTimeout(tryOnce, 100)
      })
    }
    tryOnce()
  })
}

// Start the out-of-process content server and resolve to [child, port].
function startContentServer() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(__dirname, 'content_server.js')], {
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    let buf = ''
    child.stdout.on('data', (d) => {
      buf += d.toString()
      const m = buf.match(/PORT (\d+)/)
      if (m) resolve([child, Number(m[1])])
    })
    child.on('error', reject)
    setTimeout(() => reject(new Error('content server did not report a port')), 5000)
  })
}

test('live chrome + surface', async (t) => {
  const driverBin = which('chromedriver')
  if (!driverBin) {
    t.skip('chromedriver not on PATH')
    return
  }

  const [web, webPort] = await startContentServer()
  const base = `http://127.0.0.1:${webPort}`

  const cdPort = await freePort()
  const cd = spawn(driverBin, [`--port=${cdPort}`], { stdio: 'ignore' })

  try {
    if (!(await waitUp(cdPort))) {
      t.skip('chromedriver did not come up')
      return
    }

    // From here on, everything is synchronous (blocking FFI).
    const d = s.WebDriver.headlessChrome(`http://127.0.0.1:${cdPort}`)
    try {
      assert.ok(d.sessionId, 'no session id after newSession')

      d.get(`${base}/one`)
      assert.strictEqual(d.title, 'Page One')
      assert.strictEqual(d.findElement(s.By.ID, 'hdr').text, 'One')
      assert.strictEqual(d.findElement(s.By.CSS_SELECTOR, '#go').tagName.toLowerCase(), 'a')

      // navigation history
      d.findElement(s.By.ID, 'go').click()
      assert.strictEqual(d.title, 'Page Two')
      d.back()
      assert.strictEqual(d.title, 'Page One')
      d.forward()
      assert.strictEqual(d.title, 'Page Two')
      d.back()

      // cookies
      d.deleteAllCookies()
      d.addCookie({ name: 'flavor', value: 'mint' })
      assert.strictEqual(d.getCookie('flavor').value, 'mint')
      assert.ok(d.getCookies().some((c) => c.name === 'flavor'))
      d.deleteCookie('flavor')
      assert.ok(!d.getCookies().some((c) => c.name === 'flavor'))

      // windows
      const handles = d.windowHandles
      assert.ok(handles.length >= 1)
      assert.ok(handles.includes(d.currentWindowHandle))
      d.setWindowRect({ width: 900, height: 650 })
      assert.strictEqual(d.getWindowRect().width, 900)

      // execute_script shapes
      assert.strictEqual(d.executeScript('return 6*7;'), 42)
      assert.strictEqual(d.executeScript("return 'hi';"), 'hi')
      assert.deepStrictEqual(d.executeScript('return [1,2,3];'), [1, 2, 3])
      assert.deepStrictEqual(d.executeScript('return {a:1};'), { a: 1 })
      assert.strictEqual(d.executeScript('return arguments[0]+arguments[1];', 40, 2), 42)

      // W3C actions: pointer click on the button.
      const rect = d.findElement(s.By.ID, 'btn').rect
      const cx = Math.round(rect.x + rect.width / 2)
      const cy = Math.round(rect.y + rect.height / 2)
      d.performActions([
        {
          type: 'pointer',
          id: 'mouse',
          parameters: { pointerType: 'mouse' },
          actions: [
            { type: 'pointerMove', duration: 0, x: cx, y: cy },
            { type: 'pointerDown', button: 0 },
            { type: 'pointerUp', button: 0 },
          ],
        },
      ])
      assert.strictEqual(d.findElement(s.By.ID, 'hdr').text, 'clicked')
      d.clearActions()

      // screenshot -> PNG
      const raw = Buffer.from(d.screenshotBase64(), 'base64')
      assert.strictEqual(raw.subarray(1, 4).toString('ascii'), 'PNG')

      // negative path: typed error
      assert.throws(
        () => d.findElement(s.By.ID, 'does-not-exist'),
        (e) => e instanceof s.NoSuchElementError,
      )
    } finally {
      d.quit()
    }
  } finally {
    cd.kill()
    web.kill()
  }
})
