## No-browser FFI test: proves the Nim binding links libselenium_core.so and
## marshals correctly, exercising the pure engine helpers and the transport
## error path. Built by nim/.tests.ae with the .so on the link path + rpath.
import std/[json, strutils, unittest]
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
