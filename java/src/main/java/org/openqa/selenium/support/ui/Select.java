package org.openqa.selenium.support.ui;

import java.util.ArrayList;
import java.util.List;
import org.openqa.selenium.By;
import org.openqa.selenium.NoSuchElementException;
import org.openqa.selenium.WebElement;

/**
 * A {@code <select>} dropdown helper. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.support.ui.Select}: wraps a {@code <select>}
 * WebElement and drives it by finding and clicking its {@code <option>} children.
 *
 * <pre>{@code
 * new Select(driver.findElement(By.id("country"))).selectByVisibleText("Spain");
 * }</pre>
 */
public class Select {

    private final WebElement element;
    private final boolean isMulti;

    public Select(WebElement element) {
        String tag = element.getTagName().toLowerCase();
        if (!"select".equals(tag)) {
            throw new IllegalArgumentException(
                    "Select only works on <select> elements, not <" + tag + ">");
        }
        this.element = element;
        String multiple = element.getAttribute("multiple");
        this.isMulti = multiple != null && !"false".equals(multiple);
    }

    public WebElement getWrappedElement() {
        return element;
    }

    public boolean isMultiple() {
        return isMulti;
    }

    public List<WebElement> getOptions() {
        return element.findElements(By.tagName("option"));
    }

    public List<WebElement> getAllSelectedOptions() {
        List<WebElement> selected = new ArrayList<>();
        for (WebElement o : getOptions()) {
            if (o.isSelected()) {
                selected.add(o);
            }
        }
        return selected;
    }

    public WebElement getFirstSelectedOption() {
        for (WebElement o : getOptions()) {
            if (o.isSelected()) {
                return o;
            }
        }
        throw new NoSuchElementException("No options are selected", 17);
    }

    public void selectByVisibleText(String text) {
        for (WebElement o : getOptions()) {
            if (text.equals(o.getText())) {
                select(o);
                return;
            }
        }
        throw new NoSuchElementException("Cannot locate option with text: " + text, 17);
    }

    public void selectByValue(String value) {
        for (WebElement o : getOptions()) {
            if (value.equals(o.getAttribute("value"))) {
                select(o);
                return;
            }
        }
        throw new NoSuchElementException("Cannot locate option with value: " + value, 17);
    }

    public void selectByIndex(int index) {
        List<WebElement> opts = getOptions();
        if (index < 0 || index >= opts.size()) {
            throw new NoSuchElementException("Cannot locate option with index: " + index, 17);
        }
        select(opts.get(index));
    }

    public void deselectAll() {
        if (!isMulti) {
            throw new UnsupportedOperationException("You may only deselect all options of a multi-select");
        }
        for (WebElement o : getOptions()) {
            if (o.isSelected()) {
                o.click();
            }
        }
    }

    public void deselectByValue(String value) {
        requireMulti();
        boolean matched = false;
        for (WebElement o : getOptions()) {
            if (value.equals(o.getAttribute("value"))) {
                deselect(o);
                matched = true;
            }
        }
        if (!matched) {
            throw new NoSuchElementException("Cannot locate option with value: " + value, 17);
        }
    }

    public void deselectByIndex(int index) {
        requireMulti();
        for (WebElement o : getOptions()) {
            if (String.valueOf(index).equals(o.getAttribute("index"))) {
                deselect(o);
                return;
            }
        }
        throw new NoSuchElementException("Cannot locate option with index: " + index, 17);
    }

    public void deselectByVisibleText(String text) {
        requireMulti();
        boolean matched = false;
        for (WebElement o : getOptions()) {
            if (text.equals(o.getText())) {
                deselect(o);
                matched = true;
            }
        }
        if (!matched) {
            throw new NoSuchElementException("Cannot locate option with text: " + text, 17);
        }
    }

    private void requireMulti() {
        if (!isMulti) {
            throw new UnsupportedOperationException("You may only deselect options of a multi-select");
        }
    }

    private void select(WebElement option) {
        if (!option.isSelected()) {
            option.click();
        }
    }

    private void deselect(WebElement option) {
        if (option.isSelected()) {
            option.click();
        }
    }
}
