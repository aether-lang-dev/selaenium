package org.openqa.selenium;

/**
 * A JavaScript alert/confirm/prompt handle, reached via
 * {@code driver.switchTo().alert()}. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.Alert}.
 */
public interface Alert {

  /** Dismiss (cancel) the alert. */
  void dismiss();

  /** Accept (OK) the alert. */
  void accept();

  /** The alert's message text. */
  String getText();

  /** Type into a prompt's input field. */
  void sendKeys(String keysToSend);
}
