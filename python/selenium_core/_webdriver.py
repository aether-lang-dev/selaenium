"""The ergonomic Python WebDriver surface — a thin layer over the Aether core.

Carries NO protocol logic: the command catalog, route table, path templating,
By normalization and W3C error decode all live in the engine (``core/``). Every
command here is one ``_native.execute`` call plus JSON marshalling. This is the
Python-idiomatic face (``driver.get(url)``, ``driver.find_element(By.CSS, ...)``)
that a user touches.
"""

from __future__ import annotations

import json
from typing import Any

from . import _native

# The W3C element-reference key. A findElement result is
# {"element-6066-11e4-a52e-4f735466cecf": "<id>"}.
_W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"


class By:
    """Locator strategies. Values match the engine's ``by_locator`` strategy
    strings; id/name/class name are rewritten to CSS in the engine."""

    ID = "id"
    NAME = "name"
    CSS_SELECTOR = "css selector"
    CLASS_NAME = "className"
    TAG_NAME = "tag name"
    LINK_TEXT = "link text"
    PARTIAL_LINK_TEXT = "partial link text"
    XPATH = "xpath"


class WebDriverError(Exception):
    """Base for all remote-end errors, matching the W3C error taxonomy."""

    def __init__(self, msg: str = "", code: int = 0):
        super().__init__(msg)
        self.w3c_code = code


class NoSuchElementError(WebDriverError):
    pass


class StaleElementReferenceError(WebDriverError):
    pass


class ElementClickInterceptedError(WebDriverError):
    pass


class ElementNotInteractableError(WebDriverError):
    pass


class InvalidSelectorError(WebDriverError):
    pass


class NoSuchWindowError(WebDriverError):
    pass


class NoSuchFrameError(WebDriverError):
    pass


class TimeoutError_(WebDriverError):
    pass


class JavascriptError(WebDriverError):
    pass


class SessionNotCreatedError(WebDriverError):
    pass


class UnknownCommandError(WebDriverError):
    pass


# The engine's integer error codes (selenium_core.error_code) -> exception type.
# Codes not listed map to the base WebDriverError.
_CODE_TO_EXC = {
    3: ElementClickInterceptedError,
    4: ElementNotInteractableError,
    11: InvalidSelectorError,
    13: JavascriptError,
    17: NoSuchElementError,
    18: NoSuchFrameError,
    20: NoSuchWindowError,
    21: TimeoutError_,
    22: SessionNotCreatedError,
    23: StaleElementReferenceError,
    24: TimeoutError_,
    28: UnknownCommandError,
}


def _raise_for(code: int, message: str) -> None:
    exc = _CODE_TO_EXC.get(code, WebDriverError)
    raise exc(message, code)


class WebElement:
    """A remote element handle. Methods issue element-scoped commands via the
    engine, passing this element's id as the ``:id`` path parameter."""

    def __init__(self, driver: "WebDriver", element_id: str):
        self._driver = driver
        self._id = element_id

    @property
    def id(self) -> str:
        return self._id

    def _exec(self, command: str, params: dict | None = None) -> Any:
        p = dict(params or {})
        p["id"] = self._id
        return self._driver._execute(command, p)

    def click(self) -> None:
        self._exec("clickElement")

    def clear(self) -> None:
        self._exec("clearElement")

    def send_keys(self, text: str) -> None:
        # W3C expects {"text": full, "value": [chars...]} — send both for
        # broad driver compatibility.
        self._exec("sendKeysToElement", {"text": text, "value": list(text)})

    @property
    def text(self) -> str:
        return self._exec("getElementText")

    @property
    def tag_name(self) -> str:
        return self._exec("getElementTagName")

    def get_attribute(self, name: str) -> Any:
        # DOM attribute (W3C native endpoint). The atom-based getAttribute
        # (property-or-attribute) is a binding/engine follow-up.
        return self._exec("getDomAttribute", {"name": name})

    def get_property(self, name: str) -> Any:
        return self._exec("getElementProperty", {"name": name})

    def value_of_css_property(self, name: str) -> Any:
        return self._exec("getElementValueOfCssProperty", {"propertyName": name})

    def is_enabled(self) -> bool:
        return bool(self._exec("isElementEnabled"))

    def is_selected(self) -> bool:
        return bool(self._exec("isElementSelected"))

    @property
    def rect(self) -> dict:
        return self._exec("getElementRect")

    def screenshot_as_base64(self) -> str:
        return self._exec("takeElementScreenshot")

    def find_element(self, by: str, value: str) -> "WebElement":
        loc = _decode_by(by, value)
        loc["id"] = self._id
        result = self._driver._execute("findChildElement", loc)
        return WebElement(self._driver, result[_W3C_ELEMENT_KEY])

    def find_elements(self, by: str, value: str) -> list["WebElement"]:
        loc = _decode_by(by, value)
        loc["id"] = self._id
        result = self._driver._execute("findChildElements", loc)
        return [WebElement(self._driver, e[_W3C_ELEMENT_KEY]) for e in result]

    def __eq__(self, other):
        return isinstance(other, WebElement) and other._id == self._id

    def __repr__(self):
        return f"<WebElement id={self._id!r}>"


def _decode_by(by: str, value: str) -> dict:
    """Ask the engine for the {"using","value"} locator (shares the ONE By
    normalization + CSS-escape path with every other binding)."""
    raw = _native.take_string(_native.by_locator(_native.encode(by), _native.encode(value)))
    return json.loads(raw)


class WebDriver:
    """A WebDriver session. Construct with a remote-end URL and capabilities,
    or use :func:`Chrome` / :func:`Remote` helpers."""

    def __init__(self, command_executor: str, capabilities: dict | None = None):
        self._handle = _native.open(_native.encode(command_executor))
        caps = capabilities or {"browserName": "chrome"}
        # W3C newSession envelope: {"capabilities": {"alwaysMatch": {...}}}
        payload = {"capabilities": {"alwaysMatch": caps}}
        self._execute("newSession", payload)

    # ---- the FFI seam ----

    def _execute(self, command: str, params: dict | None = None) -> Any:
        params_json = json.dumps(params or {})
        rc = _native.execute(
            self._handle, _native.encode(command), _native.encode(params_json)
        )
        if rc != 0:
            code = _native.last_error_code(self._handle)
            message = _native.take_string(_native.last_error(self._handle))
            if rc == -1 and code == 0:
                # transport-level failure
                raise WebDriverError(message or "transport failure", -1)
            _raise_for(code, message)
        raw = _native.take_string(_native.last_value(self._handle))
        if raw == "":
            return None
        return json.loads(raw)

    # ---- navigation ----

    def get(self, url: str) -> None:
        self._execute("get", {"url": url})

    @property
    def current_url(self) -> str:
        return self._execute("getCurrentUrl")

    @property
    def title(self) -> str:
        return self._execute("getTitle")

    @property
    def page_source(self) -> str:
        return self._execute("getPageSource")

    def back(self) -> None:
        self._execute("goBack")

    def forward(self) -> None:
        self._execute("goForward")

    def refresh(self) -> None:
        self._execute("refresh")

    # ---- elements ----

    def find_element(self, by: str, value: str) -> WebElement:
        result = self._execute("findElement", _decode_by(by, value))
        return WebElement(self, result[_W3C_ELEMENT_KEY])

    def find_elements(self, by: str, value: str) -> list[WebElement]:
        result = self._execute("findElements", _decode_by(by, value))
        return [WebElement(self, e[_W3C_ELEMENT_KEY]) for e in result]

    # ---- script ----

    def execute_script(self, script: str, *args) -> Any:
        return self._execute("executeScript", {"script": script, "args": list(args)})

    def execute_async_script(self, script: str, *args) -> Any:
        return self._execute("executeAsyncScript", {"script": script, "args": list(args)})

    # ---- windows ----

    @property
    def window_handles(self) -> list[str]:
        return self._execute("getWindowHandles")

    @property
    def current_window_handle(self) -> str:
        return self._execute("getCurrentWindowHandle")

    def switch_to_window(self, handle: str) -> None:
        self._execute("switchToWindow", {"handle": handle})

    def maximize_window(self) -> None:
        self._execute("maximizeWindow")

    def minimize_window(self) -> None:
        self._execute("minimizeWindow")

    def fullscreen_window(self) -> None:
        self._execute("fullscreenWindow")

    def get_window_rect(self) -> dict:
        return self._execute("getWindowRect")

    def set_window_rect(self, x=None, y=None, width=None, height=None) -> dict:
        rect = {}
        if x is not None:
            rect["x"] = x
        if y is not None:
            rect["y"] = y
        if width is not None:
            rect["width"] = width
        if height is not None:
            rect["height"] = height
        return self._execute("setWindowRect", rect)

    # ---- cookies ----

    def add_cookie(self, cookie: dict) -> None:
        self._execute("addCookie", {"cookie": cookie})

    def get_cookies(self) -> list[dict]:
        return self._execute("getCookies")

    def get_cookie(self, name: str) -> dict:
        return self._execute("getCookie", {"name": name})

    def delete_cookie(self, name: str) -> None:
        self._execute("deleteCookie", {"name": name})

    def delete_all_cookies(self) -> None:
        self._execute("deleteAllCookies")

    # ---- alerts ----

    def accept_alert(self) -> None:
        self._execute("acceptAlert")

    def dismiss_alert(self) -> None:
        self._execute("dismissAlert")

    @property
    def alert_text(self) -> str:
        return self._execute("getAlertText")

    def send_alert_text(self, text: str) -> None:
        self._execute("setAlertValue", {"text": text})

    # ---- timeouts ----

    def set_page_load_timeout(self, ms: int) -> None:
        self._execute("setTimeout", {"pageLoad": ms})

    def set_script_timeout(self, ms: int) -> None:
        self._execute("setTimeout", {"script": ms})

    def implicitly_wait(self, ms: int) -> None:
        self._execute("setTimeout", {"implicit": ms})

    # ---- screenshots ----

    def get_screenshot_as_base64(self) -> str:
        return self._execute("screenshot")

    # ---- lifecycle ----

    @property
    def session_id(self) -> str:
        return _native.take_string(_native.session_id(self._handle))

    def quit(self) -> None:
        try:
            self._execute("quit")
        finally:
            self.close_handle()

    def close(self) -> None:
        """Close the current window (not the whole session)."""
        self._execute("close")

    def close_handle(self) -> None:
        if self._handle:
            _native.close(self._handle)
            self._handle = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.quit()


def Chrome(command_executor: str = "http://127.0.0.1:9515", options: dict | None = None) -> WebDriver:
    """Convenience: a Chrome session against a running chromedriver.

    ``options`` is a raw capabilities dict merged under ``browserName: chrome``
    (e.g. ``{"goog:chromeOptions": {"args": ["--headless=new"]}}``)."""
    caps = {"browserName": "chrome"}
    if options:
        caps.update(options)
    return WebDriver(command_executor, caps)


def Remote(command_executor: str, capabilities: dict) -> WebDriver:
    """A session against an arbitrary remote end / Grid hub with explicit caps."""
    return WebDriver(command_executor, capabilities)
