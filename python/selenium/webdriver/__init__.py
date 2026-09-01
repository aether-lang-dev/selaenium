"""selenium.webdriver — the Selenium 4.x entry-point namespace.

    from selenium import webdriver
    driver = webdriver.Chrome()

``Chrome`` / ``Remote`` mirror Selenium's driver constructors. ``Chrome()`` with
no command_executor lets the engine resolve and launch its own chromedriver.
"""

from .._webdriver import (
    BiDi,
    BidiEvent,
    Chrome,
    Remote,
    LocalChrome,
    DriverProcess,
    WebDriver,
    WebElement,
    resolve_driver,
    launch_driver,
    ensure_driver,
)
from .._native import configure as configure_native_lib
from .common.by import By

__all__ = [
    "BiDi",
    "BidiEvent",
    "Chrome",
    "Remote",
    "LocalChrome",
    "DriverProcess",
    "WebDriver",
    "WebElement",
    "By",
    "resolve_driver",
    "launch_driver",
    "ensure_driver",
    "configure_native_lib",
]
