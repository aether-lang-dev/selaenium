// Live end-to-end + surface test (Node): a real headless Chrome session driven
// through the pure-Aether engine from JS. The whole pipeline — Node -> koffi ->
// libselenium_core.so -> std.http.client -> chromedriver -> Chrome. Skips if
// chromedriver is absent. Uses node:test.
//
// IMPORTANT: the WebDriver surface is async (Promise-returning) exactly like
// mainstream selenium-webdriver, but each command is a blocking FFI round-trip
// under the hood (the resolved Promise's work runs synchronously before it
// resolves). So the content server the browser fetches from MUST live in a
// SEPARATE process (test/content_server.js) — an in-process server could not
// answer while an `await d.get()` blocks. chromedriver + the content server are
// both started (and waited on) BEFORE any command. The BiDi channel (d.bidi.*)
// stays synchronous — it has no mainstream ABI to match.
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
    assert.strictEqual(await d.findElement(s.By.id('hdr')).getText(), 'Hello')
  } finally {
    d.quit()
  }
})

// Live Firefox smoke over the engine-managed geckodriver: resolve + spawn a
// geckodriver in-binding (no geckodriver on PATH, no Grid), open a headless
// Firefox session against it, drive a data: page, and assert title + element
// text — WebDriver.firefox/headlessFirefox against real Firefox. Self-skips
// when the engine cannot resolve a geckodriver here.
test('live firefox', async (t) => {
  const path = s.resolveDriver('firefox')
  if (!path) {
    t.skip('engine cannot resolve a geckodriver (no Firefox/cache)')
    return
  }
  assert.ok(fs.existsSync(path), `resolveDriver(firefox) returned a non-file: ${path}`)

  const proc = s.ensureDriver('firefox')
  assert.ok(proc instanceof s.DriverProcess, 'ensureDriver(firefox) did not return a DriverProcess')
  try {
    assert.ok(proc.url.startsWith('http'), `geckodriver url=${proc.url}`)
    const d = s.WebDriver.headlessFirefox(proc.url)
    try {
      assert.ok(d.sessionId, 'no session id from headlessFirefox')
      const html = '<!doctype html><title>Aether Firefox</title><h1 id="hdr">Hello FF</h1>'
      d.get(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`)
      assert.strictEqual(d.title, 'Aether Firefox', `title=${d.title}`)
      assert.strictEqual(await d.findElement(s.By.id('hdr')).getText(), 'Hello FF')
    } finally {
      d.quit()
    }
  } finally {
    proc.stop()
  }
})

// The edge/safari factories are not live-runnable here (no Edge on Linux,
// Safari is macOS-only), so this is a surface check that they exist and set the
// right browserName — each opens against a dead port and fails transport (-1),
// proving the factory is callable with the chrome shape. No browser is touched.
test('firefox/edge/safari factories set the right browserName', () => {
  for (const open of [
    () => s.WebDriver.firefox('http://127.0.0.1:1'),
    () => s.WebDriver.headlessFirefox('http://127.0.0.1:1'),
    () => s.WebDriver.edge('http://127.0.0.1:1'),
    () => s.WebDriver.headlessEdge('http://127.0.0.1:1'),
    () => s.WebDriver.safari('http://127.0.0.1:1'),
  ]) {
    assert.throws(open, (e) => e.code === -1)
  }
})

test('live chrome + surface', async (t) => {
  // Source the driver from the engine's Selenium-Manager port (a VERSION-MATCHED
  // binary), not PATH — a PATH chromedriver can mismatch the installed Chrome
  // (skew). This test still exercises the BYO-endpoint path (spawn a driver, then
  // usingServer(url)/headlessChrome(url)) — distinct from the fully
  // engine-managed 'driver orchestration' test; only the binary source changed.
  const driverBin = s.resolveDriver('chrome') || which('chromedriver')
  if (!driverBin || !fs.existsSync(driverBin)) {
    t.skip('no chromedriver (engine could not resolve one, none on PATH)')
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

    // Builder with an explicit usingServer() -> the Remote/WebDriver path against
    // a running driver. The surface is async (Promise-returning) exactly like
    // mainstream selenium-webdriver, so every command is awaited.
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

      await d.get(`${base}/one`)
      assert.strictEqual(await d.getTitle(), 'Page One')
      assert.strictEqual(await d.findElement(s.By.id('hdr')).getText(), 'One')
      assert.strictEqual((await d.findElement(s.By.css('#go')).getTagName()).toLowerCase(), 'a')

      // navigation history
      await d.findElement(s.By.id('go')).click()
      assert.strictEqual(await d.getTitle(), 'Page Two')
      await d.back()
      assert.strictEqual(await d.getTitle(), 'Page One')
      await d.forward()
      assert.strictEqual(await d.getTitle(), 'Page Two')
      await d.back()

      // cookies
      await d.deleteAllCookies()
      await d.addCookie({ name: 'flavor', value: 'mint' })
      assert.strictEqual((await d.getCookie('flavor')).value, 'mint')
      assert.ok((await d.getCookies()).some((c) => c.name === 'flavor'))
      await d.deleteCookie('flavor')
      assert.ok(!(await d.getCookies()).some((c) => c.name === 'flavor'))

      // windows
      const handles = await d.getAllWindowHandles()
      assert.ok(handles.length >= 1)
      assert.ok(handles.includes(await d.getWindowHandle()))
      await d.setWindowRect({ width: 900, height: 650 })
      assert.strictEqual((await d.getWindowRect()).width, 900)

      // execute_script shapes
      assert.strictEqual(await d.executeScript('return 6*7;'), 42)
      assert.strictEqual(await d.executeScript("return 'hi';"), 'hi')
      assert.deepStrictEqual(await d.executeScript('return [1,2,3];'), [1, 2, 3])
      assert.deepStrictEqual(await d.executeScript('return {a:1};'), { a: 1 })
      assert.strictEqual(await d.executeScript('return arguments[0]+arguments[1];', 40, 2), 42)

      // timeout setter + async script: the async callback is arguments[last].
      await d.setScriptTimeout(10000)
      assert.strictEqual(await d.executeAsyncScript('arguments[arguments.length-1](42);'), 42)

      // W3C actions: pointer click on the button.
      const rect = await d.findElement(s.By.id('btn')).getRect()
      const cx = Math.round(rect.x + rect.width / 2)
      const cy = Math.round(rect.y + rect.height / 2)
      await d.performActions([
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
      assert.strictEqual(await d.findElement(s.By.id('hdr')).getText(), 'clicked')
      await d.clearActions()

      // screenshot -> PNG
      const raw = Buffer.from(await d.screenshotBase64(), 'base64')
      assert.strictEqual(raw.subarray(1, 4).toString('ascii'), 'PNG')

      // negative path: typed error
      await assert.rejects(
        () => d.findElement(s.By.id('does-not-exist')),
        (e) => e instanceof s.NoSuchElementException,
      )
    } finally {
      await d.quit()
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
  // Source the driver from the engine's Selenium-Manager port (a VERSION-MATCHED
  // binary), not PATH — a PATH chromedriver can mismatch the installed Chrome
  // (skew). This test still exercises the BYO-endpoint path (spawn a driver, then
  // usingServer(url)/headlessChrome(url)) — distinct from the fully
  // engine-managed 'driver orchestration' test; only the binary source changed.
  const driverBin = s.resolveDriver('chrome') || which('chromedriver')
  if (!driverBin || !fs.existsSync(driverBin)) {
    t.skip('no chromedriver (engine could not resolve one, none on PATH)')
    return
  }

  const cdPort = await freePort()
  const cd = spawn(driverBin, [`--port=${cdPort}`], { stdio: 'ignore' })

  try {
    if (!(await waitUp(cdPort))) {
      t.skip('chromedriver did not come up')
      return
    }

    // The classic WebDriver surface is async (Promise-returning); the BiDi
    // channel (d.bidi.*) is synchronous blocking FFI.
    const d = s.WebDriver.headlessChrome(`http://127.0.0.1:${cdPort}`)
    try {
      assert.ok(d.sessionId, 'no session id after newSession')
      assert.ok(d.bidiAvailable(), 'session negotiated no BiDi webSocketUrl')

      await d.get('data:text/html,<title>BiDi</title><h1>hi</h1>')

      const ack = d.bidi.subscribe(s.BidiEvent.LOG_ENTRY_ADDED)
      assert.strictEqual(ack.type, 'success', `subscribe ack: ${JSON.stringify(ack)}`)

      await d.executeScript("console.log('bidi-hello');")

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

      await d.executeScript("fetch('https://example.com/blocked').catch(()=>{});")

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

      await d.executeScript(
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
        mock = (await d.executeScript('return window.__mock;')) || ''
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
      await d.quit()
    }
  } finally {
    cd.kill()
  }
})

// Live atom-backed commands: isDisplayed / getAttribute / relative locators all
// run the shared JS atoms in-page via the engine. Same fixture as above: own
// chromedriver on an ephemeral port, self-skip if absent. Uses a data: URL so no
// content server is needed. The surface is async (Promise-returning), so every
// command is awaited.
test('live chrome + atoms', async (t) => {
  // Source the driver from the engine's Selenium-Manager port (a VERSION-MATCHED
  // binary), not PATH — a PATH chromedriver can mismatch the installed Chrome
  // (skew). This test still exercises the BYO-endpoint path (spawn a driver, then
  // usingServer(url)/headlessChrome(url)) — distinct from the fully
  // engine-managed 'driver orchestration' test; only the binary source changed.
  const driverBin = s.resolveDriver('chrome') || which('chromedriver')
  if (!driverBin || !fs.existsSync(driverBin)) {
    t.skip('no chromedriver (engine could not resolve one, none on PATH)')
    return
  }

  const cdPort = await freePort()
  const cd = spawn(driverBin, [`--port=${cdPort}`], { stdio: 'ignore' })

  try {
    if (!(await waitUp(cdPort))) {
      t.skip('chromedriver did not come up')
      return
    }

    // The classic surface is async (Promise-returning); the atom-backed commands
    // (isDisplayed/getAttribute) and findRelative are exposed through it too.
    const d = s.WebDriver.headlessChrome(`http://127.0.0.1:${cdPort}`)
    try {
      assert.ok(d.sessionId, 'no session id after newSession')

      const html =
        '<title>Atoms</title>' +
        "<h1 id='hdr'>Header</h1>" +
        "<button id='btn'>go</button>" +
        "<p id='gone' style='display:none'>hidden</p>" +
        "<a id='lnk' href='https://example.com/x'>link</a>"
      await d.get(`data:text/html,${encodeURIComponent(html)}`)

      // isDisplayed atom
      assert.strictEqual(
        await d.findElement(s.By.id('hdr')).isDisplayed(),
        true,
        '#hdr should be displayed',
      )
      assert.strictEqual(
        await d.findElement(s.By.id('gone')).isDisplayed(),
        false,
        '#gone should be hidden',
      )

      // getAttribute atom (property-or-attribute)
      const href = await d.findElement(s.By.id('lnk')).getAttribute('href')
      assert.ok(href.includes('example.com/x'), `href missing: ${href}`)

      // relative locators: the button is below the header
      const below = d.findRelative('button', { kind: 'below', sel: '#hdr' })
      assert.ok(below.length >= 1, `findRelative found none: ${below.length}`)

      // Shadow DOM: attach an open shadow root hosting a #sinner, then reach
      // inside it via getShadowRoot().findElement(css '#sinner').
      await d.executeScript(
        "var h=document.createElement('div');h.id='shost';document.body.appendChild(h);" +
          "var r=h.attachShadow({mode:'open'});r.innerHTML='<p id=\"sinner\">shadowtext</p>';",
      )
      const shadow = await d.findElement(s.By.id('shost')).getShadowRoot()
      assert.ok(shadow instanceof s.ShadowRoot, 'getShadowRoot did not return a ShadowRoot')
      const inner = await shadow.findElement(s.By.css('#sinner'))
      assert.strictEqual(await inner.getText(), 'shadowtext')
      assert.strictEqual((await shadow.findElements(s.By.css('p'))).length, 1)

      // A non-host element rejects with NoSuchShadowRootError (code 19).
      await assert.rejects(
        () => d.findElement(s.By.id('hdr')).getShadowRoot(),
        (e) => e instanceof s.error.NoSuchShadowRootError && e.code === 19,
      )
    } finally {
      await d.quit()
    }
  } finally {
    cd.kill()
  }
})
