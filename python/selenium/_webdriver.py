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
    """Base for all remote-end errors, matching the Selenium/W3C error taxonomy."""

    def __init__(self, msg: str = "", code: int = 0):
        super().__init__(msg)
        self.w3c_code = code


class NoSuchElementException(WebDriverException):
    pass


class StaleElementReferenceException(WebDriverException):
    pass


class ElementClickInterceptedException(WebDriverException):
    pass


class ElementNotInteractableException(WebDriverException):
    pass


class InvalidSelectorException(WebDriverException):
    pass


class NoSuchWindowException(WebDriverException):
    pass


class NoSuchFrameException(WebDriverException):
    pass


class TimeoutException(WebDriverException):
    pass


class JavascriptException(WebDriverException):
    pass


class SessionNotCreatedException(WebDriverException):
    pass


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
        if isinstance(result, dict):
            self._ws_url = (result.get("capabilities") or {}).get("webSocketUrl", "") or ""
        self._bidi: "BiDi | None" = None

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
                raise WebDriverException(message or "transport failure", -1)
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
                raise WebDriverException(message or "transport failure", -1)
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

    # Timeouts take SECONDS and are sent as milliseconds on the wire — matching
    # mainstream Selenium-Python exactly (upstream: int(float(t) * 1000)). A
    # script's implicitly_wait(10) must mean 10 seconds, not 10 ms.
    def set_page_load_timeout(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"pageLoad": int(float(time_to_wait) * 1000)})

    def set_script_timeout(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"script": int(float(time_to_wait) * 1000)})

    def implicitly_wait(self, time_to_wait: float) -> None:
        self._execute("setTimeout", {"implicit": int(float(time_to_wait) * 1000)})

    # ---- screenshots ----

    def get_screenshot_as_base64(self) -> str:
        return self._execute("screenshot")

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
                    "BiDi not available: the session negotiated no webSocketUrl", 0
                )
            handle = _native.bidi_open(_native.encode(self._ws_url))
            if not handle:
                raise WebDriverException("BiDi channel failed to open", -1)
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
            raise WebDriverException(f"BiDi send failed: {method}", -1)
        waited, step = 0, 50
        while waited < timeout_ms:
            reply = _native.take_string(_native.bidi_poll_reply(self._handle, cid))
            if reply:
                return json.loads(reply)
            if _native.bidi_pump(self._handle, step) < 0:
                break
            waited += step
        raise TimeoutException(f"BiDi command timed out: {method}", 0)

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
            raise WebDriverException("no browsing context for script.evaluate", 0)
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
            raise WebDriverException("no browsing context for navigate", 0)
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


def Chrome(command_executor: str | None = None, options: dict | None = None,
           ca_path: str | None = None, insecure: bool = False) -> WebDriver:
    """A Chrome session, matching ``webdriver.Chrome()`` in Selenium 4.x.

    With no ``command_executor`` the engine resolves and launches its own
    chromedriver (no driver on PATH, no Grid) — a :class:`LocalChrome`. Pass a
    URL to drive an already-running chromedriver instead. ``options`` is a raw
    capabilities dict merged under ``browserName: chrome``."""
    if command_executor is None:
        return LocalChrome(options=options, ca_path=ca_path, insecure=insecure)
    caps = {"browserName": "chrome"}
    if options:
        caps.update(options)
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

    def __init__(self, options: dict | None = None, hint: str = "", timeout_ms: int = 15000,
                 ca_path: str | None = None, insecure: bool = False):
        proc = ensure_driver("chrome", hint, timeout_ms)
        if proc is None:
            raise WebDriverException("could not resolve/launch chromedriver", -1)
        self._proc = proc
        caps = {"browserName": "chrome"}
        if options:
            caps.update(options)
        super().__init__(proc.url, caps, ca_path=ca_path, insecure=insecure)

    def quit(self) -> None:
        try:
            super().quit()
        finally:
            self._proc.stop()
