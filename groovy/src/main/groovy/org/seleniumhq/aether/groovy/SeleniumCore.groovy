package org.seleniumhq.aether.groovy

import org.seleniumhq.aether.WebDriver

/**
 * Idiomatic Groovy over the Java binding.
 *
 * There is NO second FFI here. The one JVM binding to the shared Aether engine
 * is the Java FFM binding (org.seleniumhq.aether.*); this is ordinary
 * Groovy/Java interop over those classes — exactly as one Java jar backs the
 * whole JVM family (Kotlin/Scala/Clojure/Groovy). A Groovy-specific FFI would be
 * a second copy of the marshalling rules to keep in sync with the engine.
 *
 * What Groovy adds: a `withChrome`/`withHeadlessChrome` closure form that quits
 * the session on exit. Everything else is just calling the Java methods, which
 * Groovy already makes terse (driver.title, driver.findElement(By.ID, "x"),
 * Groovy maps/lists coerce to java.util.Map/List for params).
 *
 *   SeleniumCore.withHeadlessChrome("http://127.0.0.1:9515") { d ->
 *       d.get("https://example.com")
 *       println d.title
 *       d.findElement(By.CSS_SELECTOR, "a").click()
 *   }
 */
class SeleniumCore {

    /** Start a Chrome session, run the closure with the driver, quit on exit. */
    static <R> R withChrome(String commandExecutor, Map options = [:], Closure<R> body) {
        def driver = WebDriver.chrome(commandExecutor, options)
        try {
            return body(driver)
        } finally {
            driver.quit()
        }
    }

    /** As withChrome, with the standard headless launch args. */
    static <R> R withHeadlessChrome(String commandExecutor, Closure<R> body) {
        withChrome(commandExecutor, [
            'goog:chromeOptions': [
                args: ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
            ]
        ], body)
    }
}
