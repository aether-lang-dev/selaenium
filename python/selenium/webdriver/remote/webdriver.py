"""``WebDriver``, at the Selenium 4.x import path
``from selenium.webdriver.remote.webdriver import WebDriver``.

Re-exports the single ``WebDriver`` from the binding core so there is one source
of truth for the session surface.
"""

from ..._webdriver import WebDriver

__all__ = ["WebDriver"]
