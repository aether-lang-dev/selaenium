package org.openqa.selenium;

import java.util.Map;

/**
 * A Chrome session that resolves, downloads-or-caches, and launches its OWN
 * chromedriver via the shared engine — no driver on PATH, no Grid. Mirrors
 * Selenium 4.x's {@code org.openqa.selenium.chrome.ChromeDriver}: the no-arg
 * constructor "just works", and the options constructor threads
 * {@code goog:chromeOptions}-style capabilities. The launched driver process is
 * stopped on {@link #quit()}.
 */
public class ChromeDriver extends RemoteWebDriver {

    /** Launch chromedriver and start a default Chrome session. */
    public ChromeDriver() {
        this(Map.of());
    }

    /**
     * Launch chromedriver and start a Chrome session with the given options
     * (e.g. {@code Map.of("goog:chromeOptions", Map.of("args", List.of("--headless=new")))}).
     * {@code browserName=chrome} is set automatically.
     */
    public ChromeDriver(Map<String, Object> options) {
        super(ensureChromeDriver(), withChrome(options), null, false);
    }

    /**
     * Launch chromedriver and start a Chrome session configured by an upstream
     * {@link org.openqa.selenium.chrome.ChromeOptions} (or any
     * {@link org.openqa.selenium.Capabilities}). Mirrors Selenium 4.x's
     * {@code new ChromeDriver(chromeOptions)}.
     */
    public ChromeDriver(org.openqa.selenium.Capabilities options) {
        super(ensureChromeDriver(), withChrome(new java.util.HashMap<>(options.asMap())), null, false);
    }

    private static DriverProcess ensureChromeDriver() {
        DriverProcess proc = ensureDriver("chrome");
        if (proc == null) {
            throw new WebDriverException("could not resolve/launch chromedriver", -1);
        }
        return proc;
    }

    private static Map<String, Object> withChrome(Map<String, Object> options) {
        java.util.Map<String, Object> caps = new java.util.HashMap<>();
        caps.put("browserName", "chrome");
        if (options != null) {
            caps.putAll(options);
        }
        return caps;
    }
}
