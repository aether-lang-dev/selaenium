@file:JvmName("Selenium")

package org.openqa.selenium.kotlin

import org.openqa.selenium.ChromeDriver
import org.openqa.selenium.RemoteWebDriver
import org.openqa.selenium.WebDriver
import org.openqa.selenium.WebElement

/**
 * Idiomatic Kotlin over the Java binding.
 *
 * There is **no second FFI here**. The one JVM binding to the shared Aether
 * WebDriver engine is `java/src/org/openqa/selenium` (Panama FFM); everything
 * in this file is ordinary Kotlin/Java interop on top of those classes — exactly
 * as one Java jar backs the whole JVM family (Kotlin/Scala/Clojure/Groovy). A
 * Kotlin-specific FFI would be a second copy of the marshalling rules to keep in
 * sync with `selenium_core/embed.ae`, and the first thing to drift.
 *
 * What Kotlin adds:
 *  * a `chrome { }` / `headlessChrome { }` builder that takes a capabilities
 *    lambda and hands the driver to a `use`-style block, quitting at the end;
 *  * `driver.find(By.cssSelector("..."))` and element extensions;
 *  * `By` re-exported as Kotlin factory functions delegating to the Java
 *    factory (or just use `org.openqa.selenium.By` directly).
 *
 * ```kotlin
 * headlessChrome("http://127.0.0.1:9515") { d ->
 *     d.get("https://example.com")
 *     println(d.getTitle())
 *     d.find(By.cssSelector("a")).click()
 * }
 * ```
 */

/**
 * `By` locators, re-exported for a Kotlin call site. Selenium 4.x's `By` is a
 * factory returning a locator instance; these delegate to the Java factory
 * methods. (Callers may equally use `org.openqa.selenium.By` directly.)
 */
object By {
    fun id(value: String): org.openqa.selenium.By = org.openqa.selenium.By.id(value)

    fun name(value: String): org.openqa.selenium.By = org.openqa.selenium.By.name(value)

    fun className(value: String): org.openqa.selenium.By = org.openqa.selenium.By.className(value)

    fun cssSelector(value: String): org.openqa.selenium.By = org.openqa.selenium.By.cssSelector(value)

    fun tagName(value: String): org.openqa.selenium.By = org.openqa.selenium.By.tagName(value)

    fun linkText(value: String): org.openqa.selenium.By = org.openqa.selenium.By.linkText(value)

    fun partialLinkText(value: String): org.openqa.selenium.By = org.openqa.selenium.By.partialLinkText(value)

    fun xpath(value: String): org.openqa.selenium.By = org.openqa.selenium.By.xpath(value)
}

/**
 * Start a Chrome session, run [block] with the driver, then quit (even on
 * error) — the `use`-shaped lifecycle Kotlin readers expect. `options` is a
 * capabilities map merged under browserName: chrome.
 */
inline fun <R> chrome(
    commandExecutor: String,
    options: Map<String, Any?> = emptyMap(),
    block: (WebDriver) -> R,
): R {
    val driver = RemoteWebDriver.chrome(commandExecutor, options)
    try {
        return block(driver)
    } finally {
        driver.quit()
    }
}

/** As [chrome], with the standard headless launch args baked in. */
inline fun <R> headlessChrome(commandExecutor: String, block: (WebDriver) -> R): R =
    chrome(
        commandExecutor,
        mapOf(
            "goog:chromeOptions" to mapOf(
                "args" to listOf("--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"),
            ),
        ),
        block,
    )

/**
 * Start a *local* Chrome session that spawns its own chromedriver via the
 * engine (no driver on PATH, no Grid), run [block], then quit — the
 * Selenium 4.x `ChromeDriver()` entry point in `use`-shape.
 */
inline fun <R> localChrome(
    options: Map<String, Any?> = emptyMap(),
    block: (WebDriver) -> R,
): R {
    val driver = ChromeDriver(options)
    try {
        return block(driver)
    } finally {
        driver.quit()
    }
}

/** Terser element lookup. */
fun WebDriver.find(by: org.openqa.selenium.By): WebElement = findElement(by)

fun WebDriver.findAll(by: org.openqa.selenium.By): List<WebElement> = findElements(by)

/** `driver.script("return 6*7;")` — thin alias for executeScript. */
fun WebDriver.script(js: String, vararg args: Any?): Any? = executeScript(js, *args)
