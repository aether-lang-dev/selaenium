"""``Timeouts``, at the Selenium 4.x import path
``from selenium.webdriver.common.timeouts import Timeouts``.

Re-exports the single ``Timeouts`` from the binding core.
"""

from ..._webdriver import Timeouts

__all__ = ["Timeouts"]
