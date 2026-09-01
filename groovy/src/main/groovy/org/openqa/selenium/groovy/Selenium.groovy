package org.openqa.selenium.groovy

import org.openqa.selenium.ChromeDriver
import org.openqa.selenium.RemoteWebDriver

/**
 * Idiomatic Groovy over the Java binding.
 *
 * There is NO second FFI here. The one JVM binding to the shared Aether engine
 * is the Java FFM binding (org.openqa.selenium.*); this is ordinary
 * Groovy/Java interop over those classes — exactly as one Java jar backs the
 * whole JVM family (Kotlin/Scala/Clojure/Groovy). A Groovy-specific FFI would be
 * a second copy of the marshalling rules to keep in sync with the engine.
 *
 * What Groovy adds: a `withChrome`/`withHeadlessChrome`/`withLocalChrome`
 * closure form that quits the session on exit. Everything else is just calling
 * the Java methods, which Groovy already makes terse (driver.getTitle(),
 * driver.findElement(By.id("x")), Groovy maps/lists coerce to
 * java.util.Map/List for params).
 *
 *   Selenium.withHeadlessChrome("http://127.0.0.1:9515") { d ->
 *       d.get("https://example.com")
 *       println d.getTitle()
 *       d.findElement(By.cssSelector("a")).click()
 *   }
 */
class Selenium {

    /** Start a Chrome session, run the closure with the driver, quit on exit. */
    static <R> R withChrome(String commandExecutor, Map options = [:], Closure<R> body) {
        def driver = RemoteWebDriver.chrome(commandExecutor, options)
        try {
            return body(driver)
        } finally {
            driver.quit()
        }
    }

    /**
     * As withChrome, with the standard headless launch args. Honors
     * SEL_CHROME_BINARY when set (a box with no system Chrome but a cached
     * Chrome-for-Testing), pointing goog:chromeOptions.binary at it.
     */
    static <R> R withHeadlessChrome(String commandExecutor, Closure<R> body) {
        def chromeOpts = [
            args: ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
        ]
        def chromeBin = System.getenv('SEL_CHROME_BINARY')
        if (chromeBin) {
            chromeOpts.binary = chromeBin
        }
        withChrome(commandExecutor, ['goog:chromeOptions': chromeOpts], body)
    }

    /**
     * Start a local Chrome session that spawns its own chromedriver via the
     * engine (no driver on PATH, no Grid) — the Selenium 4.x `ChromeDriver()`
     * entry point — run the closure, quit on exit.
     */
    static <R> R withLocalChrome(Map options = [:], Closure<R> body) {
        def driver = new ChromeDriver(options)
        try {
            return body(driver)
        } finally {
            driver.quit()
        }
    }
}
