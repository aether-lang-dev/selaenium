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


class _CapabilityDescriptor:
    """Reads/writes one top-level W3C capability as an attribute.

    Mainstream exposes the standard capabilities as typed properties rather than
    making callers remember the camelCase wire key; each of those is one of
    these, bound to the capability name it reads and writes.
    """

    def __init__(self, name: str):
        self.name = name

    def __get__(self, obj, cls):
        if obj is None:
            return self
        return obj._caps.get(self.name)

    def __set__(self, obj, value) -> None:
        obj.set_capability(self.name, value)


class _PageLoadStrategyDescriptor(_CapabilityDescriptor):
    """``pageLoadStrategy`` — only the three W3C values are accepted."""

    def __set__(self, obj, value) -> None:
        if value not in ("normal", "eager", "none"):
            raise ValueError("Strategy can only be one of the following: normal, eager, none")
        obj.set_capability(self.name, value)


class _UnhandledPromptBehaviorDescriptor(_CapabilityDescriptor):
    """``unhandledPromptBehavior`` — only the W3C prompt-handling values."""

    VALUES = ("dismiss", "accept", "dismiss and notify", "accept and notify", "ignore")

    def __set__(self, obj, value) -> None:
        if value not in self.VALUES:
            raise ValueError(f"Behavior can only be one of the following: {', '.join(self.VALUES)}")
        obj.set_capability(self.name, value)


class _TimeoutsDescriptor(_CapabilityDescriptor):
    """``timeouts`` — the W3C {implicit, pageLoad, script} block, in ms."""

    def __set__(self, obj, value) -> None:
        if not all(key in ("implicit", "pageLoad", "script") for key in value.keys()):
            raise ValueError("Timeout keys can only be one of the following: implicit, pageLoad, script")
        obj.set_capability(self.name, value)


class _ProxyDescriptor(_CapabilityDescriptor):
    """``proxy`` — takes a :class:`~selenium.webdriver.common.proxy.Proxy` and
    stores its rendered capability block."""

    def __set__(self, obj, value) -> None:
        if not hasattr(value, "to_capabilities"):
            raise TypeError("Proxy must be an instance of selenium.webdriver.common.proxy.Proxy")
        obj.set_capability(self.name, value.to_capabilities())


class _EnableBidiDescriptor(_CapabilityDescriptor):
    """``enable_bidi`` is a read of ``webSocketUrl`` and a write of it too —
    matching mainstream, where asking for BiDi means asking for the socket."""

    def __get__(self, obj, cls):
        if obj is None:
            return self
        return obj._caps.get("webSocketUrl") is not None

    def __set__(self, obj, value) -> None:
        obj.set_capability("webSocketUrl", value)


class BaseOptions(metaclass=ABCMeta):
    """Base for browser options: an accumulating capabilities dict plus the
    mainstream setter surface."""

    # ---- the standard W3C capabilities, as mainstream typed properties ----
    browser_version = _CapabilityDescriptor("browserVersion")
    platform_name = _CapabilityDescriptor("platformName")
    accept_insecure_certs = _CapabilityDescriptor("acceptInsecureCerts")
    strict_file_interactability = _CapabilityDescriptor("strictFileInteractability")
    set_window_rect = _CapabilityDescriptor("setWindowRect")
    web_socket_url = _CapabilityDescriptor("webSocketUrl")
    enable_downloads = _CapabilityDescriptor("se:downloadsEnabled")
    page_load_strategy = _PageLoadStrategyDescriptor("pageLoadStrategy")
    unhandled_prompt_behavior = _UnhandledPromptBehaviorDescriptor("unhandledPromptBehavior")
    timeouts = _TimeoutsDescriptor("timeouts")
    proxy = _ProxyDescriptor("proxy")
    enable_bidi = _EnableBidiDescriptor("webSocketUrl")

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
