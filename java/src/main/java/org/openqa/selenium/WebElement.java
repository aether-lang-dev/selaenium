package org.openqa.selenium;

import java.util.List;
import java.util.Map;

/**
 * A located element. Mirrors Selenium 4.x's {@code org.openqa.selenium.WebElement}
 * surface (getter grammar: {@code getText()}, {@code getTagName()}). The concrete
 * implementation is {@link RemoteWebElement}.
 */
public interface WebElement {

    String id();

    void click();

    void clear();

    void sendKeys(String text);

    String getText();

    String getTagName();

    boolean isDisplayed();

    Object getAttribute(String name);

    Object getDomAttribute(String name);

    Object getProperty(String name);

    boolean isEnabled();

    boolean isSelected();

    Map<String, Object> rect();

    WebElement findElement(By by);

    List<WebElement> findElements(By by);
}
