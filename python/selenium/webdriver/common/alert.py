"""``Alert``, at the Selenium 4.x import path
``from selenium.webdriver.common.alert import Alert``.

Re-exports the single ``Alert`` from the binding core (the same object
``driver.switch_to.alert`` returns). Construct with the driver::

    from selenium.webdriver.common.alert import Alert
    Alert(driver).accept()
"""

from ..._webdriver import Alert

__all__ = ["Alert"]
