package org.openqa.selenium.scala

import org.openqa.selenium.{BidiEvent, By, RemoteWebDriver, WebDriverException}
import java.net.ServerSocket

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

    liveBidi()

    if failures == 0 then println("PASS: Scala FFI tests green")
    else { println(s"FAILED: $failures Scala FFI test(s)"); System.exit(1) }

  /** A live WebDriver-BiDi round-trip against real Chrome, over the shared Java
   *  Panama binding (Scala reaches the Java BiDi class via JVM interop — no
   *  Scala-side FFI). Skips if chromedriver is absent. */
  private def liveBidi(): Unit =
    val driverBin = which("chromedriver")
    if driverBin.isEmpty then
      println("  (live) SKIPPED: chromedriver not on PATH")
      return
    val port = freePort()
    val proc = new ProcessBuilder(driverBin.get, s"--port=$port")
      .redirectOutput(ProcessBuilder.Redirect.DISCARD)
      .redirectError(ProcessBuilder.Redirect.DISCARD)
      .start()
    try
      if !waitUp(port, 10000) then
        println("  (live) SKIPPED: chromedriver did not come up")
        return
      Selenium.headlessChrome(s"http://127.0.0.1:$port") { d =>
        check(d.bidiAvailable(), "bidi available (webSocketUrl negotiated)")
        val bidi = d.bidi()
        check(bidi.subscribe(BidiEvent.LOG_ENTRY_ADDED).get("type") == "success",
          "bidi.subscribe(log.entryAdded)")
        d.executeScript("console.log('bidi-hello');")
        val ev = bidi.nextEvent(BidiEvent.LOG_ENTRY_ADDED, 8000)
        check(ev != null && ev.toString.contains("bidi-hello"),
          "log.entryAdded event received async, carries the text")
        check(bidi.command("session.status", null, 10000).get("type") == "success",
          "bidi.command(session.status)")
        check(!bidi.topContext(10000).isEmpty, "bidi topContext")
        check(bidi.evaluateValue("6*7", 30000).asInstanceOf[Number].intValue == 42,
          "bidi.evaluate 6*7 -> 42")
      }
    finally proc.destroy()

  private def which(cmd: String): Option[String] =
    val path = Option(System.getenv("PATH")).getOrElse("")
    path.split(java.io.File.pathSeparator).iterator
      .map(d => new java.io.File(d, cmd))
      .find(f => f.canExecute && !f.isDirectory)
      .map(_.getAbsolutePath)

  private def freePort(): Int =
    val s = new ServerSocket(0, 0, java.net.InetAddress.getByName("127.0.0.1"))
    try s.getLocalPort finally s.close()

  private def waitUp(port: Int, timeoutMs: Long): Boolean =
    val deadline = System.currentTimeMillis() + timeoutMs
    var up = false
    while !up && System.currentTimeMillis() < deadline do
      try
        val sock = new java.net.Socket("127.0.0.1", port)
        sock.close(); up = true
      catch case _: Throwable => Thread.sleep(100)
    up
