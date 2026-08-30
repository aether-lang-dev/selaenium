package org.seleniumhq.aether.scala

import org.seleniumhq.aether.{By, WebDriver, WebDriverError}

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
    check(WebDriver.route("get") == "POST /session/:sessionId/url", "route get")
    check(WebDriver.route("nope").isEmpty, "route unknown")
    check(WebDriver.errorCode("no such element") == 17, "errorCode no such element")
    check(WebDriver.errorCode("") == 0, "errorCode success")
    check(
      WebDriver.locator(By.CSS_SELECTOR, "div.foo") ==
        "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
      "locator css"
    )
    check(WebDriver.locator(By.ID, "main").contains("*[id="), "locator id rewrite")

    var threw = false
    try WebDriver.chrome("http://127.0.0.1:1", null)
    catch case e: WebDriverError => threw = e.code() == -1
    check(threw, "transport failure -> code -1")

    if failures == 0 then println("PASS: Scala FFI tests green")
    else { println(s"FAILED: $failures Scala FFI test(s)"); System.exit(1) }
