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

import base64
import os

from ..common.options import ArgOptions


class Options(ArgOptions):
    """Chrome/Chromium options. Also exported as ``webdriver.ChromeOptions``."""

    KEY = "goog:chromeOptions"

    def __init__(self) -> None:
        super().__init__()
        self._binary_location: str = ""
        self._extensions: list[str] = []
        self._extension_files: list[str] = []
        self._experimental_options: dict = {}
        self._debugger_address: str | None = None
        self._enable_webextensions: bool = False

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
    def extensions(self) -> list[str]:
        """Every extension to load, base64-encoded — the ``.crx`` paths added via
        :meth:`add_extension` read at access time, plus any already-encoded ones."""
        encoded = []
        for path in self._extension_files:
            with open(path, "rb") as f:
                # Not encodestring(): it wraps at 76 chars (RFC 1521) and the
                # driver has to strip those newlines again before decoding.
                encoded.append(base64.b64encode(f.read()).decode("utf-8"))
        return encoded + self._extensions

    def add_extension(self, extension: str) -> None:
        """Load a packed extension from a ``.crx`` path."""
        if not extension:
            raise ValueError("argument can not be null")
        path = os.path.abspath(os.path.expanduser(extension))
        if not os.path.exists(path):
            raise OSError("Path to the extension doesn't exist")
        self._extension_files.append(path)

    def add_encoded_extension(self, extension: str) -> None:
        """Load an extension already supplied as a base64 string."""
        if not extension:
            raise ValueError("argument can not be null")
        self._extensions.append(extension)

    @property
    def enable_webextensions(self) -> bool:
        """Whether Chromium webextension support is enabled."""
        return self._enable_webextensions

    @enable_webextensions.setter
    def enable_webextensions(self, value: bool) -> None:
        """Toggle webextension support, adding (or removing) the Chromium flags
        it requires. Note that ``--remote-debugging-pipe`` moves the driver's
        browser connection onto a pipe, which disables much of CDP."""
        self._enable_webextensions = value
        required = ["--enable-unsafe-extension-debugging", "--remote-debugging-pipe"]
        for flag in required:
            if value:
                if flag not in self._arguments:
                    self.add_argument(flag)
            elif flag in self._arguments:
                self._arguments.remove(flag)

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
        chrome_options["extensions"] = self.extensions
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
