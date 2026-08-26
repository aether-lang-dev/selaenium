## Third-party consumer example: imports the PACKAGED selenium_core Nim module
## (staged under target/nim-pkg, which carries the bundled native/ .so but has NO
## core/ sibling — so {.passL.}'s ../selenium_core/native can't resolve and only the
## package's own bundled native/ .so satisfies the link/rpath). Run with
## SELENIUM_CORE_LIB unset. Modes: ffi | live.
import std/[os, osproc, net, strutils, times]
import selenium_core

proc fail(msg: string) =
  stderr.writeLine("FAIL: " & msg)
  quit(1)

proc modeFfi() =
  if getEnv("SELENIUM_CORE_LIB").len > 0:
    fail("SELENIUM_CORE_LIB is set; consumer must run without it")
  if route("get") != "POST /session/:sessionId/url": fail("route mismatch")
  if errorCode("no such element") != 17: fail("errorCode mismatch")
  if not locator(ById, "main").contains("*[id="): fail("locator mismatch")
  try:
    discard chrome("http://127.0.0.1:1")
    fail("expected transport failure")
  except WebDriverError as e:
    if e.code != -1: fail("wrong transport code")
  echo "consumer(ffi): OK — bundled package linked its own .so via {.passL.} rpath"

proc which(cmd: string): string =
  for dir in getEnv("PATH").split(':'):
    let p = dir / cmd
    if fileExists(p): return p
  ""

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
    except CatchableError:
      sleep(100)
  false

proc urlencode(s: string): string =
  for ch in s:
    if ch in {'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'}:
      result.add ch
    else:
      result.add '%' & toHex(ord(ch), 2)

proc modeLive() =
  let driverBin = which("chromedriver")
  if driverBin.len == 0:
    echo "consumer(live): SKIPPED — chromedriver not on PATH"
    return
  let port = freePort()
  let cd = startProcess(driverBin, args = ["--port=" & $port.int], options = {poUsePath})
  try:
    if not waitUp(port, 10000):
      echo "consumer(live): SKIPPED — chromedriver did not come up"
      return
    let d = headlessChrome("http://127.0.0.1:" & $port.int)
    try:
      let html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>"
      d.get("data:text/html;charset=utf-8," & urlencode(html))
      if d.title != "Installed": fail("title mismatch")
      if d.findElement(ById, "h").text != "Hi": fail("text mismatch")
      echo "consumer(live): OK — bundled package drove real headless Chrome"
    finally:
      d.quit()
  finally:
    cd.terminate()
    discard cd.waitForExit()

when isMainModule:
  let mode = if paramCount() >= 1: paramStr(1) else: "ffi"
  case mode
  of "ffi": modeFfi()
  of "live": modeLive()
  else: fail("unknown mode: " & mode)
