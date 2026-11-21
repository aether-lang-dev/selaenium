"""Shared by the live tests: a chromedriver started by the ENGINE.

The engine owns the driver's lifetime (see docs/Selenium-Manager-Port.md,
"Driver and browser lifetime"): the whole tree, browser included, ends on
``stop()`` and also when this process dies however it dies. A test that spawned
chromedriver itself with subprocess got neither, and a browser whose session was
not quit outlived it.
"""
import pytest

from selenium.webdriver import ensure_driver


def chrome_driver():
    """Start chromedriver through the engine; skip the test if none resolves."""
    proc = ensure_driver("chrome")
    if proc is None:
        pytest.skip("engine cannot resolve a chromedriver (offline, no cache)")
    return proc
