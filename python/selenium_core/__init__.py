"""selenium_core — Selenium WebDriver for Python, re-glued to the shared
pure-Aether WebDriver core.

This is a thin binding: the W3C protocol logic (command catalog, route table,
path templating, By normalization, error decode, HTTP round-trip) lives ONCE in
the in-repo Aether engine (``core/selenium_core.ae``) and is shared by every
language binding via ``libselenium_core.so``. This package is the Python face.

    from selenium_core import Chrome, By

    driver = Chrome("http://127.0.0.1:9515")
    driver.get("https://example.com")
    print(driver.title)
    driver.find_element(By.CSS_SELECTOR, "a").click()
    driver.quit()
"""

from ._native import configure as configure_native_lib
from ._webdriver import (
    By,
    Chrome,
    ElementClickInterceptedError,
    ElementNotInteractableError,
    InvalidSelectorError,
    JavascriptError,
    NoSuchElementError,
    NoSuchFrameError,
    NoSuchWindowError,
    Remote,
    SessionNotCreatedError,
    StaleElementReferenceError,
    UnknownCommandError,
    WebDriver,
    WebDriverError,
    WebElement,
)

__all__ = [
    "By",
    "Chrome",
    "Remote",
    "WebDriver",
    "WebElement",
    "WebDriverError",
    "NoSuchElementError",
    "StaleElementReferenceError",
    "ElementClickInterceptedError",
    "ElementNotInteractableError",
    "InvalidSelectorError",
    "JavascriptError",
    "NoSuchFrameError",
    "NoSuchWindowError",
    "SessionNotCreatedError",
    "UnknownCommandError",
    "configure_native_lib",
]

__version__ = "0.1.0"
