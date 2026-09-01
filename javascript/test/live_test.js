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
const fs = require('node:fs')

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

// Driver orchestration over the engine: resolve + spawn a chromedriver
// in-binding (no chromedriver on PATH, no Grid), drive a page through the
// self-launched driver, and tear the process down — the ensureDriver ->
// url/pid -> WebDriver -> stop() flow the C ABI exposes for FFI bindings.
// Self-skips (does NOT fail) if the engine can't resolve a driver here.
test('driver orchestration', async (t) => {
  // Resolve only — skip loudly if the engine can't produce a driver here
  // (offline + empty cache). This is the same self-skip the native client uses.
  const path = s.resolveDriver('chrome')
  if (!path) {
    t.skip('engine cannot resolve a chromedriver (offline, no cache)')
    return
  }
  assert.ok(fs.existsSync(path), `resolveDriver returned a non-file: ${path}`)

  // ensureDriver spawns it; the handle exposes url + pid, independent of any
  // W3C session.
  const proc = s.ensureDriver('chrome')
  assert.ok(proc instanceof s.DriverProcess, 'ensureDriver did not return a DriverProcess')
  try {
    assert.ok(proc.url.startsWith('http'), `driver url=${proc.url}`)
    assert.ok(proc.pid > 0, `driver pid=${proc.pid}`)
  } finally {
    proc.stop()
    assert.strictEqual(proc.pid, 0, 'stop() should clear the handle')
  }

  // Builder without usingServer() ties it together: the engine spawns its own
  // driver, runs a session, and stops the driver on quit — the whole point of
  // the orchestration ABI. Honors SEL_CHROME_BINARY if set. This must NOT need
  // chromedriver on PATH.
  const chromeArgs = ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
  const chromeOptions = { args: chromeArgs }
  const chromeBin = process.env.SEL_CHROME_BINARY
  if (chromeBin) chromeOptions.binary = chromeBin
  const d = new s.Builder()
    .forBrowser('chrome')
    .withCapabilities({ 'goog:chromeOptions': chromeOptions })
    .build()
  try {
    assert.ok(d.sessionId, 'no session id from Builder-launched Chrome')
    const html = '<html><head><title>Aether Selenium</title></head><body><h1 id="hdr">Hello</h1></body></html>'
    d.get(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`)
    assert.strictEqual(d.title, 'Aether Selenium', `title=${d.title}`)
    assert.strictEqual(d.findElement(s.By.id('hdr')).text, 'Hello')
  } finally {
    d.quit()
  }
})

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

    // From here on, everything is synchronous (blocking FFI). Builder with an
    // explicit usingServer() -> the Remote/WebDriver path against a running driver.
    const d = new s.Builder()
      .forBrowser('chrome')
      .usingServer(`http://127.0.0.1:${cdPort}`)
      .withCapabilities({
        'goog:chromeOptions': {
          args: ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
        },
      })
      .build()
    try {
      assert.ok(d.sessionId, 'no session id after newSession')

      d.get(`${base}/one`)
      assert.strictEqual(d.title, 'Page One')
      assert.strictEqual(d.findElement(s.By.id('hdr')).text, 'One')
      assert.strictEqual(d.findElement(s.By.css('#go')).tagName.toLowerCase(), 'a')

      // navigation history
      d.findElement(s.By.id('go')).click()
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

      // timeout setter + async script: the async callback is arguments[last].
      d.setScriptTimeout(10000)
      assert.strictEqual(d.executeAsyncScript('arguments[arguments.length-1](42);'), 42)

      // W3C actions: pointer click on the button.
      const rect = d.findElement(s.By.id('btn')).rect
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
      assert.strictEqual(d.findElement(s.By.id('hdr')).text, 'clicked')
      d.clearActions()

      // screenshot -> PNG
      const raw = Buffer.from(d.screenshotBase64(), 'base64')
      assert.strictEqual(raw.subarray(1, 4).toString('ascii'), 'PNG')

      // negative path: typed error
      assert.throws(
        () => d.findElement(s.By.id('does-not-exist')),
        (e) => e instanceof s.NoSuchElementException,
      )
    } finally {
      d.quit()
    }
  } finally {
    cd.kill()
    web.kill()
  }
})

// Live WebDriver-BiDi: subscribe to log.entryAdded, emit a console.log via
// executeScript, receive the event, and issue a plain BiDi command. Same fixture
// as above: own chromedriver on an ephemeral port, self-skip if absent. All BiDi
// calls are synchronous blocking FFI.
test('live chrome + bidi', async (t) => {
  const driverBin = which('chromedriver')
  if (!driverBin) {
    t.skip('chromedriver not on PATH')
    return
  }

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
      assert.ok(d.bidiAvailable(), 'session negotiated no BiDi webSocketUrl')

      d.get('data:text/html,<title>BiDi</title><h1>hi</h1>')

      const ack = d.bidi.subscribe(s.BidiEvent.LOG_ENTRY_ADDED)
      assert.strictEqual(ack.type, 'success', `subscribe ack: ${JSON.stringify(ack)}`)

      d.executeScript("console.log('bidi-hello');")

      const ev = d.bidi.nextEvent(s.BidiEvent.LOG_ENTRY_ADDED, 8000)
      assert.ok(ev, 'no log.entryAdded event received')
      assert.strictEqual(ev.method, s.BidiEvent.LOG_ENTRY_ADDED)
      assert.ok(JSON.stringify(ev).includes('bidi-hello'), `event missing text: ${JSON.stringify(ev)}`)

      const status = d.bidi.command('session.status')
      assert.strictEqual(status.type, 'success', `session.status: ${JSON.stringify(status)}`)

      // typed convenience commands: topContext / evaluateValue (incl. promise-await)
      const ctx = d.bidi.topContext()
      assert.ok(ctx, `topContext() returned falsy: ${JSON.stringify(ctx)}`)
      assert.strictEqual(d.bidi.evaluateValue('6*7'), 42, 'evaluateValue(6*7) !== 42')
      assert.strictEqual(
        d.bidi.evaluateValue('Promise.resolve(41+1)'),
        42,
        'evaluateValue(Promise.resolve(41+1)) !== 42 (promise-await)',
      )

      // network interception: subscribe, add an intercept, trigger a fetch,
      // catch the paused beforeRequestSent event, and let it continue.
      const subNet = d.bidi.subscribe(s.BidiEvent.BEFORE_REQUEST_SENT)
      assert.strictEqual(subNet.type, 'success', `network subscribe ack: ${JSON.stringify(subNet)}`)

      const ic = d.bidi.addIntercept('beforeRequestSent', '')
      assert.ok(ic, `addIntercept returned falsy: ${JSON.stringify(ic)}`)

      d.executeScript("fetch('https://example.com/blocked').catch(()=>{});")

      const netEv = d.bidi.nextEvent(s.BidiEvent.BEFORE_REQUEST_SENT, 8000)
      assert.ok(netEv, 'no network.beforeRequestSent event received')

      const rid = s.BiDi.eventRequestId(netEv)
      assert.ok(rid, `eventRequestId returned falsy: ${JSON.stringify(netEv)}`)

      const cont = d.bidi.continueRequest(rid)
      assert.strictEqual(cont.type, 'success', `continueRequest reply: ${JSON.stringify(cont)}`)

      const rem = d.bidi.removeIntercept(ic)
      assert.strictEqual(rem.type, 'success', `removeIntercept reply: ${JSON.stringify(rem)}`)

      // request MOCKING: intercept beforeRequestSent, fire a cross-origin fetch,
      // catch the paused request, and fulfill it with provideResponse — the page
      // sees our mock body, never the real network.
      const ic2 = d.bidi.addIntercept('beforeRequestSent', '')
      assert.ok(ic2, `addIntercept(2) returned falsy: ${JSON.stringify(ic2)}`)

      d.executeScript(
        "window.__mock='';fetch('https://example.com/api').then(r=>r.text()).then(t=>{window.__mock=t}).catch(()=>{});",
      )

      const ev2 = d.bidi.nextEvent(s.BidiEvent.BEFORE_REQUEST_SENT, 8000)
      assert.ok(ev2, 'no network.beforeRequestSent event for mock fetch')
      const rid2 = s.BiDi.eventRequestId(ev2)
      assert.ok(rid2, `eventRequestId(2) returned falsy: ${JSON.stringify(ev2)}`)

      const resp = d.bidi.provideResponse(rid2, {
        status: 200,
        contentType: 'text/plain',
        body: 'MOCKED-BODY',
      })
      assert.strictEqual(resp.type, 'success', `provideResponse reply: ${JSON.stringify(resp)}`)

      // The fetch resolves asynchronously in the page; poll (synchronously,
      // since the client is blocking) until the mock body lands.
      const sleep = (ms) => {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
      }
      let mock = ''
      for (let i = 0; i < 25 && !mock.includes('MOCKED-BODY'); i++) {
        mock = d.executeScript('return window.__mock;') || ''
        if (mock.includes('MOCKED-BODY')) break
        sleep(200)
      }
      assert.ok(mock.includes('MOCKED-BODY'), `page never saw mock body: ${JSON.stringify(mock)}`)

      d.bidi.removeIntercept(ic2)

      // network.setCacheBehavior: disable the HTTP cache for the session, then
      // restore it. (continueWithAuth needs an auth server, so it is not
      // live-tested here — its module wiring is exercised by loading the binding.)
      const bypass = d.bidi.setCacheBehavior('bypass')
      assert.strictEqual(bypass.type, 'success', `setCacheBehavior('bypass'): ${JSON.stringify(bypass)}`)
      const dflt = d.bidi.setCacheBehavior('default')
      assert.strictEqual(dflt.type, 'success', `setCacheBehavior('default'): ${JSON.stringify(dflt)}`)
      assert.strictEqual(typeof d.bidi.continueWithAuth, 'function', 'continueWithAuth missing')
    } finally {
      d.quit()
    }
  } finally {
    cd.kill()
  }
})

// Live atom-backed commands: isDisplayed / getAttribute / relative locators all
// run the shared JS atoms in-page via the engine. Same fixture as above: own
// chromedriver on an ephemeral port, self-skip if absent. Uses a data: URL so no
// content server is needed. All calls are synchronous blocking FFI.
test('live chrome + atoms', async (t) => {
  const driverBin = which('chromedriver')
  if (!driverBin) {
    t.skip('chromedriver not on PATH')
    return
  }

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

      const html =
        '<title>Atoms</title>' +
        "<h1 id='hdr'>Header</h1>" +
        "<button id='btn'>go</button>" +
        "<p id='gone' style='display:none'>hidden</p>" +
        "<a id='lnk' href='https://example.com/x'>link</a>"
      d.get(`data:text/html,${encodeURIComponent(html)}`)

      // isDisplayed atom
      assert.strictEqual(d.findElement(s.By.id('hdr')).isDisplayed(), true, '#hdr should be displayed')
      assert.strictEqual(d.findElement(s.By.id('gone')).isDisplayed(), false, '#gone should be hidden')

      // getAttribute atom (property-or-attribute)
      const href = d.findElement(s.By.id('lnk')).getAttribute('href')
      assert.ok(href.includes('example.com/x'), `href missing: ${href}`)

      // relative locators: the button is below the header
      const below = d.findRelative('button', { kind: 'below', sel: '#hdr' })
      assert.ok(below.length >= 1, `findRelative found none: ${below.length}`)
    } finally {
      d.quit()
    }
  } finally {
    cd.kill()
  }
})
