package org.openqa.selenium;

import java.util.List;
import java.util.Map;

/**
 * A located element. Mirrors Selenium 4.x's {@code org.openqa.selenium.WebElement}
 * surface. Extends {@link SearchContext} (element-scoped finders) and
 * {@link TakesScreenshot} (per-element screenshots). The concrete implementation
 * is {@link RemoteWebElement}.
 *
 * <p>{@link #sendKeys(CharSequence...)} is variadic so {@link Keys} constants and
 * plain strings both flow in ({@code el.sendKeys("hi", Keys.ENTER)}).
 */
public interface WebElement extends SearchContext, TakesScreenshot {

  String id();

  void click();

  /** Submit the enclosing {@code <form>} (upstream). */
  void submit();

  void sendKeys(CharSequence... keysToSend);

  void clear();

  String getText();

  String getTagName();

  boolean isDisplayed();

  /**
   * The classic getAttribute(name): property-or-attribute (boolean attrs, live
   * properties like value/checked), via the shared engine atom. Use
   * {@link #getDomAttribute(String)} for the raw W3C DOM attribute.
   */
  String getAttribute(String name);

  /** The literal DOM attribute (W3C getDomAttribute), no property fallback. */
  String getDomAttribute(String name);

  /** The DOM property of the element (upstream getDomProperty). */
  String getDomProperty(String name);

  /** The element's live JS property (returns the decoded value). */
  Object getProperty(String name);

  /** The computed value of a CSS property (upstream getCssValue). */
  String getCssValue(String propertyName);

  /** The computed ARIA role of the element (upstream). */
  String getAriaRole();

  /** The computed accessible name of the element (upstream). */
  String getAccessibleName();

  /** The element's shadow root, as a {@link SearchContext} (upstream). */
  SearchContext getShadowRoot();

  boolean isEnabled();

  boolean isSelected();

  /** The element's rectangle as the raw W3C map (binding original form). */
  Map<String, Object> rect();

  /** The element's rectangle as an upstream {@link Rectangle}. */
  Rectangle getRect();

  /** The element's {@link Point} location (upstream). */
  Point getLocation();

  /** The element's {@link Dimension} size (upstream). */
  Dimension getSize();

  @Override
  WebElement findElement(By by);

  @Override
  List<WebElement> findElements(By by);
}
