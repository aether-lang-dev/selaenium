## Live end-to-end + surface test (Nim): a real headless Chrome session driven
## through the pure-Aether engine via the linked .so, with a std/net content
## server (on its own thread — Nim threads are OS threads, so a blocking FFI
## call on the main thread doesn't stall the server) for a real cookie/nav
## origin. Skips if chromedriver is absent.
import std/[json, os, osproc, net, strutils, base64, times]
import selenium

const
  pageOne = "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>" &
    "<a id=\"go\" href=\"/two\">to two</a>" &
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
  pageTwo = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>"
  # A form page for the convenience-tier live test: a <select>, a text input,
  # a button that reveals a hidden node after a short delay (for the waits), and
  # a right-click target that records a contextmenu.
  pageForm = "<!doctype html><title>Form Page</title>" &
    "<select id=\"country\"><option value=\"us\">United States</option>" &
    "<option value=\"es\">Spain</option><option value=\"fr\">France</option></select>" &
    "<input id=\"txt\">" &
    "<button id=\"reveal\" onclick=\"setTimeout(function(){" &
    "var p=document.createElement('p');p.id='late';p.textContent='here';" &
    "document.body.appendChild(p);},400)\">reveal</button>" &
    "<div id=\"ctx\" oncontextmenu=\"this.textContent='ctx';return false;\">rc</div>"

var serverStop = false

proc freePort(): Port =
  let s = newSocket()
  s.bindAddr(Port(0), "127.0.0.1")
  let p = s.getLocalAddr()[1]
  s.close()
  p

proc waitUp(port: Port, timeoutMs: int): bool =
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    try:
      let s = newSocket()
      s.connect("127.0.0.1", port)
      s.close()
      return true
    except OSError, CatchableError:
      sleep(100)
  false

proc contentServer(port: Port) {.thread.} =
  let listener = newSocket()
  listener.setSockOpt(OptReuseAddr, true)
  listener.bindAddr(port, "127.0.0.1")
  listener.listen()
  while not serverStop:
    var client: Socket
    var address = ""
    try:
      listener.acceptAddr(client, address)
    except CatchableError:
      break
    try:
      let req = client.recvLine(timeout = 2000)
      let body =
        if req.contains("/two"): pageTwo
        elif req.contains("/form"): pageForm
        else: pageOne
      client.send("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" &
                  "Content-Length: " & $body.len & "\r\nConnection: close\r\n\r\n" & body)
    except CatchableError:
      discard
    client.close()
  listener.close()

proc which(cmd: string): string =
  for dir in getEnv("PATH").split(':'):
    let p = dir / cmd
    if fileExists(p): return p
  ""

proc main() =
  let driverBin = which("chromedriver")
  if driverBin.len == 0:
    echo "SKIPPED: chromedriver not on PATH"
    return

  let webPort = freePort()
  var srvThread: Thread[Port]
  createThread(srvThread, contentServer, webPort)
  let base = "http://127.0.0.1:" & $webPort.int

  let cdPort = freePort()
  let cd = startProcess(driverBin, args = ["--port=" & $cdPort.int],
                        options = {poUsePath})
  try:
    if not waitUp(cdPort, 10000):
      echo "SKIPPED: chromedriver did not come up"
      return
    let d = headlessChrome("http://127.0.0.1:" & $cdPort.int)
    try:
      doAssert d.sessionId.len > 0
      echo "  ok: session started"

      d.get(base & "/one")
      doAssert d.title == "Page One"
      doAssert d.findElement(By.id("hdr")).text == "One"
      doAssert d.findElement(By.cssSelector("#go")).tagName.toLowerAscii == "a"
      echo "  ok: navigate + find + text/tag"

      # atom-backed commands: isDisplayed / getAttribute / relative locators,
      # each run in-page by the shared JS atoms in the engine.
      let atomsUrl = "data:text/html," &
        "<!doctype html><title>Atoms</title>" &
        "<h1 id='hdr'>H</h1>" &
        "<button id='btn'>b</button>" &
        "<p id='gone' style='display:none'>hidden</p>" &
        "<a id='lnk' href='https://example.com/x'>lnk</a>"
      d.get(atomsUrl)
      doAssert d.findElement(By.id("hdr")).isDisplayed
      doAssert not d.findElement(By.id("gone")).isDisplayed
      doAssert d.findElement(By.id("lnk")).getAttribute("href").getStr.contains("example.com/x")
      let below = d.findRelative("button", %*{"kind": "below", "sel": "#hdr"})
      doAssert below.len >= 1
      echo "  ok: atoms (isDisplayed / getAttribute / findRelative)"

      d.get(base & "/one")
      doAssert d.title == "Page One"

      # navigation history
      d.findElement(By.id("go")).click()
      doAssert d.title == "Page Two"
      d.back()
      doAssert d.title == "Page One"
      d.forward()
      doAssert d.title == "Page Two"
      d.back()
      echo "  ok: back / forward history"

      # cookies
      d.deleteAllCookies()
      d.addCookie(%*{"name": "flavor", "value": "mint"})
      doAssert d.cookie("flavor")["value"].getStr == "mint"
      d.deleteCookie("flavor")
      echo "  ok: cookies"

      # windows
      doAssert d.windowHandles.len >= 1
      doAssert d.currentWindowHandle in d.windowHandles
      discard d.setWindowRect(%*{"width": 900, "height": 650})
      doAssert d.getWindowRect()["width"].getInt == 900
      echo "  ok: windows"

      # execute_script shapes
      doAssert d.executeScript("return 6*7;").getInt == 42
      doAssert d.executeScript("return 'hi';").getStr == "hi"
      doAssert d.executeScript("return arguments[0]+arguments[1];", %*[40, 2]).getInt == 42
      echo "  ok: execute_script"

      # execute_async_script + script timeout setter
      d.setScriptTimeout(5000)
      doAssert d.executeAsyncScript(
        "const cb = arguments[arguments.length - 1]; cb(6*7);").getInt == 42
      echo "  ok: execute_async_script + set_script_timeout"

      # W3C actions: pointer click on the button
      let r = d.findElement(By.id("btn")).rect
      let cx = (r["x"].getFloat + r["width"].getFloat / 2).int
      let cy = (r["y"].getFloat + r["height"].getFloat / 2).int
      d.performActions(%*[{
        "type": "pointer", "id": "mouse",
        "parameters": {"pointerType": "mouse"},
        "actions": [
          {"type": "pointerMove", "duration": 0, "x": cx, "y": cy},
          {"type": "pointerDown", "button": 0},
          {"type": "pointerUp", "button": 0}
        ]
      }])
      doAssert d.findElement(By.id("hdr")).text == "clicked"
      d.clearActions()
      echo "  ok: W3C actions"

      # convenience tier: explicit waits + Select + Actions gesture, all against
      # real Chrome. waitForVisible blocks for a node that appears after a
      # setTimeout; Select drives the <select> by value/text/index and reads
      # back the state via isSelected; an Actions chain right-clicks a target and
      # types into the input through the key device.
      d.get(base & "/form")
      # Select by value / visible text / index, verified through isSelected.
      let sel = newSelect(d.findElement(By.id("country")))
      doAssert not sel.isMultiple
      sel.selectByValue("es")
      doAssert sel.firstSelectedOption.getAttribute("value").getStr == "es"
      sel.selectByVisibleText("France")
      doAssert sel.firstSelectedOption.text == "France"
      sel.selectByIndex(0)
      doAssert sel.firstSelectedOption.getAttribute("value").getStr == "us"
      echo "  ok: Select (byValue / byVisibleText / byIndex)"

      # Actions: right-click the ctx div (records "ctx"), and type into the input
      # via the key device (moveToElement to focus, then sendKeys).
      d.actions.contextClick(d.findElement(By.id("ctx"))).perform()
      doAssert d.findElement(By.id("ctx")).text == "ctx"
      d.actions.click(d.findElement(By.id("txt"))).sendKeys("hi" & Keys.enter).perform()
      doAssert d.findElement(By.id("txt")).getAttribute("value").getStr.contains("hi")
      echo "  ok: Actions (contextClick + click + sendKeys via key device)"

      # Explicit wait: the reveal button appends #late after ~400ms; waitForVisible
      # must block until it's present + displayed, then return it.
      d.findElement(By.id("reveal")).click()
      let late = d.waitForVisible(By.id("late"), 4000)
      doAssert late.text == "here"
      # waitUntil with a custom predicate re-reads the live DOM each poll.
      doAssert d.waitUntil(2000, proc (d: WebDriver): bool =
        d.findElement(By.id("late")).text == "here")
      echo "  ok: waits (waitForVisible + waitUntil)"

      # screenshot -> PNG
      let raw = decode(d.screenshotBase64())
      doAssert raw[1..3] == "PNG"
      echo "  ok: screenshot (" & $raw.len & " bytes PNG)"

      # negative path
      var nse = false
      try:
        discard d.findElement(By.id("does-not-exist"))
      except WebDriverError as e:
        nse = e.kind == ekNoSuchElement
      doAssert nse
      echo "  ok: no such element error"

      # WebDriver-BiDi: subscribe to log.entryAdded, trigger a console.log via
      # a data: URL page, drain the event, and round-trip a session.status
      # command — all over the negotiated webSocketUrl on this same session.
      doAssert d.bidiAvailable
      let dataUrl = "data:text/html," &
        "<!doctype html><title>BiDi</title><h1>bidi page</h1>"
      d.get(dataUrl)
      let ack = d.bidi.subscribe(LogEntryAdded)
      doAssert ack["type"].getStr == "success"
      discard d.executeScript("console.log('bidi-hello');")
      let ev = d.bidi.nextEvent(LogEntryAdded, 8000)
      doAssert ev != nil
      doAssert ev["method"].getStr == LogEntryAdded
      doAssert ($ev).contains("bidi-hello")
      let status = d.bidi.command("session.status")
      doAssert status["type"].getStr == "success"
      echo "  ok: BiDi (log.entryAdded event + session.status command)"

      # Typed BiDi convenience: getTree/topContext, script.evaluate (unwrapped
      # value), and a promise-awaiting evaluate — all against real Chrome.
      let top = d.bidi.topContext()
      doAssert top.len > 0
      doAssert d.bidi.evaluateValue("6*7").getInt == 42
      doAssert d.bidi.evaluateValue("Promise.resolve(41+1)").getInt == 42
      echo "  ok: BiDi typed (topContext + evaluateValue sync/promise)"

      # BiDi network interception: add an intercept at the beforeRequestSent
      # phase, trigger a matching fetch, drain the paused-request event, pull its
      # request id, and let it continue — all over real Chrome.
      discard d.bidi.subscribe(BeforeRequestSent)
      let ic = d.bidi.addIntercept(phases = "beforeRequestSent",
                                   urlPattern = "https://example.com/blocked")
      doAssert ic.len > 0
      discard d.executeScript("fetch('https://example.com/blocked').catch(()=>{});")
      let netEv = d.bidi.nextEvent(BeforeRequestSent, 8000)
      doAssert netEv != nil
      let rid = eventRequestId(netEv)
      doAssert rid.len > 0
      doAssert d.bidi.continueRequest(rid)["type"].getStr == "success"
      doAssert d.bidi.removeIntercept(ic)["type"].getStr == "success"
      echo "  ok: BiDi network interception (addIntercept + continueRequest)"

      # BiDi request mocking: intercept a fetch and fulfill it with a mock
      # response (network.provideResponse) — the request never hits the network,
      # and the page reads back our MOCKED-BODY. The engine auto-adds
      # Access-Control-Allow-Origin:* so the cross-origin fetch can read it.
      let ic2 = d.bidi.addIntercept(phases = "beforeRequestSent",
                                    urlPattern = "https://example.com/api")
      doAssert ic2.len > 0
      discard d.executeScript(
        "window.__mock='';" &
        "fetch('https://example.com/api')" &
        ".then(function(r){return r.text();})" &
        ".then(function(t){window.__mock=t;})" &
        ".catch(function(e){window.__mock='ERR:'+e;});")
      let ev2 = d.bidi.nextEvent(BeforeRequestSent, 8000)
      doAssert ev2 != nil
      let rid2 = eventRequestId(ev2)
      doAssert rid2.len > 0
      let resp = d.bidi.provideResponse(rid2, 200, "text/plain", "MOCKED-BODY")
      doAssert resp["type"].getStr == "success"
      var mocked = ""
      for _ in 0 ..< 25:
        mocked = d.executeScript("return window.__mock;").getStr
        if mocked.contains("MOCKED-BODY"): break
        sleep(200)
      doAssert mocked.contains("MOCKED-BODY")
      doAssert d.bidi.removeIntercept(ic2)["type"].getStr == "success"
      echo "  ok: BiDi request mocking (provideResponse -> MOCKED-BODY)"

      # network.setCacheBehavior — bypass (disable the HTTP cache so every
      # request hits the network / an intercept) then restore the default.
      doAssert d.bidi.setCacheBehavior("bypass")["type"].getStr == "success"
      doAssert d.bidi.setCacheBehavior("default")["type"].getStr == "success"
      echo "  ok: BiDi setCacheBehavior (bypass -> default)"

      echo "PASS: Nim live surface test green"
    finally:
      d.quit()
  finally:
    cd.terminate()
    discard cd.waitForExit()
    serverStop = true
    # nudge the server out of accept()
    try:
      let s = newSocket()
      s.connect("127.0.0.1", webPort)
      s.close()
    except CatchableError:
      discard
    joinThread(srvThread)

proc driverOrchestration() =
  ## Driver orchestration over the engine: resolve + spawn a chromedriver
  ## in-binding (no chromedriver on PATH, no Grid), drive a data: page through
  ## the self-launched driver, and tear the process down — the ensureDriver ->
  ## url -> chrome() -> stop flow the C-ABI exposes for FFI bindings.

  # Resolve only — self-skip if the engine can't produce a driver here (offline +
  # empty cache). NOT a failure; same self-skip the reference client uses.
  let path = resolveDriver("chrome")
  if path.len == 0:
    echo "SKIPPED: engine cannot resolve a chromedriver (offline, no cache)"
    return
  doAssert fileExists(path), "resolveDriver returned a non-file: " & path
  echo "  ok: resolveDriver -> " & path

  # ensureDriver spawns it; the handle exposes url + pid, independent of any
  # W3C session.
  let p = ensureDriver("chrome")
  doAssert p != nil, "ensureDriver returned nil"
  doAssert p.url.startsWith("http"), "driver url=" & p.url
  doAssert p.pid > 0, "driver pid=" & $p.pid
  echo "  ok: ensureDriver -> pid " & $p.pid & " at " & p.url
  p.stop()
  doAssert p.pid == 0, "stop should clear the handle"
  echo "  ok: stop terminated the process"

  # localChrome ties it together: spawn its own driver, run a session against a
  # data: page, and stop the driver on quit — the whole point of the ABI. The
  # driver is spawned by the engine, so this needs NO chromedriver on PATH.
  var options = %*{
    "goog:chromeOptions": {
      "args": ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
    }
  }
  let chromeBin = getEnv("SEL_CHROME_BINARY")
  if chromeBin.len != 0:
    options["goog:chromeOptions"]["binary"] = %chromeBin
  let lc = localChrome(options = options)
  try:
    doAssert lc.sessionId.len > 0, "no session id from localChrome"
    lc.get("data:text/html," &
      "<!doctype html><title>Aether Selenium</title><h1 id='hdr'>Hello</h1>")
    doAssert lc.title == "Aether Selenium", "title=" & lc.title
    doAssert lc.findElement(By.id("hdr")).text == "Hello"
    echo "PASS: Nim live driver-orchestration test green (self-spawned driver)"
  finally:
    lc.quit()

main()
driverOrchestration()
