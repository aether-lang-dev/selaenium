package org.openqa.selenium;

/**
 * A target (element, frame, window, alert, …) could not be located. Mirrors
 * Selenium 4.x's {@code org.openqa.selenium.NotFoundException}; the base for
 * {@link NoAlertPresentException}.
 */
public class NotFoundException extends WebDriverException {

  public NotFoundException() {}

  public NotFoundException(String message) {
    super(message);
  }

  public NotFoundException(String message, Throwable cause) {
    super(message, cause);
  }

  public NotFoundException(Throwable cause) {
    super(cause);
  }
}
