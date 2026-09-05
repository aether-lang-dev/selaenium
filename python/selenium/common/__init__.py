"""selenium.common — the mainstream import root for shared exception types.

    from selenium.common.exceptions import NoSuchElementException

Re-exports the exception taxonomy defined once in the binding core, so a script
written against upstream Selenium imports the same names from the same path.
"""

from .exceptions import *  # noqa: F401,F403
from . import exceptions  # noqa: F401
