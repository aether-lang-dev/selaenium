"""selenium — Selenium WebDriver for Python, re-glued to the shared pure-Aether
WebDriver core.

This is a thin binding: the W3C protocol logic (command catalog, route table,
path templating, By normalization, error decode, HTTP round-trip) lives ONCE in
the in-repo Aether engine (``selenium_core/selenium_core.ae``) and is shared by
every language binding via ``libselenium_core.so``. This package is the Python
face, shaped to match Selenium 4.x:

    from selenium import webdriver
    from selenium.webdriver.common.by import By

    driver = webdriver.Chrome()            # engine launches its own chromedriver
    driver.get("https://example.com")
    print(driver.title)
    driver.find_element(By.CSS_SELECTOR, "a").click()
    driver.quit()
"""

from . import webdriver
from .webdriver.common.by import By
from ._webdriver import (
    BiDi,
    BidiEvent,
    WebDriver,
    WebElement,
    WebDriverException,
    NoSuchElementException,
    StaleElementReferenceException,
    ElementClickInterceptedException,
    ElementNotInteractableException,
    InvalidSelectorException,
    JavascriptException,
    NoSuchFrameException,
    NoSuchWindowException,
    SessionNotCreatedException,
    TimeoutException,
    UnknownCommandException,
)

__all__ = [
    "webdriver",
    "By",
    "BiDi",
    "BidiEvent",
    "WebDriver",
    "WebElement",
    "WebDriverException",
    "NoSuchElementException",
    "StaleElementReferenceException",
    "ElementClickInterceptedException",
    "ElementNotInteractableException",
    "InvalidSelectorException",
    "JavascriptException",
    "NoSuchFrameException",
    "NoSuchWindowException",
    "SessionNotCreatedException",
    "TimeoutException",
    "UnknownCommandException",
]

__version__ = "0.1.0"
