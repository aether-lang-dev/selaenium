package org.openqa.selenium;

/**
 * The kind of top-level browsing context to open with
 * {@link WebDriver.TargetLocator#newWindow(WindowType)}. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.WindowType}.
 */
public enum WindowType {
  WINDOW("window"),
  TAB("tab"),
  ;

  private final String text;

  WindowType(String text) {
    this.text = text;
  }

  @Override
  public String toString() {
    return String.valueOf(text);
  }

  public static WindowType fromString(String text) {
    if (text != null) {
      for (WindowType b : WindowType.values()) {
        if (text.equalsIgnoreCase(b.text)) {
          return b;
        }
      }
    }
    return null;
  }
}
