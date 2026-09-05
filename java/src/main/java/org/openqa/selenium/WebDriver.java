package org.openqa.selenium;

import java.net.URL;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * A WebDriver session. Mirrors Selenium 4.x's {@code org.openqa.selenium.WebDriver}
 * surface: the getter grammar ({@code getTitle()}, {@code getCurrentUrl()}), the
 * nested {@link Navigation} / {@link TargetLocator} / {@link Options} / {@link Window}
 * / {@link Timeouts} facades, and the {@link #navigate()} / {@link #switchTo()} /
 * {@link #manage()} entry points. The concrete implementation is
 * {@link RemoteWebDriver} (and its subclass {@link ChromeDriver}).
 *
 * <p>Extends {@link SearchContext} (upstream) so a WebDriver is a find-element
 * context, and also {@link JavascriptExecutor} (a binding convenience kept from
 * the original flat surface) so every session can run scripts directly. The flat
 * methods ({@link #back()}, {@link #switchToWindow(String)}, {@link #acceptAlert()},
 * {@link #implicitlyWait(long)}, …) all remain available alongside the facades.
 */
public interface WebDriver extends SearchContext, JavascriptExecutor {

  // ---- navigation ----
  void get(String url);

  String getCurrentUrl();

  String getTitle();

  String getPageSource();

  void back();

  void forward();

  void refresh();

  // ---- elements ----
  @Override
  WebElement findElement(By by);

  @Override
  List<WebElement> findElements(By by);

  /**
   * Relative locators: elements matching {@code baseCss} filtered by spatial
   * relation to anchors (each filter a map with {@code "kind"} and {@code "sel"}),
   * nearest first.
   */
  List<WebElement> findRelative(String baseCss, List<Map<String, Object>> filters);

  // ---- windows (flat) ----
  List<String> windowHandles();

  String currentWindowHandle();

  void switchToWindow(String handle);

  Map<String, Object> maximizeWindow();

  Map<String, Object> minimizeWindow();

  Map<String, Object> fullscreenWindow();

  Map<String, Object> setWindowRect(Map<String, Object> rect);

  Map<String, Object> getWindowRect();

  // ---- windows (upstream facade forms) ----

  /** The set of open window handles (upstream {@code getWindowHandles()}). */
  Set<String> getWindowHandles();

  /** The current window's handle (upstream {@code getWindowHandle()}). */
  String getWindowHandle();

  // ---- cookies (flat) ----
  void addCookie(Map<String, Object> cookie);

  List<Map<String, Object>> getCookies();

  Map<String, Object> getCookie(String name);

  void deleteCookie(String name);

  void deleteAllCookies();

  // ---- actions ----
  void performActions(List<Object> actions);

  void clearActions();

  // ---- alerts (flat) ----
  void acceptAlert();

  void dismissAlert();

  String alertText();

  void sendAlertText(String text);

  // ---- timeouts (flat) ----
  void setTimeouts(Map<String, Object> timeouts);

  void setPageLoadTimeout(long ms);

  void setScriptTimeout(long ms);

  void implicitlyWait(long ms);

  // ---- screenshots (flat) ----
  String screenshotBase64();

  // ---- upstream facades ----

  /** Access the browser's history and navigate to a URL (upstream). */
  Navigation navigate();

  /** Switch focus to a different frame or window (upstream). */
  TargetLocator switchTo();

  /** Manage cookies, timeouts and the window (upstream). */
  Options manage();

  // ---- WebDriver-BiDi ----
  BiDi bidi();

  boolean bidiAvailable();

  // ---- lifecycle ----
  String sessionId();

  /** Close the current window (upstream; distinct from {@link #quit()}). */
  void close();

  void quit();

  // ---- nested facade interfaces (upstream shapes) ----

  /** Browser-history navigation. */
  interface Navigation {
    void back();

    void forward();

    void to(String url);

    void to(URL url);

    void refresh();
  }

  /** Select a frame or window to send future commands to. */
  interface TargetLocator {
    WebDriver frame(int index);

    WebDriver frame(String nameOrId);

    WebDriver frame(WebElement frameElement);

    WebDriver parentFrame();

    WebDriver window(String nameOrHandle);

    WebDriver newWindow(WindowType typeHint);

    WebDriver defaultContent();

    WebElement activeElement();

    Alert alert();
  }

  /** Things you would do in a browser menu (cookies, timeouts, window). */
  interface Options {
    void addCookie(Cookie cookie);

    void deleteCookieNamed(String name);

    void deleteCookie(Cookie cookie);

    void deleteAllCookies();

    Set<Cookie> getCookies();

    Cookie getCookieNamed(String name);

    Timeouts timeouts();

    Window window();
  }

  /** Timeout configuration. */
  interface Timeouts {
    Timeouts implicitlyWait(Duration duration);

    Duration getImplicitWaitTimeout();

    Timeouts scriptTimeout(Duration duration);

    Duration getScriptTimeout();

    Timeouts pageLoadTimeout(Duration duration);

    Duration getPageLoadTimeout();
  }

  /** The current window's geometry and state. */
  interface Window {
    Dimension getSize();

    void setSize(Dimension targetSize);

    Point getPosition();

    void setPosition(Point targetPosition);

    void maximize();

    void minimize();

    void fullscreen();
  }
}
