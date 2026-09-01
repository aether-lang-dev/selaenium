package org.openqa.selenium;

import java.util.List;
import java.util.Map;

/**
 * A WebDriver session. Mirrors Selenium 4.x's {@code org.openqa.selenium.WebDriver}
 * surface (getter grammar: {@code getTitle()}, {@code getCurrentUrl()}, one-arg
 * {@code findElement(By)}). The concrete implementation is {@link RemoteWebDriver}
 * (and its subclass {@link ChromeDriver}). Extends {@link JavascriptExecutor} so
 * every session can run scripts.
 */
public interface WebDriver extends JavascriptExecutor {

    // ---- navigation ----
    void get(String url);

    String getCurrentUrl();

    String getTitle();

    String getPageSource();

    void back();

    void forward();

    void refresh();

    // ---- elements ----
    WebElement findElement(By by);

    List<WebElement> findElements(By by);

    /**
     * Relative locators: elements matching {@code baseCss} filtered by spatial
     * relation to anchors (each filter a map with {@code "kind"} and {@code "sel"}),
     * nearest first.
     */
    List<WebElement> findRelative(String baseCss, List<Map<String, Object>> filters);

    // ---- windows ----
    List<String> windowHandles();

    String currentWindowHandle();

    void switchToWindow(String handle);

    Map<String, Object> maximizeWindow();

    Map<String, Object> minimizeWindow();

    Map<String, Object> fullscreenWindow();

    Map<String, Object> setWindowRect(Map<String, Object> rect);

    Map<String, Object> getWindowRect();

    // ---- cookies ----
    void addCookie(Map<String, Object> cookie);

    List<Map<String, Object>> getCookies();

    Map<String, Object> getCookie(String name);

    void deleteCookie(String name);

    void deleteAllCookies();

    // ---- actions ----
    void performActions(List<Object> actions);

    void clearActions();

    // ---- alerts ----
    void acceptAlert();

    void dismissAlert();

    String alertText();

    void sendAlertText(String text);

    // ---- timeouts ----
    void setTimeouts(Map<String, Object> timeouts);

    void setPageLoadTimeout(long ms);

    void setScriptTimeout(long ms);

    void implicitlyWait(long ms);

    // ---- screenshots ----
    String screenshotBase64();

    // ---- WebDriver-BiDi ----
    BiDi bidi();

    boolean bidiAvailable();

    // ---- lifecycle ----
    String sessionId();

    void quit();
}
