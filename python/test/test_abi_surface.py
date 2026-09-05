"""No-browser ABI-parity tests: prove the Python binding presents the mainstream
Selenium-Python surface (import paths, method names/signatures, and the exact
W3C commands the facades issue) WITHOUT a browser or the engine .so.

The facades (SwitchTo / Alert / ActionChains / Select / expected_conditions)
route everything through ``driver._execute`` / ``driver.find_element`` /
``driver.execute_script``, so a small recording fake stands in for the driver
and lets us assert the exact (command, params) pairs. This mirrors how the
convenience tier is meant to be validated: the wire shape is what matters.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from selenium._webdriver import WebElement, _W3C_ELEMENT_KEY  # noqa: E402


# ---- import-path resolution (the mainstream locations must all resolve) ------


def test_import_paths_resolve():
    import selenium  # noqa: F401
    from selenium import webdriver
    from selenium.webdriver.remote.webdriver import WebDriver
    from selenium.webdriver.remote.webelement import WebElement as WE
    from selenium.webdriver.remote.switch_to import SwitchTo
    from selenium.webdriver.common.alert import Alert
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys
    from selenium.webdriver.common.action_chains import ActionChains, ScrollOrigin
    from selenium.webdriver.common.options import BaseOptions, ArgOptions
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.support.ui import WebDriverWait, Select
    from selenium.webdriver.support import expected_conditions  # noqa: F401

    # webdriver namespace exposes ChromeOptions and the facade classes
    assert webdriver.ChromeOptions is Options
    assert webdriver.SwitchTo is SwitchTo
    assert webdriver.Alert is Alert
    assert issubclass(Options, ArgOptions) and issubclass(ArgOptions, BaseOptions)
    assert WE is WebElement


def test_exceptions_importable_and_hierarchy():
    from selenium.common.exceptions import (
        WebDriverException,
        InvalidSwitchToTargetException,
        NoSuchFrameException,
        NoSuchWindowException,
        NoSuchElementException,
        NoSuchAttributeException,
        NoSuchShadowRootException,
        InvalidElementStateException,
        UnexpectedAlertPresentException,
        NoAlertPresentException,
        ElementNotVisibleException,
        ElementNotSelectableException,
        InvalidCookieDomainException,
        UnableToSetCookieException,
        MoveTargetOutOfBoundsException,
        UnexpectedTagNameException,
        ImeNotAvailableException,
        ImeActivationFailedException,
        InvalidArgumentException,
        NoSuchCookieException,
        ScreenshotException,
        InsecureCertificateException,
        InvalidCoordinatesException,
        InvalidSessionIdException,
        UnknownMethodException,
        NoSuchDriverException,
        DetachedShadowRootException,
    )

    # Base-class hierarchy matches upstream.
    assert issubclass(NoSuchFrameException, InvalidSwitchToTargetException)
    assert issubclass(NoSuchWindowException, InvalidSwitchToTargetException)
    assert issubclass(ElementNotVisibleException, InvalidElementStateException)
    assert issubclass(ElementNotSelectableException, InvalidElementStateException)
    assert issubclass(InvalidSwitchToTargetException, WebDriverException)

    # Same object regardless of import path (single source of truth).
    from selenium._webdriver import NoSuchElementException as Core
    assert Core is NoSuchElementException

    # Upstream constructor shape (msg, screen, stacktrace) is honored.
    e = WebDriverException("boom", screen="shot", stacktrace=["a", "b"])
    assert e.msg == "boom" and e.screen == "shot" and e.stacktrace == ["a", "b"]

    e2 = UnexpectedAlertPresentException("x", alert_text="hi")
    assert e2.alert_text == "hi"


# ---- a recording fake driver ------------------------------------------------


class FakeDriver:
    """Records every _execute call; returns canned values keyed by command."""

    _is_remote = False

    def __init__(self, returns=None):
        self.calls = []
        self._returns = returns or {}

    def _execute(self, command, params=None):
        self.calls.append((command, params or {}))
        val = self._returns.get(command)
        return val() if callable(val) else val

    # facades reach these directly
    def find_element(self, by, value=None):
        self.calls.append(("findElement", {"using": by, "value": value}))
        return self._returns.get("findElement", WebElement(self, "el-found"))

    def find_elements(self, by, value=None):
        self.calls.append(("findElements", {"using": by, "value": value}))
        return self._returns.get("findElements", [])

    def execute_script(self, script, *args):
        self.calls.append(("executeScript", {"script": script, "args": args}))
        return self._returns.get("executeScript")

    @property
    def current_window_handle(self):
        return "orig"

    @property
    def window_handles(self):
        return ["orig"]


def _cmds(driver):
    return [c for c, _ in driver.calls]


# ---- switch_to facade -------------------------------------------------------


def test_switch_to_window_frame_parent_default():
    from selenium._webdriver import SwitchTo

    d = FakeDriver()
    st = SwitchTo(d)
    st.window("w-2")
    st.parent_frame()
    st.default_content()

    assert ("switchToWindow", {"handle": "w-2"}) in d.calls
    assert ("switchToFrameParent", {}) in d.calls
    assert ("switchToFrame", {"id": None}) in d.calls


def test_switch_to_frame_by_index_and_element():
    from selenium._webdriver import SwitchTo

    d = FakeDriver()
    st = SwitchTo(d)
    st.frame(1)  # integer index passes through
    assert ("switchToFrame", {"id": 1}) in d.calls

    el = WebElement(d, "frame-99")
    st.frame(el)  # WebElement becomes a W3C element reference
    assert ("switchToFrame", {"id": {_W3C_ELEMENT_KEY: "frame-99"}}) in d.calls


def test_switch_to_new_window_switches_to_returned_handle():
    from selenium._webdriver import SwitchTo

    d = FakeDriver(returns={"newWindow": {"handle": "new-h", "type": "tab"}})
    st = SwitchTo(d)
    st.new_window("tab")
    assert ("newWindow", {"type": "tab"}) in d.calls
    assert ("switchToWindow", {"handle": "new-h"}) in d.calls


def test_switch_to_active_element_returns_webelement():
    from selenium._webdriver import SwitchTo

    d = FakeDriver(returns={"getActiveElement": {_W3C_ELEMENT_KEY: "active-1"}})
    st = SwitchTo(d)
    el = st.active_element
    assert isinstance(el, WebElement) and el.id == "active-1"
    assert ("getActiveElement", {}) in d.calls


def test_switch_to_alert_returns_alert_and_reads_text():
    from selenium._webdriver import SwitchTo, Alert

    d = FakeDriver(returns={"getAlertText": "Are you sure?"})
    st = SwitchTo(d)
    alert = st.alert
    assert isinstance(alert, Alert)
    # accessing .alert eagerly reads text (mainstream behavior)
    assert ("getAlertText", {}) in d.calls
    assert alert.text == "Are you sure?"


# ---- Alert ------------------------------------------------------------------


def test_alert_methods_issue_right_commands():
    from selenium.webdriver.common.alert import Alert

    d = FakeDriver(returns={"getAlertText": "hi"})
    a = Alert(d)
    assert a.text == "hi"
    a.accept()
    a.dismiss()
    a.send_keys("typed")

    assert ("acceptAlert", {}) in d.calls
    assert ("dismissAlert", {}) in d.calls
    assert ("setAlertValue", {"text": "typed", "value": list("typed")}) in d.calls


# ---- WebElement additions ---------------------------------------------------


def test_send_keys_variadic():
    from selenium.webdriver.common.keys import Keys

    d = FakeDriver()
    el = WebElement(d, "e1")
    el.send_keys("ab", "c", Keys.ENTER)
    # last recorded call is sendKeysToElement with joined text + char list
    cmd, params = d.calls[-1]
    assert cmd == "sendKeysToElement"
    assert params["text"] == "ab" + "c" + Keys.ENTER
    assert params["value"] == ["a", "b", "c", Keys.ENTER]
    assert params["id"] == "e1"


def test_send_keys_accepts_numbers():
    d = FakeDriver()
    el = WebElement(d, "e1")
    el.send_keys(12)
    _, params = d.calls[-1]
    assert params["value"] == ["1", "2"]


def test_screenshot_as_base64_is_property():
    d = FakeDriver(returns={"takeElementScreenshot": "AAAA"})
    el = WebElement(d, "e1")
    # PROPERTY, not a method — accessing it (no call) returns the value
    assert isinstance(WebElement.screenshot_as_base64, property)
    assert el.screenshot_as_base64 == "AAAA"


def test_element_location_size_aria():
    d = FakeDriver(returns={
        "getElementRect": {"x": 1, "y": 2, "width": 3, "height": 4},
        "getAriaRole": "button",
        "getAccessibleName": "Submit",
    })
    el = WebElement(d, "e1")
    assert el.location == {"x": 1, "y": 2}
    assert el.size == {"width": 3, "height": 4}
    assert el.aria_role == "button"
    assert el.accessible_name == "Submit"


def test_element_submit_runs_script():
    d = FakeDriver()
    el = WebElement(d, "e1")
    el.submit()
    assert _cmds(d)[-1] == "executeScript"
    _, params = d.calls[-1]
    assert params["args"] == (el,)


def test_find_element_default_args():
    import inspect
    from selenium.webdriver.common.by import By

    for cls in (WebElement,):
        sig = inspect.signature(cls.find_element)
        assert sig.parameters["by"].default == By.ID
        assert sig.parameters["value"].default is None


# ---- Options / ChromeOptions ------------------------------------------------


def test_chrome_options_to_capabilities():
    from selenium.webdriver.chrome.options import Options

    opts = Options()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_experimental_option("prefs", {"download.default_directory": "/tmp"})
    opts.binary_location = "/usr/bin/chromium"
    opts.set_capability("acceptInsecureCerts", True)

    caps = opts.to_capabilities()
    assert caps["browserName"] == "chrome"
    assert caps["acceptInsecureCerts"] is True
    goog = caps["goog:chromeOptions"]
    assert goog["args"] == ["--headless=new", "--no-sandbox"]
    assert goog["binary"] == "/usr/bin/chromium"
    assert goog["prefs"] == {"download.default_directory": "/tmp"}


def test_options_add_argument_rejects_empty():
    from selenium.webdriver.chrome.options import Options

    try:
        Options().add_argument("")
        assert False, "expected ValueError"
    except ValueError:
        pass


def test_chrome_accepts_options_object(monkeypatch=None):
    # Chrome(command_executor=...) must accept a ChromeOptions object and apply
    # to_capabilities(). We intercept WebDriver construction to capture caps.
    import selenium._webdriver as core
    from selenium.webdriver.chrome.options import Options

    captured = {}

    class FakeWD:
        def __init__(self, url, caps, ca_path=None, insecure=False):
            captured["url"] = url
            captured["caps"] = caps

    orig = core.WebDriver
    core.WebDriver = FakeWD
    try:
        opts = Options()
        opts.add_argument("--headless=new")
        core.Chrome("http://localhost:9515", options=opts)
    finally:
        core.WebDriver = orig

    assert captured["caps"]["browserName"] == "chrome"
    assert captured["caps"]["goog:chromeOptions"]["args"] == ["--headless=new"]


def test_chrome_still_accepts_raw_dict():
    import selenium._webdriver as core

    captured = {}

    class FakeWD:
        def __init__(self, url, caps, ca_path=None, insecure=False):
            captured["caps"] = caps

    orig = core.WebDriver
    core.WebDriver = FakeWD
    try:
        core.Chrome("http://localhost:9515", options={"goog:chromeOptions": {"args": ["--x"]}})
    finally:
        core.WebDriver = orig

    assert captured["caps"]["goog:chromeOptions"] == {"args": ["--x"]}


# ---- Keys -------------------------------------------------------------------


def test_keys_new_constants_exact_codepoints():
    from selenium.webdriver.common.keys import Keys

    assert Keys.RIGHT_SHIFT == "\ue050"
    assert Keys.RIGHT_CONTROL == "\ue051"
    assert Keys.RIGHT_ALT == "\ue052"
    assert Keys.RIGHT_META == "\ue053"
    assert Keys.RIGHT_OPTION == Keys.RIGHT_ALT
    assert Keys.LEFT_META == Keys.META == "\ue03d"
    assert Keys.LEFT_COMMAND == Keys.COMMAND == "\ue03d"
    assert Keys.LEFT_OPTION == Keys.LEFT_ALT == "\ue00a"
    assert Keys.ZENKAKU_HANKAKU == "\ue040"


# ---- ActionChains additions -------------------------------------------------


def test_action_chains_new_members_exist():
    from selenium.webdriver.common.action_chains import ActionChains, ScrollOrigin

    for name in (
        "reset_actions", "drag_and_drop_by_offset", "move_by_offset",
        "move_to_element_with_offset", "send_keys_to_element",
        "scroll_to_element", "scroll_by_amount", "scroll_from_origin",
    ):
        assert hasattr(ActionChains, name), name

    assert hasattr(ScrollOrigin, "from_element")
    assert hasattr(ScrollOrigin, "from_viewport")


def test_action_chains_scroll_emits_wheel_device():
    from selenium.webdriver.common.action_chains import ActionChains, ScrollOrigin

    d = FakeDriver()
    ActionChains(d).scroll_by_amount(0, 200).perform()
    cmd, params = d.calls[-1]
    assert cmd == "actions"
    devices = {a["type"] for a in params["actions"]}
    assert "wheel" in devices

    d2 = FakeDriver()
    el = WebElement(d2, "e1")
    ActionChains(d2).scroll_from_origin(ScrollOrigin.from_element(el, 5, 6), 0, 100).perform()
    cmd, params = d2.calls[-1]
    wheel = [a for a in params["actions"] if a["type"] == "wheel"][0]
    scroll = [a for a in wheel["actions"] if a.get("type") == "scroll"][0]
    assert scroll["origin"] == {_W3C_ELEMENT_KEY: "e1"}
    assert scroll["deltaY"] == 100


# ---- Select additions -------------------------------------------------------


def test_select_deselect_methods_exist():
    from selenium.webdriver.support.select import Select

    for name in ("deselect_by_value", "deselect_by_index", "deselect_by_visible_text"):
        assert hasattr(Select, name), name


# ---- expected_conditions additions ------------------------------------------


def test_expected_conditions_new_members_exist():
    from selenium.webdriver.support import expected_conditions as EC

    for name in (
        "visibility_of_any_elements_located", "visibility_of_all_elements_located",
        "text_to_be_present_in_element_value", "text_to_be_present_in_element_attribute",
        "frame_to_be_available_and_switch_to_it", "invisibility_of_element",
        "element_to_be_selected", "element_located_to_be_selected",
        "element_selection_state_to_be", "element_located_selection_state_to_be",
        "number_of_windows_to_be", "new_window_is_opened",
        "element_attribute_to_include", "url_matches", "url_changes",
        "any_of", "all_of", "none_of",
    ):
        assert hasattr(EC, name), name


def test_expected_conditions_url_matches_and_windows():
    from selenium.webdriver.support import expected_conditions as EC

    class D:
        current_url = "https://example.com/path?q=1"
        window_handles = ["a", "b"]

    d = D()
    assert EC.url_matches(r"example\.com/path")(d) is True
    assert EC.url_matches(r"nope")(d) is False
    assert EC.url_changes("https://other")(d) is True
    assert EC.number_of_windows_to_be(2)(d) is True
    assert EC.new_window_is_opened({"a"})(d) is True


def test_expected_conditions_any_all_none():
    from selenium.webdriver.support import expected_conditions as EC

    yes = lambda d: "Y"
    no = lambda d: False

    assert EC.any_of(no, yes)(None) == "Y"
    assert EC.any_of(no, no)(None) is False
    assert EC.all_of(yes, yes)(None) == ["Y", "Y"]
    assert EC.all_of(yes, no)(None) is False
    assert EC.none_of(no, no)(None) is True
    assert EC.none_of(no, yes)(None) is False


# ---- WebDriver facade methods (name/capabilities/screenshot/print/window) ----


def _make_driver_without_session():
    """Build a WebDriver instance bypassing __init__ (no engine .so needed)."""
    from selenium._webdriver import WebDriver, SwitchTo

    d = WebDriver.__new__(WebDriver)
    d._caps = {"browserName": "chrome"}
    d._switch_to = SwitchTo.__new__(SwitchTo)
    d.calls = []

    def _execute(command, params=None):
        d.calls.append((command, params or {}))
        return {
            "screenshot": "QUJD",  # base64 of "ABC"
            "getWindowRect": {"x": 1, "y": 2, "width": 800, "height": 600},
            "printPage": "cGRm",
        }.get(command)

    d._execute = _execute
    return d


def test_webdriver_name_and_capabilities():
    d = _make_driver_without_session()
    assert d.name == "chrome"
    assert d.capabilities == {"browserName": "chrome"}


def test_webdriver_screenshot_png_and_window_helpers():
    import base64
    d = _make_driver_without_session()
    assert d.get_screenshot_as_png() == base64.b64decode(b"QUJD")
    assert d.get_window_size() == {"width": 800, "height": 600}
    assert d.get_window_position() == {"x": 1, "y": 2}
    d.set_window_size(1024, 768)
    assert ("setWindowRect", {"width": 1024, "height": 768}) in d.calls
    d.set_window_position(10, 20)
    assert ("setWindowRect", {"x": 10, "y": 20}) in d.calls


def test_webdriver_print_page():
    d = _make_driver_without_session()
    assert d.print_page() == "cGRm"
    assert ("printPage", {}) in d.calls


def test_webdriver_execute_is_public_alias():
    from selenium._webdriver import WebDriver
    d = _make_driver_without_session()
    # execute() delegates to _execute
    d.execute("screenshot")
    assert ("screenshot", {}) in d.calls
