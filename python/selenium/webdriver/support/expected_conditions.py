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

import re
from collections.abc import Iterable
from typing import Callable, Tuple

from ..._webdriver import (
    NoSuchElementException,
    NoSuchFrameException,
    StaleElementReferenceException,
    WebDriverException,
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


def _element_if_visible(element: WebElement, visibility: bool = True):
    return element if element.is_displayed() == visibility else False


def visibility_of_any_elements_located(locator: Locator) -> Callable[..., list]:
    """At least one matching element is visible; returns the visible ones."""
    def _cond(driver):
        return [e for e in driver.find_elements(*locator) if _element_if_visible(e)]
    return _cond


def visibility_of_all_elements_located(locator: Locator) -> Callable[..., list]:
    """All matching elements are present AND visible; returns the list, else False."""
    def _cond(driver):
        try:
            elements = driver.find_elements(*locator)
            for element in elements:
                if _element_if_visible(element, visibility=False):
                    return False
            return elements
        except StaleElementReferenceException:
            return False
    return _cond


def text_to_be_present_in_element_value(locator: Locator, text_: str) -> Callable[..., bool]:
    """``text_`` is a substring of the element's ``value`` attribute."""
    def _cond(driver):
        try:
            element_text = driver.find_element(*locator).get_attribute("value")
            if element_text is None:
                return False
            return text_ in element_text
        except StaleElementReferenceException:
            return False
    return _cond


def text_to_be_present_in_element_attribute(locator: Locator, attribute_: str, text_: str) -> Callable[..., bool]:
    """``text_`` is a substring of the element's ``attribute_``."""
    def _cond(driver):
        try:
            element_text = driver.find_element(*locator).get_attribute(attribute_)
            if element_text is None:
                return False
            return text_ in element_text
        except StaleElementReferenceException:
            return False
    return _cond


def frame_to_be_available_and_switch_to_it(locator) -> Callable[..., bool]:
    """The frame is available; switch to it. ``locator`` is a (By, value) tuple,
    a name/id string, or a frame WebElement."""
    def _cond(driver):
        try:
            if isinstance(locator, Iterable) and not isinstance(locator, str):
                driver.switch_to.frame(driver.find_element(*locator))
            else:
                driver.switch_to.frame(locator)
            return True
        except NoSuchFrameException:
            return False
    return _cond


def invisibility_of_element(element) -> Callable[..., bool]:
    """Alias of :func:`invisibility_of_element_located` accepting a locator or
    a WebElement."""
    return invisibility_of_element_located(element)


def element_to_be_selected(element: WebElement) -> Callable[..., bool]:
    """The given element is selected."""
    def _cond(_driver):
        return element.is_selected()
    return _cond


def element_located_to_be_selected(locator: Locator) -> Callable[..., bool]:
    """The element found by ``locator`` is selected."""
    def _cond(driver):
        return driver.find_element(*locator).is_selected()
    return _cond


def element_selection_state_to_be(element: WebElement, is_selected: bool) -> Callable[..., bool]:
    """The given element's selection state equals ``is_selected``."""
    def _cond(_driver):
        return element.is_selected() == is_selected
    return _cond


def element_located_selection_state_to_be(locator: Locator, is_selected: bool) -> Callable[..., bool]:
    """The located element's selection state equals ``is_selected``."""
    def _cond(driver):
        try:
            element = driver.find_element(*locator)
            return element.is_selected() == is_selected
        except StaleElementReferenceException:
            return False
    return _cond


def number_of_windows_to_be(num_windows: int) -> Callable[..., bool]:
    """The number of open windows equals ``num_windows``."""
    def _cond(driver):
        return len(driver.window_handles) == num_windows
    return _cond


def new_window_is_opened(current_handles) -> Callable[..., bool]:
    """A new window opened since ``current_handles`` was captured."""
    def _cond(driver):
        return len(driver.window_handles) > len(current_handles)
    return _cond


def element_attribute_to_include(locator: Locator, attribute_: str) -> Callable[..., bool]:
    """The located element has the attribute ``attribute_`` (value not None)."""
    def _cond(driver):
        try:
            element_attribute = driver.find_element(*locator).get_attribute(attribute_)
            return element_attribute is not None
        except StaleElementReferenceException:
            return False
    return _cond


def url_matches(pattern: str) -> Callable[..., bool]:
    """The current URL matches the regular-expression ``pattern`` (re.search)."""
    def _cond(driver):
        return re.search(pattern, driver.current_url) is not None
    return _cond


def url_changes(url: str) -> Callable[..., bool]:
    """The current URL differs from ``url``."""
    def _cond(driver):
        return url != driver.current_url
    return _cond


def any_of(*expected_conditions) -> Callable[..., object]:
    """Logical OR: return the first truthy condition's result, else False."""
    def any_of_condition(driver):
        for expected_condition in expected_conditions:
            try:
                result = expected_condition(driver)
                if result:
                    return result
            except WebDriverException:
                pass
        return False
    return any_of_condition


def all_of(*expected_conditions) -> Callable[..., object]:
    """Logical AND: return the list of each result if all are truthy, else False."""
    def all_of_condition(driver):
        results = []
        for expected_condition in expected_conditions:
            try:
                result = expected_condition(driver)
                if not result:
                    return False
                results.append(result)
            except WebDriverException:
                return False
        return results
    return all_of_condition


def none_of(*expected_conditions) -> Callable[..., bool]:
    """Logical NOR: True when none of the conditions are truthy."""
    def none_of_condition(driver):
        for expected_condition in expected_conditions:
            try:
                result = expected_condition(driver)
                if result:
                    return False
            except WebDriverException:
                pass
        return True
    return none_of_condition


__all__ = [
    "presence_of_element_located",
    "presence_of_all_elements_located",
    "visibility_of_element_located",
    "visibility_of",
    "visibility_of_any_elements_located",
    "visibility_of_all_elements_located",
    "invisibility_of_element_located",
    "invisibility_of_element",
    "element_to_be_clickable",
    "text_to_be_present_in_element",
    "text_to_be_present_in_element_value",
    "text_to_be_present_in_element_attribute",
    "frame_to_be_available_and_switch_to_it",
    "element_to_be_selected",
    "element_located_to_be_selected",
    "element_selection_state_to_be",
    "element_located_selection_state_to_be",
    "number_of_windows_to_be",
    "new_window_is_opened",
    "element_attribute_to_include",
    "title_is",
    "title_contains",
    "url_to_be",
    "url_contains",
    "url_matches",
    "url_changes",
    "any_of",
    "all_of",
    "none_of",
    "alert_is_present",
    "staleness_of",
]
