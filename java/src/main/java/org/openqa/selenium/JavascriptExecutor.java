package org.openqa.selenium;

/**
 * A driver that can run JavaScript in the current browsing context. Mirrors
 * Selenium 4.x's {@code org.openqa.selenium.JavascriptExecutor}.
 */
public interface JavascriptExecutor {

    Object executeScript(String script, Object... args);

    Object executeAsyncScript(String script, Object... args);
}
