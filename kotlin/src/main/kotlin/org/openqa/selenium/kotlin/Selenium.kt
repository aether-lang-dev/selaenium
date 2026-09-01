@file:JvmName("SeleniumCore")

package org.seleniumhq.aether.kotlin

import org.seleniumhq.aether.By
import org.seleniumhq.aether.WebDriver
import org.seleniumhq.aether.WebElement

/**
 * Idiomatic Kotlin over the Java binding.
 *
 * There is **no second FFI here**. The one JVM binding to the shared Aether
 * WebDriver engine is `java/src/org/seleniumhq/aether` (Panama FFM); everything
 * in this file is ordinary Kotlin/Java interop on top of those classes — exactly
 * as one Java jar backs the whole JVM family (Kotlin/Scala/Clojure/Groovy). A
 * Kotlin-specific FFI would be a second copy of the marshalling rules to keep in
 * sync with `core/embed.ae`, and the first thing to drift.
 *
 * What Kotlin adds:
 *  * a `chrome { }` / `headlessChrome { }` builder that takes a capabilities
 *    lambda and hands the driver to a `use`-style block, quitting at the end;
 *  * `driver.find(By.CSS_SELECTOR, "...")` and element extensions;
 *  * `By` re-exported as Kotlin constants.
 *
 * ```kotlin
 * headlessChrome("http://127.0.0.1:9515") { d ->
 *     d.get("https://example.com")
 *     println(d.title)
 *     d.find(By.CSS_SELECTOR, "a").click()
 * }
 * ```
 */

/** `By` strategies, re-exported for a Kotlin call site. */
object By {
    const val ID = org.seleniumhq.aether.By.ID
    const val NAME = org.seleniumhq.aether.By.NAME
    const val CSS_SELECTOR = org.seleniumhq.aether.By.CSS_SELECTOR
    const val CLASS_NAME = org.seleniumhq.aether.By.CLASS_NAME
    const val TAG_NAME = org.seleniumhq.aether.By.TAG_NAME
    const val LINK_TEXT = org.seleniumhq.aether.By.LINK_TEXT
    const val PARTIAL_LINK_TEXT = org.seleniumhq.aether.By.PARTIAL_LINK_TEXT
    const val XPATH = org.seleniumhq.aether.By.XPATH
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
    val driver = WebDriver.chrome(commandExecutor, options)
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

/** Terser element lookup. */
fun WebDriver.find(by: String, value: String): WebElement = findElement(by, value)

fun WebDriver.findAll(by: String, value: String): List<WebElement> = findElements(by, value)

/** `driver.script("return 6*7;")` — thin alias for executeScript. */
fun WebDriver.script(js: String, vararg args: Any?): Any? = executeScript(js, *args)
