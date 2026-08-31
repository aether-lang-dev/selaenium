## Live end-to-end + surface test (Nim): a real headless Chrome session driven
## through the pure-Aether engine via the linked .so, with a std/net content
## server (on its own thread — Nim threads are OS threads, so a blocking FFI
## call on the main thread doesn't stall the server) for a real cookie/nav
## origin. Skips if chromedriver is absent.
import std/[json, os, osproc, net, strutils, base64, times]
import selenium_core

const
  pageOne = "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>" &
    "<a id=\"go\" href=\"/two\">to two</a>" &
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
  pageTwo = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>"

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
      let body = if req.contains("/two"): pageTwo else: pageOne
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
      doAssert d.findElement(ById, "hdr").text == "One"
      doAssert d.findElement(ByCss, "#go").tagName.toLowerAscii == "a"
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
      doAssert d.findElement(ById, "hdr").isDisplayed
      doAssert not d.findElement(ById, "gone").isDisplayed
      doAssert d.findElement(ById, "lnk").getAttribute("href").getStr.contains("example.com/x")
      let below = d.findRelative("button", %*{"kind": "below", "sel": "#hdr"})
      doAssert below.len >= 1
      echo "  ok: atoms (isDisplayed / getAttribute / findRelative)"

      d.get(base & "/one")
      doAssert d.title == "Page One"

      # navigation history
      d.findElement(ById, "go").click()
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

      # W3C actions: pointer click on the button
      let r = d.findElement(ById, "btn").rect
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
      doAssert d.findElement(ById, "hdr").text == "clicked"
      d.clearActions()
      echo "  ok: W3C actions"

      # screenshot -> PNG
      let raw = decode(d.screenshotBase64())
      doAssert raw[1..3] == "PNG"
      echo "  ok: screenshot (" & $raw.len & " bytes PNG)"

      # negative path
      var nse = false
      try:
        discard d.findElement(ById, "does-not-exist")
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

main()
