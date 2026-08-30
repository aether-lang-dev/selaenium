package org.seleniumhq.aether.scala

import org.seleniumhq.aether.{By, WebDriver, WebElement}

/**
 * Idiomatic Scala over the Java binding.
 *
 * There is NO second FFI here. The one JVM binding to the shared Aether
 * WebDriver engine is `java/src/main/java/org/seleniumhq/aether` (Panama FFM);
 * everything here is ordinary Scala/Java interop on top of those classes —
 * exactly as one Java jar backs the whole JVM family (Kotlin/Scala/Clojure/
 * Groovy). A Scala-specific FFI would be a second copy of the marshalling rules
 * to keep in sync with selenium_core/embed.ae, and the first thing to drift.
 *
 * What Scala adds:
 *  - a `headlessChrome(url) { d => … }` loan-pattern that quits at the end;
 *  - `d.find(By.Css, "…")` with a typed `By` enum re-export;
 *  - `WebElement` extension methods.
 *
 * {{{
 * import org.seleniumhq.aether.scala.SeleniumCore.*
 * headlessChrome("http://127.0.0.1:9515") { d =>
 *   d.get("https://example.com")
 *   println(d.title())
 *   d.find(By.CSS_SELECTOR, "a").click()
 * }
 * }}}
 */
object SeleniumCore:

  /** By strategies, re-exported (the same string constants the engine expects). */
  object By:
    val ID: String = org.seleniumhq.aether.By.ID
    val NAME: String = org.seleniumhq.aether.By.NAME
    val CSS_SELECTOR: String = org.seleniumhq.aether.By.CSS_SELECTOR
    val CLASS_NAME: String = org.seleniumhq.aether.By.CLASS_NAME
    val TAG_NAME: String = org.seleniumhq.aether.By.TAG_NAME

  /** Pure engine helpers (no session) — shared with every binding. */
  def route(command: String): String = WebDriver.route(command)
  def errorCode(w3cError: String): Int = WebDriver.errorCode(w3cError)
  def locator(by: String, value: String): String = WebDriver.locator(by, value)

  /** Loan-pattern: open a headless Chrome session, run `body`, always quit. */
  def headlessChrome[A](commandExecutor: String)(body: WebDriver => A): A =
    val d = WebDriver.headlessChrome(commandExecutor)
    try body(d)
    finally d.quit()

  /** Scala-friendly find on the Java WebDriver. */
  extension (d: WebDriver)
    def find(by: String, value: String): WebElement = d.findElement(by, value)
