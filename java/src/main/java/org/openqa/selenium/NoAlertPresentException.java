package org.openqa.selenium;

/**
 * Thrown when switching to an alert that is not present. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.NoAlertPresentException}.
 */
public class NoAlertPresentException extends NotFoundException {

  public NoAlertPresentException() {
    this("No alert was present");
  }

  public NoAlertPresentException(String message) {
    super(message);
  }

  public NoAlertPresentException(Throwable cause) {
    super(cause);
  }

  public NoAlertPresentException(String message, Throwable cause) {
    super(message, cause);
  }
}
