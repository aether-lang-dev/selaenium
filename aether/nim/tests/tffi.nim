## No-browser FFI test: proves the Nim binding links libselenium_core.so and
## marshals correctly, exercising the pure engine helpers and the transport
## error path. Built by nim/.tests.ae with the .so on the link path + rpath.
import std/[json, strutils, unittest]
import selenium_core

suite "ffi":
  test "route":
    check route("get") == "POST /session/:sessionId/url"
    check route("nope") == ""

  test "errorCode":
    check errorCode("no such element") == 17
    check errorCode("") == 0

  test "locator css":
    check parseJson(locator(ByCss, "div.foo")) ==
      %*{"using": "css selector", "value": "div.foo"}

  test "locator id rewrite":
    check locator(ById, "main").contains("*[id=")

  test "transport failure":
    var threw = false
    try:
      discard chrome("http://127.0.0.1:1")
    except WebDriverError as e:
      threw = e.code == -1
    check threw
