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
    CLASS_NAME = "class name"
    TAG_NAME = "tag name"
    LINK_TEXT = "link text"
    PARTIAL_LINK_TEXT = "partial link text"
    XPATH = "xpath"


class WebDriverException(Exception):
    """Base for all remote-end errors, matching the Selenium/W3C error taxonomy.

    Signature mirrors mainstream Selenium (``msg``, ``screen``, ``stacktrace``) so
    an unmodified upstream script constructs and inspects these the same way. This
    binding additionally records the engine's integer ``code`` (also exposed as
    ``w3c_code``) — the seam passes it as the ``code`` keyword.
    """

    def __init__(self, msg=None, screen=None, stacktrace=None, code: int = 0):
        super().__init__(msg)
        self.msg = msg
        self.screen = screen
        self.stacktrace = stacktrace
        self.w3c_code = code

    def __str__(self) -> str:
        exception_msg = f"Message: {self.msg}\n"
        if self.screen:
            exception_msg += "Screenshot: available via screen\n"
        if self.stacktrace:
            stacktrace = "\n".join(self.stacktrace)
            exception_msg += f"Stacktrace:\n{stacktrace}"
        return exception_msg


# ---- W3C / Selenium exception taxonomy (upstream selenium.common.exceptions) ----
# Base classes and hierarchy match mainstream so `except NoSuchFrameException` and
# the broader `except InvalidSwitchToTargetException` both behave identically.


class InvalidSwitchToTargetException(WebDriverException):
    """Frame or window target to be switched doesn't exist."""


class NoSuchWindowException(InvalidSwitchToTargetException):
    """Window target to be switched doesn't exist."""


class NoSuchFrameException(InvalidSwitchToTargetException):
    """Frame target to be switched doesn't exist."""


class NoSuchElementException(WebDriverException):
    pass


class NoSuchAttributeException(WebDriverException):
    """The attribute of element could not be found."""


class NoSuchShadowRootException(WebDriverException):
    """The element does not have a shadow root attached."""


class StaleElementReferenceException(WebDriverException):
    pass


class InvalidElementStateException(WebDriverException):
    """A command could not be completed because the element is in an invalid state."""


class UnexpectedAlertPresentException(WebDriverException):
    """An unexpected alert has appeared."""

    def __init__(self, msg=None, screen=None, stacktrace=None, alert_text=None, code: int = 0):
        super().__init__(msg, screen, stacktrace, code)
        self.alert_text = alert_text

    def __str__(self) -> str:
        return f"Alert Text: {self.alert_text}\n{super().__str__()}"


class NoAlertPresentException(WebDriverException):
    """Switching to an alert that is not present."""


class ElementNotVisibleException(InvalidElementStateException):
    """The element is present on the DOM but not visible."""


class ElementNotInteractableException(InvalidElementStateException):
    """Element interactions will hit another element due to paint order."""


class ElementNotSelectableException(InvalidElementStateException):
    """Trying to select an unselectable element."""


class InvalidCookieDomainException(WebDriverException):
    """Adding a cookie under a different domain."""


class UnableToSetCookieException(WebDriverException):
    """A driver failed to set a cookie."""


class TimeoutException(WebDriverException):
    pass


class MoveTargetOutOfBoundsException(WebDriverException):
    """The move() target is out of document bounds."""


class UnexpectedTagNameException(WebDriverException):
    """A support class did not get an expected web element."""


class InvalidSelectorException(WebDriverException):
    pass


class ImeNotAvailableException(WebDriverException):
    """IME support is not available."""


class ImeActivationFailedException(WebDriverException):
    """Activating an IME engine failed."""


class InvalidArgumentException(WebDriverException):
    """The arguments passed to a command are invalid or malformed."""


class JavascriptException(WebDriverException):
    pass


class NoSuchCookieException(WebDriverException):
    """No cookie matching the given path name was found."""


class ScreenshotException(WebDriverException):
    """A screen capture was made impossible."""


class ElementClickInterceptedException(WebDriverException):
    pass


class InsecureCertificateException(WebDriverException):
    """The user agent hit a certificate warning."""


class InvalidCoordinatesException(WebDriverException):
    """The coordinates provided to an interaction are invalid."""


class InvalidSessionIdException(WebDriverException):
    """The given session id is not in the list of active sessions."""


class SessionNotCreatedException(WebDriverException):
    pass


class UnknownMethodException(WebDriverException):
    """The command matched a known URL but no method for that URL."""


class NoSuchDriverException(WebDriverException):
    """Driver is not specified and cannot be located."""


class DetachedShadowRootException(WebDriverException):
    """The referenced shadow root is no longer attached to the DOM."""


class UnknownCommandException(WebDriverException):
    pass


# The engine's integer error codes (selenium.error_code) -> exception type.
# Codes not listed map to the base WebDriverException.
_CODE_TO_EXC = {
    3: ElementClickInterceptedException,
    4: ElementNotInteractableException,
    11: InvalidSelectorException,
    13: JavascriptException,
    17: NoSuchElementException,
    18: NoSuchFrameException,
    20: NoSuchWindowException,
    21: TimeoutException,
    22: SessionNotCreatedException,
    23: StaleElementReferenceException,
    24: TimeoutException,
    28: UnknownCommandException,
}


def _raise_for(code: int, message: str) -> None:
    exc = _CODE_TO_EXC.get(code, WebDriverException)
    raise exc(message, code=code)


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

    def send_keys(self, *value: str) -> None:
        """Type into the element. Variadic (mainstream): accepts multiple strings
        and :class:`Keys` constants, joined into one keystroke sequence. W3C
        expects {"text": full, "value": [chars...]} — send both for broad driver
        compatibility."""
        chars = _keys_to_typing(value)
        self._exec("sendKeysToElement", {"text": "".join(chars), "value": chars})

    def submit(self) -> None:
        """Submit the form containing this element (mainstream: walks up to the
        enclosing <form> and dispatches submit, in-page)."""
        script = (
            "/* submitForm */var form = arguments[0];\n"
            'while (form.nodeName != "FORM" && form.parentNode) {\n'
            "  form = form.parentNode;\n"
            "}\n"
            "if (!form) { throw Error('Unable to find containing form element'); }\n"
            "if (!form.ownerDocument) { throw Error('Unable to find owning document'); }\n"
            "var e = form.ownerDocument.createEvent('Event');\n"
            "e.initEvent('submit', true, true);\n"
            "if (form.dispatchEvent(e)) { HTMLFormElement.prototype.submit.call(form) }\n"
        )
        try:
            self._driver.execute_script(script, self)
        except JavascriptException as exc:
            raise WebDriverException(
                "To submit an element, it must be nested inside a form element"
            ) from exc

    @property
    def text(self) -> str:
        return self._exec("getElementText")

    @property
    def tag_name(self) -> str:
        return self._exec("getElementTagName")

    @property
    def aria_role(self) -> str:
        """The computed ARIA role of the element."""
        return self._exec("getAriaRole")

    @property
    def accessible_name(self) -> str:
        """The computed accessible name of the element."""
        return self._exec("getAccessibleName")

    def is_displayed(self) -> bool:
        """Whether the element is shown (the isDisplayed atom, run in-page by the
        engine — the visibility algorithm, not a naive style check)."""
        return bool(self._driver._atom_bool("is_displayed", self._id))

    def get_attribute(self, name: str) -> Any:
        """The classic getAttribute(name): property-or-attribute (boolean attrs,
        live properties like value/checked), via the shared engine atom. Use
        get_dom_attribute() for the raw W3C DOM attribute."""
        return self._driver._atom_get_attribute(self._id, name)

    def get_dom_attribute(self, name: str) -> Any:
        """The literal DOM attribute (W3C getDomAttribute), no property fallback."""
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

    @property
    def location(self) -> dict:
        """The element's {"x","y"} position in the renderable canvas."""
        r = self._exec("getElementRect")
        return {"x": r["x"], "y": r["y"]}

    @property
    def size(self) -> dict:
        """The element's {"height","width"}."""
        r = self._exec("getElementRect")
        return {"height": r["height"], "width": r["width"]}

    @property
    def screenshot_as_base64(self) -> str:
        """A base64-encoded PNG screenshot of this element (mainstream: property)."""
        return self._exec("takeElementScreenshot")

    @property
    def screenshot_as_png(self) -> bytes:
        """This element's screenshot as raw PNG bytes."""
        import base64
        return base64.b64decode(self.screenshot_as_base64.encode("ascii"))

    def screenshot(self, filename) -> bool:
        """Save this element's PNG screenshot to ``filename``. Returns False on
        an OSError writing the file, else True."""
        png = self.screenshot_as_png
        try:
            with open(filename, "wb") as f:
                f.write(png)
        except OSError:
            return False
        finally:
            del png
        return True

    def find_element(self, by: str = By.ID, value: str | None = None) -> "WebElement":
        loc = _decode_by(by, value)
        loc["id"] = self._id
        result = self._driver._execute("findChildElement", loc)
        return WebElement(self._driver, result[_W3C_ELEMENT_KEY])

    def find_elements(self, by: str = By.ID, value: str | None = None) -> list["WebElement"]:
        loc = _decode_by(by, value)
        loc["id"] = self._id
        result = self._driver._execute("findChildElements", loc)
        return [WebElement(self._driver, e[_W3C_ELEMENT_KEY]) for e in result]

    def __eq__(self, other):
        return isinstance(other, WebElement) and other._id == self._id

    def __repr__(self):
        return f"<WebElement id={self._id!r}>"


def _wrap_args(args):
    """Serialize execute_script args, encoding any WebElement as its W3C
    element-reference object so the engine forwards a live element handle."""
    def enc(a):
        if isinstance(a, WebElement):
            return {_W3C_ELEMENT_KEY: a.id}
        if isinstance(a, (list, tuple)):
            return [enc(x) for x in a]
        if isinstance(a, dict):
            return {k: enc(v) for k, v in a.items()}
        return a
    return [enc(a) for a in args]


def _keys_to_typing(value) -> list[str]:
    """Flatten send_keys args into a list of single characters — the mainstream
    ``keys_to_typing``: strings splat into chars, ints/floats stringify."""
    chars: list[str] = []
    for val in value:
        if isinstance(val, (int, float)):
            chars.extend(str(val))
        else:
            chars.extend(val)
    return chars


def _decode_by(by: str, value: str) -> dict:
    """Ask the engine for the {"using","value"} locator (shares the ONE By
    normalization + CSS-escape path with every other binding)."""
    raw = _native.take_string(_native.by_locator(_native.encode(by), _native.encode(value)))
    return json.loads(raw)


class WebDriver:
    """A WebDriver session. Construct with a remote-end URL and capabilities,
    or use :func:`Chrome` / :func:`Remote` helpers."""

    def __init__(self, command_executor: str, capabilities: dict | None = None,
                 ca_path: str | None = None, insecure: bool = False):
        self._handle = _native.open(_native.encode(command_executor))
        # TLS trust config must land on the handle BEFORE newSession (the first
        # request). ca_path pins a private-CA bundle; insecure skips verification
        # entirely (self-signed dev/staging Grid — trust the host out-of-band).
        if ca_path:
            _native.set_ca(self._handle, _native.encode(ca_path))
        if insecure:
            _native.set_insecure(self._handle, 1)
        caps = capabilities or {"browserName": "chrome"}
        # Request a BiDi channel so `.bidi` is available on demand; the channel
        # itself is opened lazily (a classic script never opens the WebSocket).
        caps = {**caps, "webSocketUrl": True}
        # W3C newSession envelope: {"capabilities": {"alwaysMatch": {...}}}
        payload = {"capabilities": {"alwaysMatch": caps}}
        result = self._execute("newSession", payload)
        # value.capabilities.webSocketUrl — the BiDi endpoint for this session.
        self._ws_url = ""
        self._caps: dict = {}
        if isinstance(result, dict):
            self._caps = result.get("capabilities") or {}
            self._ws_url = self._caps.get("webSocketUrl", "") or ""
        self._bidi: "BiDi | None" = None
        self._switch_to = SwitchTo(self)

    # ---- the FFI seam ----

    def execute(self, driver_command: str, params: dict | None = None) -> Any:
        """Issue a W3C command by name and return its parsed value — mainstream's
        documented low-level entrypoint. Public alias of the FFI seam
        :meth:`_execute` (the engine already unwraps the ``{"value": ...}``
        envelope, so this returns the value directly)."""
        return self._execute(driver_command, params)

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
                raise WebDriverException(message or "transport failure", code=-1)
            _raise_for(code, message)
        raw = _native.take_string(_native.last_value(self._handle))
        if raw == "":
            return None
        return json.loads(raw)

    # ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

    def _atom_result(self, rc: int) -> Any:
        """Drain the last_value after an atom call, raising a typed error on rc!=0."""
        if rc != 0:
            code = _native.last_error_code(self._handle)
            message = _native.take_string(_native.last_error(self._handle))
            if rc == -1 and code == 0:
                raise WebDriverException(message or "transport failure", code=-1)
            _raise_for(code, message)
        raw = _native.take_string(_native.last_value(self._handle))
        return None if raw == "" else json.loads(raw)

    def _atom_bool(self, verb: str, element_id: str) -> bool:
        fn = getattr(_native, verb)
        return bool(self._atom_result(fn(self._handle, _native.encode(element_id))))

    def _atom_get_attribute(self, element_id: str, name: str) -> Any:
        rc = _native.get_attribute(
            self._handle, _native.encode(element_id), _native.encode(name)
        )
        return self._atom_result(rc)

    def find_relative(self, base_css: str, *filters: dict) -> list["WebElement"]:
        """Relative locators: elements matching ``base_css`` filtered by spatial
        relation to anchors, nearest first. Each filter is a dict
        ``{"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"}``
        (``near`` also accepts ``"dist"``). Returns a list of WebElement."""
        rc = _native.find_relative(
            self._handle, _native.encode(base_css), _native.encode(json.dumps(list(filters)))
        )
        result = self._atom_result(rc)
        refs = result or []
        return [WebElement(self, r[_W3C_ELEMENT_KEY]) for r in refs]

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

    def find_element(self, by: str = By.ID, value: str | None = None) -> WebElement:
        result = self._execute("findElement", _decode_by(by, value))
        return WebElement(self, result[_W3C_ELEMENT_KEY])

    def find_elements(self, by: str = By.ID, value: str | None = None) -> list[WebElement]:
        result = self._execute("findElements", _decode_by(by, value))
        return [WebElement(self, e[_W3C_ELEMENT_KEY]) for e in result]

    # ---- script ----

    def execute_script(self, script: str, *args) -> Any:
        return self._execute("executeScript", {"script": script, "args": _wrap_args(args)})

    def execute_async_script(self, script: str, *args) -> Any:
        return self._execute("executeAsyncScript", {"script": script, "args": _wrap_args(args)})

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

    def set_window_size(self, width, height) -> None:
        """Set the current window's size (mainstream convenience over set_window_rect)."""
        self.set_window_rect(width=int(width), height=int(height))

    def get_window_size(self) -> dict:
        """The current window's {"width","height"}."""
        r = self.get_window_rect()
        return {k: r[k] for k in ("width", "height")}

    def set_window_position(self, x, y) -> dict:
        """Set the current window's top-left position."""
        return self.set_window_rect(x=int(x), y=int(y))

    def get_window_position(self) -> dict:
        """The current window's {"x","y"} top-left position."""
        r = self.get_window_rect()
        return {k: r[k] for k in ("x", "y")}

    # ---- switch_to facade ----

    @property
    def switch_to(self) -> "SwitchTo":
        """The mainstream focus-switching facade:
        ``driver.switch_to.window(h)`` / ``.frame(ref)`` / ``.parent_frame()`` /
        ``.default_content()`` / ``.new_window("tab")`` / ``.active_element`` /
        ``.alert``. The flat ``switch_to_window`` / ``accept_alert`` methods stay
        available for existing callers."""
        return self._switch_to

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

    # Timeouts take SECONDS and are sent as milliseconds on the wire — matching
    # mainstream Selenium-Python exactly (upstream: int(float(t) * 1000)). A
    # script's implicitly_wait(10) must mean 10 seconds, not 10 ms.
    def set_page_load_timeout(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"pageLoad": int(float(time_to_wait) * 1000)})

    def set_script_timeout(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"script": int(float(time_to_wait) * 1000)})

    def implicitly_wait(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"implicit": int(float(time_to_wait) * 1000)})

    # ---- screenshots / print ----

    def get_screenshot_as_base64(self) -> str:
        return self._execute("screenshot")

    def get_screenshot_as_png(self) -> bytes:
        """The current window's screenshot as raw PNG bytes."""
        import base64
        return base64.b64decode(self.get_screenshot_as_base64().encode("ascii"))

    def get_screenshot_as_file(self, filename) -> bool:
        """Save a PNG screenshot of the current window to ``filename``. Returns
        False on an OSError writing the file, else True."""
        png = self.get_screenshot_as_png()
        try:
            with open(filename, "wb") as f:
                f.write(png)
        except OSError:
            return False
        finally:
            del png
        return True

    def save_screenshot(self, filename) -> bool:
        """Alias of :meth:`get_screenshot_as_file` (mainstream)."""
        return self.get_screenshot_as_file(filename)

    def print_page(self, print_options=None) -> str:
        """Render the current page to a PDF, returned base64-encoded.
        ``print_options`` may be a mapping (or an object with ``to_dict()``) of
        the W3C print parameters."""
        options: dict = {}
        if print_options is not None:
            options = print_options.to_dict() if hasattr(print_options, "to_dict") else dict(print_options)
        return self._execute("printPage", options)

    # ---- session metadata ----

    @property
    def name(self) -> str:
        """The browserName of the underlying browser for this session."""
        caps = self._caps or {}
        if "browserName" in caps:
            return caps["browserName"]
        raise KeyError("browserName not specified in session capabilities")

    @property
    def capabilities(self) -> dict:
        """The session capabilities the remote end returned."""
        return self._caps

    def __repr__(self) -> str:
        return f'<{type(self).__module__}.{type(self).__name__} (session="{self.session_id}")>'

    # ---- lifecycle ----

    @property
    def session_id(self) -> str:
        return _native.take_string(_native.session_id(self._handle))

    # ---- WebDriver-BiDi ----

    @property
    def bidi(self) -> "BiDi":
        """The event-driven BiDi surface for this session (lazily opened over the
        negotiated webSocketUrl). Raises if the remote end granted no BiDi URL.

            driver.bidi.subscribe("log.entryAdded")
            driver.get(url)
            ev = driver.bidi.next_event("log.entryAdded", timeout_ms=5000)
        """
        if self._bidi is None:
            if not self._ws_url:
                raise WebDriverException(
                    "BiDi not available: the session negotiated no webSocketUrl", code=0
                )
            handle = _native.bidi_open(_native.encode(self._ws_url))
            if not handle:
                raise WebDriverException("BiDi channel failed to open", code=-1)
            self._bidi = BiDi(handle)
        return self._bidi

    @property
    def bidi_available(self) -> bool:
        """True if this session can use BiDi (a webSocketUrl was negotiated)."""
        return bool(self._ws_url)

    def quit(self) -> None:
        try:
            if self._bidi is not None:
                self._bidi.close()
                self._bidi = None
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


class SwitchTo:
    """The mainstream focus-switching facade reached via ``driver.switch_to``.

    Each method issues the matching W3C command through this binding's engine
    seam. The flat driver methods (``switch_to_window``, ``accept_alert``, …)
    remain the underlying calls, so both styles coexist."""

    def __init__(self, driver: "WebDriver"):
        import weakref
        self._driver = weakref.proxy(driver)

    @property
    def active_element(self) -> "WebElement":
        """The element with focus (or BODY if nothing has focus)."""
        result = self._driver._execute("getActiveElement")
        return WebElement(self._driver, result[_W3C_ELEMENT_KEY])

    @property
    def alert(self) -> "Alert":
        """The open alert/confirm/prompt. Touches its text (raising
        NoAlertPresentException-style errors if none is present), as mainstream."""
        alert = Alert(self._driver)
        _ = alert.text
        return alert

    def default_content(self) -> None:
        """Switch focus back to the top-level document."""
        self._driver._execute("switchToFrame", {"id": None})

    def frame(self, frame_reference) -> None:
        """Switch to a frame by index, name/id (looked up as element), or a
        frame WebElement."""
        if isinstance(frame_reference, str):
            try:
                frame_reference = self._driver.find_element(By.ID, frame_reference)
            except NoSuchElementException:
                try:
                    frame_reference = self._driver.find_element(By.NAME, frame_reference)
                except NoSuchElementException as exc:
                    raise NoSuchFrameException(frame_reference) from exc
        if isinstance(frame_reference, WebElement):
            frame_reference = {_W3C_ELEMENT_KEY: frame_reference.id}
        self._driver._execute("switchToFrame", {"id": frame_reference})

    def new_window(self, type_hint: str = "tab") -> None:
        """Open and switch to a new top-level context ("tab" or "window")."""
        value = self._driver._execute("newWindow", {"type": type_hint})
        self._driver._execute("switchToWindow", {"handle": value["handle"]})

    def parent_frame(self) -> None:
        """Switch to the parent of the current frame."""
        self._driver._execute("switchToFrameParent")

    def window(self, window_name: str) -> None:
        """Switch to the window/tab with the given handle."""
        self._driver._execute("switchToWindow", {"handle": window_name})


class Alert:
    """A JavaScript alert/confirm/prompt handle, reached via
    ``driver.switch_to.alert``. Mirrors mainstream ``selenium...common.alert.Alert``."""

    def __init__(self, driver: "WebDriver"):
        self.driver = driver

    @property
    def text(self) -> str:
        """The alert's message text."""
        return self.driver._execute("getAlertText")

    def dismiss(self) -> None:
        """Dismiss (cancel) the alert."""
        self.driver._execute("dismissAlert")

    def accept(self) -> None:
        """Accept (OK) the alert."""
        self.driver._execute("acceptAlert")

    def send_keys(self, keysToSend: str) -> None:
        """Type into a prompt's input field."""
        self.driver._execute(
            "setAlertValue", {"text": keysToSend, "value": list(keysToSend)}
        )


class BidiEvent:
    """The common WebDriver-BiDi event names (W3C spec). Pass to
    ``driver.bidi.subscribe(...)`` and match in ``next_event(...)``."""

    LOG_ENTRY_ADDED = "log.entryAdded"
    CONTEXT_CREATED = "browsingContext.contextCreated"
    CONTEXT_DESTROYED = "browsingContext.contextDestroyed"
    NAVIGATION_STARTED = "browsingContext.navigationStarted"
    DOM_CONTENT_LOADED = "browsingContext.domContentLoaded"
    LOAD = "browsingContext.load"
    DOWNLOAD_WILL_BEGIN = "browsingContext.downloadWillBegin"
    BEFORE_REQUEST_SENT = "network.beforeRequestSent"
    AUTH_REQUIRED = "network.authRequired"
    RESPONSE_STARTED = "network.responseStarted"
    RESPONSE_COMPLETED = "network.responseCompleted"
    FETCH_ERROR = "network.fetchError"
    REALM_CREATED = "script.realmCreated"
    REALM_DESTROYED = "script.realmDestroyed"
    MESSAGE = "script.message"


class BiDi:
    """The event-driven BiDi channel for a session (over the demux C ABI).

    Commands and events multiplex over one WebSocket via the engine's shape-C
    demux (a single reader routes replies to an id table and events to a bounded
    queue), so replies stay correlated while events stream. Command ids are
    supplied automatically."""

    def __init__(self, handle):
        self._handle = handle
        self._next_id = 1

    def _id(self) -> int:
        i = self._next_id
        self._next_id += 1
        return i

    def subscribe(self, *events: str, timeout_ms: int = 10000) -> dict:
        """session.subscribe to one or more event names; wait for the ack.
        Returns the ack payload. After this, matching events arrive on the
        queue (drain via :meth:`next_event`)."""
        csv = ",".join(events)
        raw = _native.take_string(
            _native.bidi_subscribe(self._handle, self._id(), _native.encode(csv), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def unsubscribe(self, *events: str, timeout_ms: int = 10000) -> dict:
        csv = ",".join(events)
        raw = _native.take_string(
            _native.bidi_unsubscribe(self._handle, self._id(), _native.encode(csv), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def next_event(self, method: str, timeout_ms: int = 5000) -> dict | None:
        """Block until an event whose ``method`` matches arrives, or timeout.
        Returns the event dict, or ``None`` on timeout/close. (Subscribe first.)"""
        raw = _native.take_string(
            _native.bidi_wait_event(self._handle, _native.encode(method), timeout_ms)
        )
        return json.loads(raw) if raw else None

    def command(self, method: str, params: dict | None = None, timeout_ms: int = 10000) -> dict:
        """Issue any BiDi command and return its reply payload. Lets a caller
        reach BiDi methods with no dedicated wrapper (script.evaluate,
        browsingContext.captureScreenshot, network.*, …)."""
        params_json = json.dumps(params or {})
        # send + pump until this id's reply arrives (the engine's convenience).
        cid = self._id()
        if _native.bidi_send(self._handle, cid, _native.encode(method), _native.encode(params_json)) != 0:
            raise WebDriverException(f"BiDi send failed: {method}", code=-1)
        waited, step = 0, 50
        while waited < timeout_ms:
            reply = _native.take_string(_native.bidi_poll_reply(self._handle, cid))
            if reply:
                return json.loads(reply)
            if _native.bidi_pump(self._handle, step) < 0:
                break
            waited += step
        raise TimeoutException(f"BiDi command timed out: {method}", code=0)

    # ---- typed convenience commands ----

    def get_tree(self, timeout_ms: int = 10000) -> dict:
        """browsingContext.getTree — the browsing contexts (each with a "context" id)."""
        raw = _native.take_string(_native.bidi_get_tree(self._handle, self._id(), timeout_ms))
        return json.loads(raw) if raw else {}

    def top_context(self, timeout_ms: int = 10000) -> str | None:
        """The top-level browsing context id (the anchor for evaluate/navigate)."""
        contexts = (self.get_tree(timeout_ms).get("result") or {}).get("contexts") or []
        return contexts[0]["context"] if contexts else None

    def evaluate(self, expression: str, context: str | None = None, timeout_ms: int = 30000) -> dict:
        """script.evaluate an expression in a context's realm, awaiting a returned
        promise. Returns the reply; ``["result"]["result"]`` is the BiDi-typed value
        (e.g. {"type": "number", "value": 42}). BiDi's richer alternative to
        execute_script — real realms, promise-awaiting, structured value types."""
        ctx = context or self.top_context(timeout_ms)
        if not ctx:
            raise WebDriverException("no browsing context for script.evaluate", code=0)
        raw = _native.take_string(
            _native.bidi_script_evaluate(self._handle, self._id(),
                                         _native.encode(expression), _native.encode(ctx), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def evaluate_value(self, expression: str, context: str | None = None, timeout_ms: int = 30000):
        """script.evaluate, returning just the unwrapped value (the ``.value`` of the
        BiDi-typed result), or None if it wasn't a simple value."""
        result = self.evaluate(expression, context, timeout_ms).get("result") or {}
        inner = result.get("result") or {}
        return inner.get("value")

    def navigate(self, url: str, context: str | None = None, timeout_ms: int = 30000) -> dict:
        """browsingContext.navigate a context to url (wait: complete)."""
        ctx = context or self.top_context(timeout_ms)
        if not ctx:
            raise WebDriverException("no browsing context for navigate", code=0)
        raw = _native.take_string(
            _native.bidi_navigate(self._handle, self._id(),
                                  _native.encode(ctx), _native.encode(url), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    # ---- network interception (observe / release / block requests) ----

    def add_intercept(self, *, phases: str = "beforeRequestSent", url_pattern: str = "",
                      timeout_ms: int = 10000) -> str | None:
        """network.addIntercept for a URL pattern (a full parseable URL as a
        "string" pattern; empty intercepts all) at the given comma-separated
        phases. Subscribe to the matching network.* event first if you want the
        paused-request events. Returns the intercept id, or None."""
        raw = _native.take_string(
            _native.bidi_network_add_intercept(self._handle, self._id(),
                                               _native.encode(phases), _native.encode(url_pattern), timeout_ms)
        )
        reply = json.loads(raw) if raw else {}
        return (reply.get("result") or {}).get("intercept")

    def remove_intercept(self, intercept_id: str, timeout_ms: int = 10000) -> dict:
        raw = _native.take_string(
            _native.bidi_network_remove_intercept(self._handle, self._id(),
                                                  _native.encode(intercept_id), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def continue_request(self, request_id: str, timeout_ms: int = 10000) -> dict:
        """Let a paused (intercepted) request proceed unchanged. request_id comes
        from a network event's ``params.request.request``."""
        raw = _native.take_string(
            _native.bidi_network_continue_request(self._handle, self._id(),
                                                  _native.encode(request_id), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def fail_request(self, request_id: str, timeout_ms: int = 10000) -> dict:
        """Block a paused request (the ad/tracker-blocking case)."""
        raw = _native.take_string(
            _native.bidi_network_fail_request(self._handle, self._id(),
                                              _native.encode(request_id), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def provide_response(self, request_id: str, *, status: int = 200,
                         content_type: str = "", body: str = "", timeout_ms: int = 10000) -> dict:
        """Fulfill a paused request with a MOCK response (network.provideResponse),
        never hitting the network — mock an API, serve stub content, or test an
        error status. The mock auto-allows any origin to read the body."""
        raw = _native.take_string(
            _native.bidi_network_provide_response(
                self._handle, self._id(), _native.encode(request_id), status,
                _native.encode(content_type), _native.encode(body), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def continue_with_auth(self, request_id: str, username: str, password: str, timeout_ms: int = 10000) -> dict:
        """Answer an HTTP auth challenge (a paused authRequired request) with
        credentials — automates basic/digest auth that classic WebDriver can't
        handle in headless."""
        raw = _native.take_string(
            _native.bidi_network_continue_with_auth(
                self._handle, self._id(), _native.encode(request_id),
                _native.encode(username), _native.encode(password), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    def set_cache_behavior(self, behavior: str = "bypass", timeout_ms: int = 10000) -> dict:
        """Set the session HTTP cache behavior: "bypass" to disable it (so every
        request hits the network / an intercept), "default" to restore it."""
        raw = _native.take_string(
            _native.bidi_network_set_cache_behavior(
                self._handle, self._id(), _native.encode(behavior), timeout_ms)
        )
        return json.loads(raw) if raw else {}

    @staticmethod
    def event_request_id(event: dict) -> str | None:
        """The network.request id out of a network.beforeRequestSent (or other
        network) event: ``params.request.request``."""
        return ((event.get("params") or {}).get("request") or {}).get("request")

    def lost_events(self) -> int:
        """How many events the bounded queue has dropped since the last call
        (then resets) — so a consumer knows it missed events."""
        return _native.bidi_lost_events(self._handle)

    def close(self) -> None:
        if self._handle:
            _native.bidi_close(self._handle)
            self._handle = None


def _options_to_caps(options) -> dict:
    """Normalize a Chrome ``options`` argument to a capabilities dict. Accepts a
    mainstream ``ChromeOptions`` object (any object exposing ``to_capabilities``)
    or a raw capabilities dict (back-compat), or None."""
    if options is None:
        return {}
    if hasattr(options, "to_capabilities"):
        return dict(options.to_capabilities())
    return dict(options)


def Chrome(command_executor: str | None = None, options=None,
           ca_path: str | None = None, insecure: bool = False) -> WebDriver:
    """A Chrome session, matching ``webdriver.Chrome()`` in Selenium 4.x.

    With no ``command_executor`` the engine resolves and launches its own
    chromedriver (no driver on PATH, no Grid) — a :class:`LocalChrome`. Pass a
    URL to drive an already-running chromedriver instead. ``options`` may be a
    mainstream :class:`ChromeOptions` object (``.to_capabilities()`` is applied)
    or a raw capabilities dict (back-compat), merged under ``browserName: chrome``."""
    if command_executor is None:
        return LocalChrome(options=options, ca_path=ca_path, insecure=insecure)
    caps = {"browserName": "chrome"}
    caps.update(_options_to_caps(options))
    return WebDriver(command_executor, caps, ca_path=ca_path, insecure=insecure)


def Remote(command_executor: str, capabilities: dict) -> WebDriver:
    """A session against an arbitrary remote end / Grid hub with explicit caps."""
    return WebDriver(command_executor, capabilities)


# ---- driver orchestration (spawn / adopt a driver process in-binding) --------
# The engine can resolve, download-or-cache, and launch a browser driver process
# itself — so a caller needs neither a driver on PATH nor a running Grid. These
# wrap the driver-handle C ABI (independent of the W3C session handle).


def resolve_driver(browser: str = "chrome", hint: str = "") -> str:
    """Resolve the local driver binary path for ``browser`` without launching it
    (detect/download/cache as needed). ``hint`` pins a version or path; ""
    auto-detects. Returns "" if none resolvable (offline, no cache)."""
    return _native.take_string(
        _native.resolve_driver(_native.encode(browser), _native.encode(hint)))


class DriverProcess:
    """A driver process launched by the engine. Owns the driver handle; call
    :meth:`stop` (or use as a context manager) to terminate it."""

    def __init__(self, handle):
        self._handle = handle

    @property
    def url(self) -> str:
        """The base URL the driver is listening on — pass to :class:`WebDriver`."""
        return _native.take_string(_native.driver_url(self._handle)) if self._handle else ""

    @property
    def pid(self) -> int:
        """The driver process id (0 if not running)."""
        return _native.driver_pid(self._handle) if self._handle else 0

    def stop(self) -> None:
        if self._handle:
            _native.stop_driver(self._handle)
            self._handle = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.stop()


def launch_driver(driver_path: str, timeout_ms: int = 15000) -> DriverProcess | None:
    """Launch a driver at an explicit binary path. Returns a :class:`DriverProcess`,
    or None if it did not come up in ``timeout_ms``."""
    h = _native.launch_driver(_native.encode(driver_path), timeout_ms)
    return DriverProcess(h) if h else None


def ensure_driver(browser: str = "chrome", hint: str = "", timeout_ms: int = 15000) -> DriverProcess | None:
    """Resolve (detect/download/cache) AND launch a driver for ``browser`` in one
    step. Returns a running :class:`DriverProcess`, or None if none could be
    resolved/launched."""
    h = _native.ensure_driver(_native.encode(browser), _native.encode(hint), timeout_ms)
    return DriverProcess(h) if h else None


class LocalChrome(WebDriver):
    """A Chrome session that spawns its own chromedriver via the engine — no
    driver on PATH, no Grid. The driver process is stopped on :meth:`quit`.

    Returns nothing special if the driver can't be resolved: raises
    :class:`WebDriverException`."""

    def __init__(self, options=None, hint: str = "", timeout_ms: int = 15000,
                 ca_path: str | None = None, insecure: bool = False):
        proc = ensure_driver("chrome", hint, timeout_ms)
        if proc is None:
            raise WebDriverException("could not resolve/launch chromedriver", code=-1)
        self._proc = proc
        caps = {"browserName": "chrome"}
        caps.update(_options_to_caps(options))
        super().__init__(proc.url, caps, ca_path=ca_path, insecure=insecure)

    def quit(self) -> None:
        try:
            super().quit()
        finally:
            self._proc.stop()
