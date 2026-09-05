"""The Selenium 4.x ``selenium.webdriver.support.ui`` grab-bag import path::

    from selenium.webdriver.support.ui import WebDriverWait, Select

Thin re-export shim so the common upstream imports resolve; the classes are
defined once in ``support.wait`` / ``support.select``.
"""

from .wait import WebDriverWait
from .select import Select

__all__ = ["WebDriverWait", "Select"]
