"""No-browser FFI test: proves the Python binding loads libselenium_core.so and
marshals across the ctypes boundary correctly, exercising the pure engine
helpers (by_locator / route / error_code) and the open/close lifecycle. Needs
only the .so (SELENIUM_CORE_LIB), no chromedriver."""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from selenium import _native  # noqa: E402


def test_by_locator_css():
    raw = _native.take_string(
        _native.by_locator(_native.encode("css selector"), _native.encode("div.foo"))
    )
    assert json.loads(raw) == {"using": "css selector", "value": "div.foo"}


def test_by_locator_id_rewrites_to_css():
    raw = _native.take_string(
        _native.by_locator(_native.encode("id"), _native.encode("main"))
    )
    assert json.loads(raw) == {"using": "css selector", "value": '*[id="main"]'}


def test_route_lookup():
    assert _native.take_string(_native.route(_native.encode("get"))) == "POST /session/:sessionId/url"
    assert _native.take_string(_native.route(_native.encode("nope"))) == ""


def test_error_code_map():
    assert _native.error_code(_native.encode("no such element")) == 17
    assert _native.error_code(_native.encode("")) == 0


def test_build_request_element_command():
    # :id is consumed into the path, not the body — the whole point of the
    # shared request-builder. Crosses the FFI as a tab-separated triple.
    raw = _native.take_string(
        _native.build_request(
            _native.encode("sendKeysToElement"),
            _native.encode("S1"),
            _native.encode(json.dumps({"id": "E9", "text": "hi"})),
        )
    )
    method, path, body = raw.split("\t")
    assert method == "POST"
    assert path == "/session/S1/element/E9/value"
    assert json.loads(body) == {"text": "hi"}


def test_open_close_no_session():
    h = _native.open(_native.encode("http://127.0.0.1:1"))
    assert h  # non-null handle
    # No newSession -> session id is empty.
    assert _native.take_string(_native.session_id(h)) == ""
    _native.close(h)


def test_execute_transport_failure():
    # Point at a dead port; newSession must report a transport failure (rc -1),
    # NOT crash. Proves the round-trip error path across the FFI.
    h = _native.open(_native.encode("http://127.0.0.1:1"))
    rc = _native.execute(
        h, _native.encode("newSession"),
        _native.encode(json.dumps({"capabilities": {"alwaysMatch": {}}})),
    )
    assert rc == -1
    msg = _native.take_string(_native.last_error(h))
    assert msg  # some transport error text
    _native.close(h)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"ok: {name}")
    print("PASS: FFI tests green")
