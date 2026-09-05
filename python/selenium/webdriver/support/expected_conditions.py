"""Expected conditions, at the Selenium 4.x import path
``from selenium.webdriver.support import expected_conditions as EC``.

Each function returns a *callable of the driver* suitable for
``WebDriverWait(driver, 10).until(...)``. Signatures and names match mainstream
Selenium so scripts import and call them unchanged::

    from selenium.webdriver.support.wait import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.webdriver.common.by import By

    el = WebDriverWait(d, 10).until(
        EC.element_to_be_clickable((By.ID, "submit")))

A *locator* is the mainstream ``(By.X, "value")`` tuple.
"""
from __future__ import annotations

from typing import Callable, Tuple

from ..._webdriver import (
    NoSuchElementException,
    StaleElementReferenceException,
    WebElement,
)

Locator = Tuple[str, str]


def _find(driver, locator: Locator) -> WebElement:
    return driver.find_element(locator[0], locator[1])


def presence_of_element_located(locator: Locator) -> Callable[..., WebElement]:
    """Element present in the DOM (not necessarily visible)."""
    def _cond(driver):
        return _find(driver, locator)
    return _cond


def presence_of_all_elements_located(locator: Locator) -> Callable[..., list]:
    """At least one element present; returns the list."""
    def _cond(driver):
        els = driver.find_elements(locator[0], locator[1])
        return els if els else False
    return _cond


def visibility_of_element_located(locator: Locator) -> Callable[..., WebElement]:
    """Element present AND displayed."""
    def _cond(driver):
        try:
            el = _find(driver, locator)
            return el if el.is_displayed() else False
        except StaleElementReferenceException:
            return False
    return _cond


def visibility_of(element: WebElement) -> Callable[..., WebElement]:
    """A known element becomes displayed."""
    def _cond(_driver):
        try:
            return element if element.is_displayed() else False
        except StaleElementReferenceException:
            return False
    return _cond


def invisibility_of_element_located(locator: Locator) -> Callable[..., bool]:
    """Element is absent or not displayed."""
    def _cond(driver):
        try:
            return not _find(driver, locator).is_displayed()
        except (NoSuchElementException, StaleElementReferenceException):
            return True
    return _cond


def element_to_be_clickable(locator: Locator) -> Callable[..., WebElement]:
    """Element is visible and enabled."""
    def _cond(driver):
        try:
            el = _find(driver, locator)
            return el if (el.is_displayed() and el.is_enabled()) else False
        except StaleElementReferenceException:
            return False
    return _cond


def text_to_be_present_in_element(locator: Locator, text: str) -> Callable[..., bool]:
    """The element's text contains ``text``."""
    def _cond(driver):
        try:
            return text in _find(driver, locator).text
        except StaleElementReferenceException:
            return False
    return _cond


def title_is(title: str) -> Callable[..., bool]:
    return lambda driver: driver.title == title


def title_contains(fragment: str) -> Callable[..., bool]:
    return lambda driver: fragment in driver.title


def url_to_be(url: str) -> Callable[..., bool]:
    return lambda driver: driver.current_url == url


def url_contains(fragment: str) -> Callable[..., bool]:
    return lambda driver: fragment in driver.current_url


def alert_is_present() -> Callable[..., bool]:
    """An alert/confirm/prompt is open."""
    def _cond(driver):
        try:
            driver.alert_text  # raises if no alert
            return True
        except Exception:
            return False
    return _cond


def staleness_of(element: WebElement) -> Callable[..., bool]:
    """Element is no longer attached to the DOM."""
    def _cond(_driver):
        try:
            element.is_enabled()  # any command triggers stale check
            return False
        except StaleElementReferenceException:
            return True
    return _cond


__all__ = [
    "presence_of_element_located",
    "presence_of_all_elements_located",
    "visibility_of_element_located",
    "visibility_of",
    "invisibility_of_element_located",
    "element_to_be_clickable",
    "text_to_be_present_in_element",
    "title_is",
    "title_contains",
    "url_to_be",
    "url_contains",
    "alert_is_present",
    "staleness_of",
]
