package org.openqa.selenium.scala

import org.openqa.selenium.{By as JBy, ChromeDriver, RemoteWebDriver, WebDriver, WebElement}

/**
 * Idiomatic Scala over the Java binding.
 *
 * There is NO second FFI here. The one JVM binding to the shared Aether
 * WebDriver engine is `java/src/main/java/org/openqa/selenium` (Panama FFM);
 * everything here is ordinary Scala/Java interop on top of those classes —
 * exactly as one Java jar backs the whole JVM family (Kotlin/Scala/Clojure/
 * Groovy). A Scala-specific FFI would be a second copy of the marshalling rules
 * to keep in sync with selenium_core/embed.ae, and the first thing to drift.
 *
 * What Scala adds:
 *  - a `headlessChrome(url) { d => … }` loan-pattern that quits at the end;
 *  - `d.find(By.css("…"))` with a `By` factory re-export (all 8 strategies);
 *  - `WebElement` extension methods.
 *
 * {{{
 * import org.openqa.selenium.scala.Selenium.*
 * headlessChrome("http://127.0.0.1:9515") { d =>
 *   d.get("https://example.com")
 *   println(d.getTitle())
 *   d.find(By.cssSelector("a")).click()
 * }
 * }}}
 */
object Selenium:

  /**
   * By strategies, re-exported. Selenium 4.x's `By` is a FACTORY returning a
   * locator instance; these delegate to the Java factory methods (all 8
   * strategies — id/name/className/cssSelector/tagName/linkText/
   * partialLinkText/xpath). Callers may equally use `org.openqa.selenium.By`.
   */
  object By:
    def id(value: String): JBy = JBy.id(value)
    def name(value: String): JBy = JBy.name(value)
    def className(value: String): JBy = JBy.className(value)
    def cssSelector(value: String): JBy = JBy.cssSelector(value)
    def tagName(value: String): JBy = JBy.tagName(value)
    def linkText(value: String): JBy = JBy.linkText(value)
    def partialLinkText(value: String): JBy = JBy.partialLinkText(value)
    def xpath(value: String): JBy = JBy.xpath(value)

  /** Pure engine helpers (no session) — shared with every binding. */
  def route(command: String): String = RemoteWebDriver.route(command)
  def errorCode(w3cError: String): Int = RemoteWebDriver.errorCode(w3cError)
  def locator(by: String, value: String): String = RemoteWebDriver.locator(by, value)

  /** Loan-pattern: open a headless Chrome session, run `body`, always quit. */
  def headlessChrome[A](commandExecutor: String)(body: WebDriver => A): A =
    val d = RemoteWebDriver.headlessChrome(commandExecutor)
    try body(d)
    finally d.quit()

  /**
   * Loan-pattern: open a *local* Chrome session that spawns its own
   * chromedriver via the engine (no driver on PATH, no Grid) — the Selenium
   * 4.x `ChromeDriver()` entry point — run `body`, always quit.
   */
  def localChrome[A]()(body: WebDriver => A): A =
    val d = ChromeDriver()
    try body(d)
    finally d.quit()

  /** Scala-friendly find on the Java WebDriver. */
  extension (d: WebDriver)
    def find(by: JBy): WebElement = d.findElement(by)
