"""Third-party consumer example. Imports the INSTALLED `selenium_core` package
(from a clean venv — NOT the source tree) and proves the bundled engine .so
loads and drives the protocol, with SELENIUM_CORE_LIB unset so only the wheel's
own native/ dir can satisfy the load.

Modes:
  ffi       — no browser: load the .so, exercise the pure engine helpers and the
              transport-error round-trip. Always runnable.
  discovery — like ffi, but explicitly asserts the .so was found by the package's
              own bundled-native discovery (no env var, no explicit path).
  live      — if chromedriver is on PATH, run a real headless-Chrome smoke.
              Skips (exit 0) if chromedriver is absent.

Exit 0 = pass/skip; non-zero = failure.
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import time


def _check_import_is_installed():
    import selenium_core
    path = os.path.dirname(os.path.abspath(selenium_core.__file__))
    # Must resolve to the clean installed location (a venv's site-packages, or
    # the clean-site dir the wheel was unpacked into), NOT the repo source tree
    # at .../python/selenium_core. The .example.ae harness points PYTHONPATH at
    # the install dir only; if we somehow imported the source tree, the whole
    # "does the packaged wheel stand alone" proof is void.
    installed = ("site-packages" in path) or ("consumer-site" in path)
    if not installed:
        raise SystemExit(f"FAIL: imported selenium_core from {path}, not the installed wheel")
    return selenium_core


def mode_ffi():
    sc = _check_import_is_installed()
    from selenium_core import _native

    # Pure engine helpers cross the FFI.
    assert _native.take_string(_native.route(_native.encode("get"))) == "POST /session/:sessionId/url"
    loc = json.loads(_native.take_string(
        _native.by_locator(_native.encode("id"), _native.encode("main"))))
    assert loc == {"using": "css selector", "value": '*[id="main"]'}, loc
    assert _native.error_code(_native.encode("no such element")) == 17

    # A transport failure round-trips cleanly (proves execute + the .so path).
    from selenium_core import WebDriverError
    try:
        sc.Chrome("http://127.0.0.1:1")  # dead port
        raise SystemExit("FAIL: expected transport failure")
    except WebDriverError as e:
        assert e.w3c_code == -1, e.w3c_code
    print("consumer(ffi): OK — installed wheel loaded its bundled .so and marshalled")


def mode_discovery():
    # SELENIUM_CORE_LIB must be unset here (the .example.ae uses env -u).
    if os.environ.get("SELENIUM_CORE_LIB"):
        raise SystemExit("FAIL: SELENIUM_CORE_LIB is set; discovery mode must run without it")
    sc = _check_import_is_installed()
    from selenium_core import _native
    _native._ensure_loaded()
    # The loaded library must be the one bundled inside the installed package.
    pkg_native = os.path.join(os.path.dirname(os.path.abspath(sc.__file__)), "native")
    # We can't introspect ctypes' resolved path portably, but the load
    # succeeding with no env var and a bundled native/ present is the proof.
    assert os.path.isdir(pkg_native), f"FAIL: no bundled native/ at {pkg_native}"
    assert any(f.endswith((".so", ".dylib", ".dll")) for f in os.listdir(pkg_native)), \
        "FAIL: bundled native/ has no shared library"
    assert _native.take_string(_native.route(_native.encode("newSession"))) == "POST /session"
    print("consumer(discovery): OK — zero-config bundled-.so discovery works")


def _free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close()
    return p


def _wait_up(port, timeout=10.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def mode_live():
    driver = shutil.which("chromedriver")
    if not driver:
        print("consumer(live): SKIPPED — chromedriver not on PATH")
        return
    sc = _check_import_is_installed()
    from selenium_core import By

    port = _free_port()
    proc = subprocess.Popen([driver, f"--port={port}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not _wait_up(port):
            print("consumer(live): SKIPPED — chromedriver did not come up")
            return
        opts = {"goog:chromeOptions": {"args": ["--headless=new", "--no-sandbox", "--disable-gpu"]}}
        d = sc.Chrome(f"http://127.0.0.1:{port}", options=opts)
        try:
            import urllib.parse
            html = '<html><head><title>Installed</title></head><body><h1 id="h">Hi</h1></body></html>'
            d.get("data:text/html;charset=utf-8," + urllib.parse.quote(html))
            assert d.title == "Installed", d.title
            assert d.find_element(By.ID, "h").text == "Hi"
            print("consumer(live): OK — installed wheel drove real headless Chrome")
        finally:
            d.quit()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "ffi"
    {"ffi": mode_ffi, "discovery": mode_discovery, "live": mode_live}[mode]()
    return 0


if __name__ == "__main__":
    sys.exit(main())
