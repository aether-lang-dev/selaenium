## Third-party consumer example: imports the PACKAGED selenium Nim module
## (staged under target/nim-pkg, which carries the bundled native/ .so but has NO
## core/ sibling — so {.passL.}'s ../selenium_core/native can't resolve and only the
## package's own bundled native/ .so satisfies the link/rpath). Run with
## SELENIUM_CORE_LIB unset. Modes: ffi | live.
import std/[os, strutils]
import selenium

proc fail(msg: string) =
  stderr.writeLine("FAIL: " & msg)
  quit(1)

proc modeFfi() =
  if getEnv("SELENIUM_CORE_LIB").len > 0:
    fail("SELENIUM_CORE_LIB is set; consumer must run without it")
  if route("get") != "POST /session/:sessionId/url": fail("route mismatch")
  if errorCode("no such element") != 17: fail("errorCode mismatch")
  let byId = By.id("main")
  if not locator(byId.strategy, byId.value).contains("*[id="): fail("locator mismatch")
  try:
    discard chrome("http://127.0.0.1:1")
    fail("expected transport failure")
  except WebDriverError as e:
    if e.code != -1: fail("wrong transport code")
  echo "consumer(ffi): OK — bundled package linked its own .so via {.passL.} rpath"

proc urlencode(s: string): string =
  for ch in s:
    if ch in {'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'}:
      result.add ch
    else:
      result.add '%' & toHex(ord(ch), 2)

proc modeLive() =
  # The engine starts the driver, so the whole tree (browser included) ends on
  # stop() and when this process dies.
  let cd = ensureDriver("chrome")
  if cd == nil:
    echo "consumer(live): SKIPPED — the engine cannot resolve a chromedriver"
    return
  try:
    let d = headlessChrome(cd.url)
    try:
      let html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>"
      d.get("data:text/html;charset=utf-8," & urlencode(html))
      if d.title != "Installed": fail("title mismatch")
      if d.findElement(By.id("h")).text != "Hi": fail("text mismatch")
      echo "consumer(live): OK — bundled package drove real headless Chrome"
    finally:
      d.quit()
  finally:
    cd.stop()

when isMainModule:
  let mode = if paramCount() >= 1: paramStr(1) else: "ffi"
  case mode
  of "ffi": modeFfi()
  of "live": modeLive()
  else: fail("unknown mode: " & mode)
