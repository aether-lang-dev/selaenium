package org.openqa.selenium.support.ui;

import java.util.function.Function;
import org.openqa.selenium.WebDriver;

/**
 * A condition evaluated against a {@link WebDriver} by {@link WebDriverWait}.
 * Mirrors Selenium 4.x's {@code org.openqa.selenium.support.ui.ExpectedCondition}:
 * it is a {@link Function}{@code <WebDriver, T>}, so a lambda works directly.
 */
public interface ExpectedCondition<T> extends Function<WebDriver, T> {}
