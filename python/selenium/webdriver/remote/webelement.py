"""``WebElement``, at the Selenium 4.x import path
``from selenium.webdriver.remote.webelement import WebElement``.

Re-exports the single ``WebElement`` from the binding core.
"""

from ..._webdriver import WebElement

__all__ = ["WebElement"]
