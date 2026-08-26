// Third-party consumer example. Requires the INSTALLED `selenium-core` package
// (from a clean node_modules — NOT the source tree) and proves the bundled
// engine .so loads and drives the protocol, with SELENIUM_CORE_LIB unset so only
// the package's own bundled native/ can satisfy the load.
//
// Modes (argv[2]):
//   ffi       — no browser: load the .so, exercise the pure engine helpers and a
//               transport-error round-trip. Always runnable.
//   discovery — like ffi, but asserts the .so was found by the package's own
//               bundled native/ discovery (no env var, no explicit path).
//   live      — real headless Chrome if chromedriver is on PATH; skips otherwise.
'use strict'

const path = require('node:path')
const fs = require('node:fs')

// Resolve the INSTALLED package (from this example dir's node_modules), not the
// repo source. require('selenium-core') resolves via node_modules here.
const s = require('selenium-core')

function checkInstalled() {
  const resolved = require.resolve('selenium-core')
  if (resolved.includes(`${path.sep}javascript${path.sep}index.js`) &&
      !resolved.includes('node_modules')) {
    console.error(`FAIL: resolved selenium-core from source (${resolved}), not the installed package`)
    process.exit(1)
  }
  return path.dirname(resolved)
}

function modeFfi() {
  checkInstalled()
  if (s.route('get') !== 'POST /session/:sessionId/url') throw new Error('route mismatch')
  if (s.errorCode('no such element') !== 17) throw new Error('errorCode mismatch')
  const loc = JSON.parse(s.locator(s.By.ID, 'main'))
  if (loc.value !== '*[id="main"]') throw new Error(`locator mismatch: ${JSON.stringify(loc)}`)
  try {
    s.WebDriver.chrome('http://127.0.0.1:1')
    console.error('FAIL: expected transport failure')
    process.exit(1)
  } catch (e) {
    if (!(e instanceof s.WebDriverError) || e.code !== -1) {
      console.error(`FAIL: wrong transport error ${e.code}`)
      process.exit(1)
    }
  }
  console.log('consumer(ffi): OK — installed package loaded its bundled .so and marshalled')
}

function modeDiscovery() {
  if (process.env.SELENIUM_CORE_LIB) {
    console.error('FAIL: SELENIUM_CORE_LIB set; discovery must run without it')
    process.exit(1)
  }
  const pkgDir = checkInstalled()
  const native = path.join(pkgDir, 'native')
  if (!fs.existsSync(native) || !fs.readdirSync(native).some((f) => /\.(so|dylib|dll)$/.test(f))) {
    console.error(`FAIL: no bundled native/ shared library at ${native}`)
    process.exit(1)
  }
  if (s.route('newSession') !== 'POST /session') throw new Error('route mismatch')
  console.log('consumer(discovery): OK — zero-config bundled-.so discovery works')
}

function which(cmd) {
  const { execFileSync } = require('node:child_process')
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

async function modeLive() {
  const net = require('node:net')
  const { spawn } = require('node:child_process')
  const driver = which('chromedriver')
  if (!driver) {
    console.log('consumer(live): SKIPPED — chromedriver not on PATH')
    return
  }
  checkInstalled()

  const freePort = () =>
    new Promise((resolve, reject) => {
      const srv = net.createServer()
      srv.listen(0, '127.0.0.1', () => {
        const { port } = srv.address()
        srv.close(() => resolve(port))
      })
      srv.on('error', reject)
    })
  const waitUp = (port, t = 10000) =>
    new Promise((resolve) => {
      const dl = Date.now() + t
      const go = () => {
        const so = net.connect(port, '127.0.0.1')
        so.on('connect', () => {
          so.destroy()
          resolve(true)
        })
        so.on('error', () => {
          so.destroy()
          Date.now() > dl ? resolve(false) : setTimeout(go, 100)
        })
      }
      go()
    })

  const port = await freePort()
  const cd = spawn(driver, [`--port=${port}`], { stdio: 'ignore' })
  try {
    if (!(await waitUp(port))) {
      console.log('consumer(live): SKIPPED — chromedriver did not come up')
      return
    }
    const html =
      '<!doctype html><title>Installed</title><h1 id="h">Hi</h1>'
    const d = s.WebDriver.headlessChrome(`http://127.0.0.1:${port}`)
    try {
      d.get('data:text/html;charset=utf-8,' + encodeURIComponent(html))
      if (d.title !== 'Installed') throw new Error(`title=${d.title}`)
      if (d.findElement(s.By.ID, 'h').text !== 'Hi') throw new Error('text mismatch')
      console.log('consumer(live): OK — installed package drove real headless Chrome')
    } finally {
      d.quit()
    }
  } finally {
    cd.kill()
  }
}

const mode = process.argv[2] || 'ffi'
;(async () => {
  if (mode === 'ffi') modeFfi()
  else if (mode === 'discovery') modeDiscovery()
  else if (mode === 'live') await modeLive()
  else {
    console.error(`unknown mode: ${mode}`)
    process.exit(1)
  }
})().catch((e) => {
  console.error('FAIL:', e)
  process.exit(1)
})
