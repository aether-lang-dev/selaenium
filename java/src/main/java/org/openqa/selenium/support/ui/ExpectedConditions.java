package org.openqa.selenium.support.ui;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;
import org.openqa.selenium.Alert;
import org.openqa.selenium.By;
import org.openqa.selenium.JavascriptExecutor;
import org.openqa.selenium.NoAlertPresentException;
import org.openqa.selenium.NoSuchElementException;
import org.openqa.selenium.StaleElementReferenceException;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;

/**
 * Ready-made {@link ExpectedCondition}s for {@link WebDriverWait#until}. Mirrors
 * Selenium 4.x's {@code org.openqa.selenium.support.ui.ExpectedConditions}.
 *
 * <p>A condition returns a truthy value to finish the wait, or {@code null} /
 * {@code false} to keep polling. Conditions that locate an element treat a
 * missing element as "not yet" rather than an error, so they compose.
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

    // ---- titles and URLs ----------------------------------------------------

    /** The current URL equals {@code url}. */
    public static ExpectedCondition<Boolean> urlToBe(String url) {
        return driver -> url.equals(driver.getCurrentUrl());
    }

    /** The current URL matches the regular expression {@code regex}. */
    public static ExpectedCondition<Boolean> urlMatches(String regex) {
        Pattern pattern = Pattern.compile(regex);
        return driver -> {
            String url = driver.getCurrentUrl();
            return url != null && pattern.matcher(url).find();
        };
    }

    // ---- element text -------------------------------------------------------

    /** The given element contains {@code text}. */
    public static ExpectedCondition<Boolean> textToBePresentInElement(WebElement element, String text) {
        return driver -> {
            try {
                String elText = element.getText();
                return elText != null && elText.contains(text);
            } catch (StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The element located by {@code locator} has exactly the text {@code text}. */
    public static ExpectedCondition<Boolean> textToBe(By locator, String text) {
        return driver -> {
            try {
                return text.equals(driver.findElement(locator).getText());
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The text of the element located by {@code locator} matches {@code regex}. */
    public static ExpectedCondition<Boolean> textMatches(By locator, Pattern regex) {
        return driver -> {
            try {
                String elText = driver.findElement(locator).getText();
                return elText != null && regex.matcher(elText).find();
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The {@code value} attribute of the element located by {@code locator} contains {@code text}. */
    public static ExpectedCondition<Boolean> textToBePresentInElementValue(By locator, String text) {
        return driver -> {
            try {
                String value = driver.findElement(locator).getAttribute("value");
                return value != null && value.contains(text);
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The {@code value} attribute of {@code element} contains {@code text}. */
    public static ExpectedCondition<Boolean> textToBePresentInElementValue(WebElement element, String text) {
        return driver -> {
            try {
                String value = element.getAttribute("value");
                return value != null && value.contains(text);
            } catch (StaleElementReferenceException e) {
                return null;
            }
        };
    }

    // ---- attributes and properties -----------------------------------------

    /** An attribute (or property) of {@code element} equals {@code value}. */
    public static ExpectedCondition<Boolean> attributeToBe(WebElement element, String attribute, String value) {
        return driver -> value.equals(element.getAttribute(attribute));
    }

    /** An attribute (or property) of the located element equals {@code value}. */
    public static ExpectedCondition<Boolean> attributeToBe(By locator, String attribute, String value) {
        return driver -> {
            try {
                return value.equals(driver.findElement(locator).getAttribute(attribute));
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** An attribute (or property) of {@code element} contains {@code value}. */
    public static ExpectedCondition<Boolean> attributeContains(WebElement element, String attribute, String value) {
        return driver -> {
            String actual = element.getAttribute(attribute);
            return actual != null && actual.contains(value);
        };
    }

    /** An attribute (or property) of the located element contains {@code value}. */
    public static ExpectedCondition<Boolean> attributeContains(By locator, String attribute, String value) {
        return driver -> {
            try {
                String actual = driver.findElement(locator).getAttribute(attribute);
                return actual != null && actual.contains(value);
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** An attribute (or property) of {@code element} is set and non-empty. */
    public static ExpectedCondition<Boolean> attributeToBeNotEmpty(WebElement element, String attribute) {
        return driver -> {
            String actual = element.getAttribute(attribute);
            return actual != null && !actual.isEmpty();
        };
    }

    /** The literal DOM attribute of {@code element} equals {@code value}. */
    public static ExpectedCondition<Boolean> domAttributeToBe(WebElement element, String attribute, String value) {
        return driver -> value.equals(element.getDomAttribute(attribute));
    }

    /** The DOM property of {@code element} equals {@code value}. */
    public static ExpectedCondition<Boolean> domPropertyToBe(WebElement element, String property, String value) {
        return driver -> value.equals(element.getDomProperty(property));
    }

    // ---- visibility and invisibility ---------------------------------------

    /** Every element in {@code elements} is displayed; yields the list. */
    public static ExpectedCondition<List<WebElement>> visibilityOfAllElements(List<WebElement> elements) {
        return driver -> {
            for (WebElement el : elements) {
                if (!el.isDisplayed()) {
                    return null;
                }
            }
            return elements.isEmpty() ? null : elements;
        };
    }

    /** Every element in {@code elements} is displayed; yields the list. */
    public static ExpectedCondition<List<WebElement>> visibilityOfAllElements(WebElement... elements) {
        return visibilityOfAllElements(Arrays.asList(elements));
    }

    /** All elements located by {@code locator} are present and displayed. */
    public static ExpectedCondition<List<WebElement>> visibilityOfAllElementsLocatedBy(By locator) {
        return driver -> {
            List<WebElement> els = driver.findElements(locator);
            for (WebElement el : els) {
                if (!el.isDisplayed()) {
                    return null;
                }
            }
            return els.isEmpty() ? null : els;
        };
    }

    /** The elements found by {@code childLocator} under {@code parent} are displayed. */
    public static ExpectedCondition<List<WebElement>> visibilityOfNestedElementsLocatedBy(
            By parent, By childLocator) {
        return driver -> {
            List<WebElement> els = driver.findElement(parent).findElements(childLocator);
            for (WebElement el : els) {
                if (!el.isDisplayed()) {
                    return null;
                }
            }
            return els.isEmpty() ? null : els;
        };
    }

    /** The given element is not displayed (or is gone from the DOM). */
    public static ExpectedCondition<Boolean> invisibilityOf(WebElement element) {
        return driver -> {
            try {
                return !element.isDisplayed();
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return true;
            }
        };
    }

    /** No element located by {@code locator} is displayed (or none is present). */
    public static ExpectedCondition<Boolean> invisibilityOfElementLocated(By locator) {
        return driver -> {
            try {
                return !driver.findElement(locator).isDisplayed();
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return true;
            }
        };
    }

    /** The located element is gone, hidden, or no longer carries {@code text}. */
    public static ExpectedCondition<Boolean> invisibilityOfElementWithText(By locator, String text) {
        return driver -> {
            try {
                return !text.equals(driver.findElement(locator).getText());
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return true;
            }
        };
    }

    /** None of {@code elements} is displayed. */
    public static ExpectedCondition<Boolean> invisibilityOfAllElements(List<WebElement> elements) {
        return driver -> {
            for (WebElement el : elements) {
                try {
                    if (el.isDisplayed()) {
                        return false;
                    }
                } catch (NoSuchElementException | StaleElementReferenceException e) {
                    // gone counts as invisible
                }
            }
            return true;
        };
    }

    /** None of {@code elements} is displayed. */
    public static ExpectedCondition<Boolean> invisibilityOfAllElements(WebElement... elements) {
        return invisibilityOfAllElements(Arrays.asList(elements));
    }

    // ---- counting -----------------------------------------------------------

    /** Exactly {@code number} elements match {@code locator}. */
    public static ExpectedCondition<List<WebElement>> numberOfElementsToBe(By locator, Integer number) {
        return driver -> {
            List<WebElement> els = driver.findElements(locator);
            return els.size() == number ? els : null;
        };
    }

    /** More than {@code number} elements match {@code locator}. */
    public static ExpectedCondition<List<WebElement>> numberOfElementsToBeMoreThan(By locator, Integer number) {
        return driver -> {
            List<WebElement> els = driver.findElements(locator);
            return els.size() > number ? els : null;
        };
    }

    /** Fewer than {@code number} elements match {@code locator}. */
    public static ExpectedCondition<List<WebElement>> numberOfElementsToBeLessThan(By locator, Integer number) {
        return driver -> {
            List<WebElement> els = driver.findElements(locator);
            return els.size() < number ? els : null;
        };
    }

    /** The session has exactly {@code expected} top-level windows/tabs. */
    public static ExpectedCondition<Boolean> numberOfWindowsToBe(int expected) {
        return driver -> driver.getWindowHandles().size() == expected;
    }

    // ---- nested lookups -----------------------------------------------------

    /** An element matching {@code child} exists under the element matching {@code parent}. */
    public static ExpectedCondition<WebElement> presenceOfNestedElementLocatedBy(By parent, By child) {
        return driver -> {
            try {
                return driver.findElement(parent).findElement(child);
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** Elements matching {@code child} exist under the element matching {@code parent}. */
    public static ExpectedCondition<List<WebElement>> presenceOfNestedElementsLocatedBy(By parent, By child) {
        return driver -> {
            try {
                List<WebElement> els = driver.findElement(parent).findElements(child);
                return els.isEmpty() ? null : els;
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    // ---- selection state ----------------------------------------------------

    /** The given element is selected. */
    public static ExpectedCondition<Boolean> elementToBeSelected(WebElement element) {
        return elementSelectionStateToBe(element, true);
    }

    /** The given element's selected state is {@code selected}. */
    public static ExpectedCondition<Boolean> elementSelectionStateToBe(WebElement element, boolean selected) {
        return driver -> element.isSelected() == selected;
    }

    /** The located element's selected state is {@code selected}. */
    public static ExpectedCondition<Boolean> elementSelectionStateToBe(By locator, boolean selected) {
        return driver -> {
            try {
                return driver.findElement(locator).isSelected() == selected;
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The element located by {@code locator} is present, displayed and enabled. */
    public static ExpectedCondition<WebElement> elementToBeClickable(WebElement element) {
        return driver -> (element.isDisplayed() && element.isEnabled()) ? element : null;
    }

    // ---- staleness, frames, alerts -----------------------------------------

    /** The given element is no longer attached to the DOM. */
    public static ExpectedCondition<Boolean> stalenessOf(WebElement element) {
        return driver -> {
            try {
                element.isEnabled();
                return false;
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return true;
            }
        };
    }

    /** Re-run {@code condition}, retrying once if the element under it went stale. */
    public static <T> ExpectedCondition<T> refreshed(ExpectedCondition<T> condition) {
        return driver -> {
            try {
                return condition.apply(driver);
            } catch (StaleElementReferenceException e) {
                return condition.apply(driver);
            }
        };
    }

    /** The frame is available; switches to it and yields the driver. */
    public static ExpectedCondition<WebDriver> frameToBeAvailableAndSwitchToIt(By locator) {
        return driver -> {
            try {
                return driver.switchTo().frame(driver.findElement(locator));
            } catch (NoSuchElementException | StaleElementReferenceException e) {
                return null;
            }
        };
    }

    /** The frame with this name or id is available; switches to it. */
    public static ExpectedCondition<WebDriver> frameToBeAvailableAndSwitchToIt(String nameOrId) {
        return driver -> {
            try {
                return driver.switchTo().frame(nameOrId);
            } catch (RuntimeException e) {
                return null;
            }
        };
    }

    /** The frame at this index is available; switches to it. */
    public static ExpectedCondition<WebDriver> frameToBeAvailableAndSwitchToIt(int index) {
        return driver -> {
            try {
                return driver.switchTo().frame(index);
            } catch (RuntimeException e) {
                return null;
            }
        };
    }

    /** A JavaScript alert is showing; yields it. */
    public static ExpectedCondition<Alert> alertIsPresent() {
        return driver -> {
            try {
                return driver.switchTo().alert();
            } catch (NoAlertPresentException e) {
                return null;
            }
        };
    }

    // ---- script -------------------------------------------------------------

    /** {@code script} runs without throwing. */
    public static ExpectedCondition<Boolean> javaScriptThrowsNoExceptions(String script) {
        return driver -> {
            try {
                ((JavascriptExecutor) driver).executeScript(script);
                return true;
            } catch (RuntimeException e) {
                return false;
            }
        };
    }

    /** {@code script} returns a non-null, non-empty value; yields it. */
    public static ExpectedCondition<Object> jsReturnsValue(String script) {
        return driver -> {
            Object value = ((JavascriptExecutor) driver).executeScript(script);
            if (value instanceof List) {
                return ((List<?>) value).isEmpty() ? null : value;
            }
            if (value instanceof String) {
                return ((String) value).isEmpty() ? null : value;
            }
            return value;
        };
    }

    // ---- composition --------------------------------------------------------

    /** Every condition holds. */
    public static ExpectedCondition<Boolean> and(ExpectedCondition<?>... conditions) {
        return driver -> {
            for (ExpectedCondition<?> condition : conditions) {
                Object result = condition.apply(driver);
                if (result == null || Boolean.FALSE.equals(result)) {
                    return false;
                }
            }
            return true;
        };
    }

    /** At least one condition holds. */
    public static ExpectedCondition<Boolean> or(ExpectedCondition<?>... conditions) {
        return driver -> {
            for (ExpectedCondition<?> condition : conditions) {
                try {
                    Object result = condition.apply(driver);
                    if (result != null && !Boolean.FALSE.equals(result)) {
                        return true;
                    }
                } catch (RuntimeException e) {
                    // a throwing condition simply does not hold
                }
            }
            return false;
        };
    }
}
