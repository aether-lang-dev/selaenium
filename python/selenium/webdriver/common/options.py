"""Browser options base classes, at the Selenium 4.x import path
``from selenium.webdriver.common.options import BaseOptions, ArgOptions``.

Match the mainstream method surface a script touches — ``set_capability``,
``add_argument``, ``to_capabilities``, ``capabilities`` — so an unmodified
upstream script builds options the same way. ``Chrome(options=...)`` in this
binding calls ``to_capabilities()`` to obtain the caps dict.

This is the source of truth for the option classes in this binding (the
Chrome-specific ``Options`` in ``chrome/options.py`` subclasses ``ArgOptions``).
"""
from __future__ import annotations

from abc import ABCMeta, abstractmethod
from enum import Enum


class PageLoadStrategy(str, Enum):
    """The W3C page-load strategies (normal / eager / none)."""

    normal = "normal"
    eager = "eager"
    none = "none"


class BaseOptions(metaclass=ABCMeta):
    """Base for browser options: an accumulating capabilities dict plus the
    mainstream setter surface."""

    def __init__(self) -> None:
        super().__init__()
        self._caps: dict = self.default_capabilities
        self.set_capability("pageLoadStrategy", PageLoadStrategy.normal.value)
        self.mobile_options: dict | None = None

    @property
    def capabilities(self) -> dict:
        return self._caps

    def set_capability(self, name: str, value) -> None:
        """Set a top-level W3C capability."""
        self._caps[name] = value

    def enable_mobile(self, android_package=None, android_activity=None, device_serial=None) -> None:
        """Enable mobile browser use (Android package/activity/serial)."""
        if not android_package:
            raise AttributeError("android_package must be passed in")
        self.mobile_options = {"androidPackage": android_package}
        if android_activity:
            self.mobile_options["androidActivity"] = android_activity
        if device_serial:
            self.mobile_options["androidDeviceSerial"] = device_serial

    @abstractmethod
    def to_capabilities(self) -> dict:
        """Convert options into a capabilities dictionary."""

    @property
    @abstractmethod
    def default_capabilities(self) -> dict:
        """The minimal capabilities dict this option set starts from."""


class ArgOptions(BaseOptions):
    """Options that accumulate command-line ``arguments`` — the base for Chromium."""

    BINARY_LOCATION_ERROR = "Binary Location Must be a String"
    FEDCM_CAPABILITY = "fedcm:accounts"

    def __init__(self) -> None:
        super().__init__()
        self._arguments: list[str] = []

    @property
    def arguments(self) -> list[str]:
        """The list of browser command-line arguments."""
        return self._arguments

    def add_argument(self, argument: str) -> None:
        """Append a command-line argument (e.g. ``--headless=new``)."""
        if argument:
            self._arguments.append(argument)
        else:
            raise ValueError("argument can not be null")

    def to_capabilities(self) -> dict:
        return self._caps

    @property
    def default_capabilities(self) -> dict:
        return {}


__all__ = ["PageLoadStrategy", "BaseOptions", "ArgOptions"]
