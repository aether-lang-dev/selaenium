"""Locator strategies, at the Selenium 4.x import path
``from selenium.webdriver.common.by import By``.

Re-exports the single ``By`` defined in the binding core so there is one source
of truth for the strategy strings the engine's ``by_locator`` accepts.
"""

from ..._webdriver import By

__all__ = ["By"]
