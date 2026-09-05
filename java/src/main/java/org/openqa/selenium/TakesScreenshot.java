package org.openqa.selenium;

/**
 * A driver or element that can be captured as a screenshot. Mirrors Selenium
 * 4.x's {@code org.openqa.selenium.TakesScreenshot}.
 */
public interface TakesScreenshot {

  /**
   * Capture a screenshot and return it in the given {@link OutputType}.
   *
   * @param target the output type (e.g. {@link OutputType#BASE64}, {@link OutputType#BYTES},
   *     {@link OutputType#FILE})
   * @return the screenshot converted to the requested representation
   */
  <X> X getScreenshotAs(OutputType<X> target) throws WebDriverException;
}
