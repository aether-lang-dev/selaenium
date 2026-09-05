package org.openqa.selenium;

import java.util.List;

/**
 * The find-element contract shared by {@link WebDriver} and {@link WebElement}.
 * Mirrors Selenium 4.x's {@code org.openqa.selenium.SearchContext}: anything that
 * can be searched exposes {@link #findElement(By)} / {@link #findElements(By)}.
 */
public interface SearchContext {

  /**
   * Find all elements within the current context using the given mechanism.
   *
   * @param by the locating mechanism to use
   * @return a list of all matching elements, or an empty list if nothing matches
   */
  List<WebElement> findElements(By by);

  /**
   * Find the first element using the given mechanism.
   *
   * @param by the locating mechanism to use
   * @return the first matching element
   * @throws NoSuchElementException if no matching element is found
   */
  WebElement findElement(By by);
}
