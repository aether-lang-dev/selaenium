package org.openqa.selenium.scala

import org.openqa.selenium.{By, RemoteWebDriver, WebDriverException}

/**
 * No-browser FFI test: proves the Scala binding drives the ONE Java FFM binding
 * (over JVM interop — no second FFI) and that the shared engine helpers marshal
 * correctly. Needs only the .so (SELENIUM_CORE_LIB / bundled native/); run with
 * --enable-native-access (aeb's jvm_flag). A plain `object … main` conformance
 * runner (scalac_test + main_class), no test-framework jar.
 */
object FfiTest:
  private var failures = 0

  private def check(cond: Boolean, label: String): Unit =
    if cond then println(s"  ok: $label")
    else { println(s"FAIL: $label"); failures += 1 }

  def main(args: Array[String]): Unit =
    check(RemoteWebDriver.route("get") == "POST /session/:sessionId/url", "route get")
    check(RemoteWebDriver.route("nope").isEmpty, "route unknown")
    check(RemoteWebDriver.errorCode("no such element") == 17, "errorCode no such element")
    check(RemoteWebDriver.errorCode("") == 0, "errorCode success")
    check(
      RemoteWebDriver.locator("css selector", "div.foo") ==
        "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
      "locator css"
    )
    check(RemoteWebDriver.locator("id", "main").contains("*[id="), "locator id rewrite")

    var threw = false
    try RemoteWebDriver.chrome("http://127.0.0.1:1", null)
    catch case e: WebDriverException => threw = e.code() == -1
    check(threw, "transport failure -> code -1")

    // By is now a factory: each strategy yields a locator instance.
    check(By.className("x").toString.contains("class name"), "By.className -> \"class name\"")

    if failures == 0 then println("PASS: Scala FFI tests green")
    else { println(s"FAILED: $failures Scala FFI test(s)"); System.exit(1) }
