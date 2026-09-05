"""``SwitchTo``, at the Selenium 4.x import path
``from selenium.webdriver.remote.switch_to import SwitchTo``.

Re-exports the single ``SwitchTo`` facade from the binding core (the same object
``driver.switch_to`` returns).
"""

from ..._webdriver import SwitchTo

__all__ = ["SwitchTo"]
