## No-browser FFI test: proves the Nim binding links libselenium_core.so and
## marshals correctly, exercising the pure engine helpers and the transport
## error path. Built by nim/.tests.ae with the .so on the link path + rpath.
import std/[json, strutils, unicode, unittest]
import selenium

suite "ffi":
  test "route":
    check route("get") == "POST /session/:sessionId/url"
    check route("nope") == ""

  test "errorCode":
    check errorCode("no such element") == 17
    check errorCode("") == 0

  test "By factory carries strategy + value":
    let css = By.cssSelector("div.foo")
    check css.strategy == "css selector"
    check css.value == "div.foo"
    check By.className("x").strategy == "class name"

  test "locator css":
    let by = By.cssSelector("div.foo")
    check parseJson(locator(by.strategy, by.value)) ==
      %*{"using": "css selector", "value": "div.foo"}

  test "locator id rewrite":
    let by = By.id("main")
    check locator(by.strategy, by.value).contains("*[id=")

  test "transport failure":
    var threw = false
    try:
      discard chrome("http://127.0.0.1:1")
    except WebDriverError as e:
      threw = e.code == -1
    check threw

# ---- convenience tier (pure, no browser) -----------------------------------

suite "keys":
  test "code points are the W3C PUA values":
    check Keys.enter == ""
    check Keys.tab == ""
    check Keys.escape == ""
    check Keys.null == ""
    check Keys.f12 == ""       # last of the F-keys
    check Keys.meta == ""      # last defined PUA point
    check Keys.enter.runeAt(0).int == 0xE007

  test "aliases share a value":
    check Keys.arrowLeft == Keys.left
    check Keys.command == Keys.meta
    check BackSpace == Keys.backspace

suite "waits":
  test "waitUntil returns true when the predicate holds":
    let d = WebDriver()  # nil handle: the predicate never touches the engine
    var calls = 0
    check d.waitUntil(1000, proc (d: WebDriver): bool =
      inc calls
      calls >= 2)        # false first, true on the 2nd poll
    check calls == 2

  test "waitUntil raises ekTimeout when it never holds":
    let d = WebDriver()
    var threw = false
    try:
      discard d.waitUntil(0, proc (d: WebDriver): bool = false)
    except WebDriverError as e:
      threw = e.kind == ekTimeout
    check threw

suite "select":
  let opts = @[
    OptionData(value: "us", text: "United States"),
    OptionData(value: "es", text: "Spain"),
    OptionData(value: "fr", text: "France")]

  test "picks the right option by value":
    check firstMatchIndex(opts, sbValue, "es") == 1
    check firstMatchIndex(opts, sbValue, "nope") == -1

  test "picks the right option by visible text":
    check firstMatchIndex(opts, sbText, "France") == 2
    check firstMatchIndex(opts, sbText, "Nowhere") == -1

  test "picks the right option by index":
    check firstMatchIndex(opts, sbIndex, "0") == 0
    check firstMatchIndex(opts, sbIndex, "3") == -1   # out of range
    check firstMatchIndex(opts, sbIndex, "x") == -1   # not a number

suite "actions":
  test "builds the correct W3C pointer sequence for a click":
    let d = WebDriver()
    let el = WebElement(id: "E1")
    let built = d.actions.click(el).build()
    check built.kind == JArray
    check built.len == 1
    let dev = built[0]
    check dev["type"].getStr == "pointer"
    check dev["id"].getStr == "mouse"
    check dev["parameters"]["pointerType"].getStr == "mouse"
    let seq0 = dev["actions"]
    check seq0[0]["type"].getStr == "pointerMove"
    check seq0[0]["origin"]["element-6066-11e4-a52e-4f735466cecf"].getStr == "E1"
    check seq0[1]["type"].getStr == "pointerDown"
    check seq0[1]["button"].getInt == 0
    check seq0[2]["type"].getStr == "pointerUp"

  test "context click uses button 2":
    let d = WebDriver()
    let built = d.actions.contextClick(WebElement(id: "E2")).build()
    let seq0 = built[0]["actions"]
    check seq0[1]["button"].getInt == 2

  test "double click emits two down/up pairs":
    let d = WebDriver()
    let built = d.actions.doubleClick(WebElement(id: "E3")).build()
    let seq0 = built[0]["actions"]
    # move + (down,up) + (down,up) = 5 actions
    check seq0.len == 5

  test "key gestures build a keyboard device and pad the pointer":
    let d = WebDriver()
    let built = d.actions.keyDown(Keys.shift).sendKeys("a").keyUp(Keys.shift).build()
    # keyboard only -> single device
    check built.len == 1
    let dev = built[0]
    check dev["type"].getStr == "key"
    check dev["id"].getStr == "keyboard"
    let seq0 = dev["actions"]
    check seq0[0]["type"].getStr == "keyDown"
    check seq0[0]["value"].getStr == ""   # shift
    check seq0[1]["value"].getStr == "a"        # keyDown a
    check seq0[2]["value"].getStr == "a"        # keyUp a

  test "dragAndDrop emits move,down,move,up on the pointer device":
    let d = WebDriver()
    let built = d.actions.dragAndDrop(WebElement(id: "S"), WebElement(id: "T")).build()
    let seq0 = built[0]["actions"]
    check seq0[0]["type"].getStr == "pointerMove"
    check seq0[1]["type"].getStr == "pointerDown"
    check seq0[2]["type"].getStr == "pointerMove"
    check seq0[2]["origin"]["element-6066-11e4-a52e-4f735466cecf"].getStr == "T"
    check seq0[3]["type"].getStr == "pointerUp"

  test "empty chain builds nothing":
    let d = WebDriver()
    check d.actions.build().len == 0

suite "element predicates exist":
  test "isEnabled and isSelected are declared on WebElement":
    # A compile-time surface check: these procs must exist (the audit gap).
    check compiles(isEnabled(WebElement()))
    check compiles(isSelected(WebElement()))
    check compiles(isDisplayed(WebElement()))
