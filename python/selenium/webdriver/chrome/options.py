"""Chrome options, at the Selenium 4.x import path
``from selenium.webdriver.chrome.options import Options``.

Matches the mainstream ``Options`` (a.k.a. ``webdriver.ChromeOptions``): collect
``--flags`` via ``add_argument``, experimental options via
``add_experimental_option``, a ``binary_location``, and arbitrary top-level caps
via ``set_capability``; ``to_capabilities()`` assembles the W3C caps dict with a
``goog:chromeOptions`` block, exactly as upstream. ``webdriver.Chrome(options=...)``
in this binding applies ``to_capabilities()``.
"""
from __future__ import annotations

from ..common.options import ArgOptions


class Options(ArgOptions):
    """Chrome/Chromium options. Also exported as ``webdriver.ChromeOptions``."""

    KEY = "goog:chromeOptions"

    def __init__(self) -> None:
        super().__init__()
        self._binary_location: str = ""
        self._extensions: list[str] = []
        self._experimental_options: dict = {}
        self._debugger_address: str | None = None

    @property
    def binary_location(self) -> str:
        """Path to the Chrome/Chromium binary (empty if unset)."""
        return self._binary_location

    @binary_location.setter
    def binary_location(self, value: str) -> None:
        if not isinstance(value, str):
            raise TypeError(self.BINARY_LOCATION_ERROR)
        self._binary_location = value

    @property
    def debugger_address(self) -> str | None:
        """Address (host[:port]) of a remote devtools instance to attach to."""
        return self._debugger_address

    @debugger_address.setter
    def debugger_address(self, value: str) -> None:
        if not isinstance(value, str):
            raise TypeError("Debugger Address must be a string")
        self._debugger_address = value

    @property
    def experimental_options(self) -> dict:
        """The accumulated experimental options."""
        return self._experimental_options

    def add_experimental_option(self, name: str, value) -> None:
        """Set an experimental option passed to Chrome under ``goog:chromeOptions``."""
        self._experimental_options[name] = value

    def to_capabilities(self) -> dict:
        """Assemble the W3C capabilities dict, including the ``goog:chromeOptions``
        block (args, binary, experimental options, debuggerAddress)."""
        caps = self._caps
        chrome_options = self.experimental_options.copy()
        if self.mobile_options:
            chrome_options.update(self.mobile_options)
        chrome_options["extensions"] = self._extensions
        if self.binary_location:
            chrome_options["binary"] = self.binary_location
        chrome_options["args"] = self._arguments
        if self.debugger_address:
            chrome_options["debuggerAddress"] = self.debugger_address
        caps[self.KEY] = chrome_options
        return caps

    @property
    def default_capabilities(self) -> dict:
        return {"browserName": "chrome"}


__all__ = ["Options"]
