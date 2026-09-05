package org.openqa.selenium.support.ui;

import java.util.List;
import org.openqa.selenium.By;
import org.openqa.selenium.NoSuchElementException;
import org.openqa.selenium.WebElement;

/**
 * Ready-made {@link ExpectedCondition}s for {@link WebDriverWait#until}. Mirrors
 * the common subset of Selenium 4.x's
 * {@code org.openqa.selenium.support.ui.ExpectedConditions}.
 */
public final class ExpectedConditions {

    private ExpectedConditions() {}

    /** The element located by {@code locator} is present in the DOM. */
    public static ExpectedCondition<WebElement> presenceOfElementLocated(By locator) {
        return driver -> driver.findElement(locator);
    }

    /** The element located by {@code locator} is present and displayed. */
    public static ExpectedCondition<WebElement> visibilityOfElementLocated(By locator) {
        return driver -> {
            try {
                WebElement el = driver.findElement(locator);
                return el.isDisplayed() ? el : null;
            } catch (NoSuchElementException e) {
                return null;
            }
        };
    }

    /** All elements located by {@code locator} are present (non-empty list). */
    public static ExpectedCondition<List<WebElement>> presenceOfAllElementsLocatedBy(By locator) {
        return driver -> {
            List<WebElement> els = driver.findElements(locator);
            return els.isEmpty() ? null : els;
        };
    }

    /** The element located by {@code locator} is present, displayed and enabled. */
    public static ExpectedCondition<WebElement> elementToBeClickable(By locator) {
        return driver -> {
            try {
                WebElement el = driver.findElement(locator);
                return (el.isDisplayed() && el.isEnabled()) ? el : null;
            } catch (NoSuchElementException e) {
                return null;
            }
        };
    }

    /** The given element is displayed. */
    public static ExpectedCondition<WebElement> visibilityOf(WebElement element) {
        return driver -> element.isDisplayed() ? element : null;
    }

    /** The current page title equals {@code title}. */
    public static ExpectedCondition<Boolean> titleIs(String title) {
        return driver -> title.equals(driver.getTitle());
    }

    /** The current page title contains {@code fraction}. */
    public static ExpectedCondition<Boolean> titleContains(String fraction) {
        return driver -> {
            String t = driver.getTitle();
            return t != null && t.contains(fraction);
        };
    }

    /** The current URL contains {@code fraction}. */
    public static ExpectedCondition<Boolean> urlContains(String fraction) {
        return driver -> {
            String u = driver.getCurrentUrl();
            return u != null && u.contains(fraction);
        };
    }

    /** The element located by {@code locator} contains {@code text}. */
    public static ExpectedCondition<Boolean> textToBePresentInElementLocated(By locator, String text) {
        return driver -> {
            try {
                String elText = driver.findElement(locator).getText();
                return elText != null && elText.contains(text);
            } catch (NoSuchElementException e) {
                return null;
            }
        };
    }

    /** Negate a condition: true when {@code condition} is falsy or raises NoSuchElement. */
    public static ExpectedCondition<Boolean> not(ExpectedCondition<?> condition) {
        return driver -> {
            try {
                Object result = condition.apply(driver);
                return result == null || Boolean.FALSE.equals(result);
            } catch (NoSuchElementException e) {
                return true;
            }
        };
    }
}
