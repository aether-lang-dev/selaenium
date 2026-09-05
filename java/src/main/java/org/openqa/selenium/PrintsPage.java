package org.openqa.selenium;

import org.openqa.selenium.print.PrintOptions;

/**
 * A driver that can render the current page to PDF (the W3C print command).
 * Mirrors mainstream Selenium's {@code org.openqa.selenium.PrintsPage}.
 */
public interface PrintsPage {

  /** Render the current page to a {@link Pdf} using the given options. */
  Pdf print(PrintOptions printOptions) throws WebDriverException;
}
