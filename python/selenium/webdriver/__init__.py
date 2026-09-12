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
    Firefox,
    Edge,
    Safari,
    headless_chrome,
    headless_firefox,
    headless_edge,
    Remote,
    LocalChrome,
    DriverProcess,
    WebDriver,
    WebElement,
    ShadowRoot,
    Timeouts,
    VirtualAuthenticatorOptions,
    Credential,
    SwitchTo,
    Alert,
    resolve_driver,
    launch_driver,
    ensure_driver,
)
from .._native import configure as configure_native_lib
from .common.by import By
from .common.proxy import Proxy, ProxyType
from .common.keys import Keys
from .common.action_chains import ActionChains
from .chrome.options import Options as ChromeOptions
from .support.wait import WebDriverWait
from .support.select import Select
from .support import expected_conditions

__all__ = [
    "BiDi",
    "BidiEvent",
    "Chrome",
    "Firefox",
    "Edge",
    "Safari",
    "headless_chrome",
    "headless_firefox",
    "headless_edge",
    "Remote",
    "LocalChrome",
    "DriverProcess",
    "WebDriver",
    "WebElement",
    "ShadowRoot",
    "Timeouts",
    "Proxy",
    "ProxyType",
    "VirtualAuthenticatorOptions",
    "Credential",
    "SwitchTo",
    "Alert",
    "By",
    "Keys",
    "ActionChains",
    "ChromeOptions",
    "WebDriverWait",
    "Select",
    "expected_conditions",
    "resolve_driver",
    "launch_driver",
    "ensure_driver",
    "configure_native_lib",
]
