"""Live end-to-end smoke test: a real headless Chrome session driven entirely
through the pure-Aether engine. This is the whole pipeline —
Python -> ctypes -> libselenium_core.so -> std.http.client -> chromedriver ->
Chrome — proving the shared core actually drives a browser.

Requires chromedriver on PATH and a Chrome/Chromium binary. The test starts its
own chromedriver on an ephemeral port, runs against a data: URL (no network),
and tears everything down. Skips loudly if chromedriver is absent.
"""

import json
import os
import pytest
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from selenium_core import By, Chrome, NoSuchElementError  # noqa: E402


def _free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _wait_up(port: int, timeout: float = 10.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


import urllib.parse  # noqa: E402

_HTML = (
    "<html><head><title>Aether Selenium</title></head>"
    '<body><h1 id="hdr">Hello</h1>'
    '<a href="#" id="lnk" class="nav">click me</a>'
    '<input id="box" name="q"/></body></html>'
)
# URL-encode the document so chromedriver parses it identically to a served
# page — a raw data: URL with spaces/quotes parses leniently and unevenly.
PAGE = "data:text/html;charset=utf-8," + urllib.parse.quote(_HTML)


def test_live_chrome():
    driver_bin = shutil.which("chromedriver")
    if not driver_bin:
        pytest.skip("chromedriver not on PATH")

    port = _free_port()
    proc = subprocess.Popen(
        [driver_bin, f"--port={port}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        if not _wait_up(port):
            pytest.skip("chromedriver did not come up")

        options = {
            "goog:chromeOptions": {
                "args": ["--headless=new", "--no-sandbox", "--disable-gpu",
                         "--disable-dev-shm-usage"]
            }
        }
        driver = Chrome(f"http://127.0.0.1:{port}", options=options)
        try:
            assert driver.session_id, "no session id after newSession"
            print(f"  ok: session started ({driver.session_id[:8]}...)")

            driver.get(PAGE)
            print("  ok: navigated")

            assert driver.title == "Aether Selenium", f"title={driver.title!r}"
            print(f"  ok: title == {driver.title!r}")

            hdr = driver.find_element(By.ID, "hdr")
            assert hdr.text == "Hello", f"hdr.text={hdr.text!r}"
            print(f"  ok: find_element(By.ID) + text == {hdr.text!r}")

            lnk = driver.find_element(By.CLASS_NAME, "nav")
            assert lnk.tag_name.lower() == "a", f"tag={lnk.tag_name!r}"
            print(f"  ok: find_element(By.CLASS_NAME) + tag_name == {lnk.tag_name!r}")

            lnk.click()
            print("  ok: click")

            box = driver.find_element(By.CSS_SELECTOR, "#box")
            box.send_keys("hello world")
            assert box.get_property("value") == "hello world", box.get_property("value")
            print("  ok: send_keys + get_property('value')")

            n = driver.execute_script("return 40 + 2;")
            assert n == 42, f"script returned {n!r}"
            print(f"  ok: execute_script -> {n}")

            # Negative path: a missing element raises the typed exception.
            try:
                driver.find_element(By.ID, "does-not-exist")
                assert False, "expected NoSuchElementError"
            except NoSuchElementError:
                print("  ok: NoSuchElementError raised for missing element")

            print("PASS: live Chrome smoke test green")
            return
        finally:
            driver.quit()
            print("  ok: quit")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_live_bidi():
    """WebDriver-BiDi over the same engine: subscribe to console log entries,
    emit one via the classic script channel, and receive the event
    asynchronously — the bidirectional half, driven from Python through the
    demux C ABI."""
    from selenium_core import BidiEvent  # noqa: E402

    driver_bin = shutil.which("chromedriver")
    if not driver_bin:
        pytest.skip("chromedriver not on PATH")

    port = _free_port()
    proc = subprocess.Popen(
        [driver_bin, f"--port={port}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        if not _wait_up(port):
            pytest.skip("chromedriver did not come up")

        options = {
            "goog:chromeOptions": {
                "args": ["--headless=new", "--no-sandbox", "--disable-gpu",
                         "--disable-dev-shm-usage"]
            }
        }
        driver = Chrome(f"http://127.0.0.1:{port}", options=options)
        try:
            assert driver.bidi_available, "session negotiated no webSocketUrl"
            print("  ok: BiDi available (webSocketUrl negotiated)")

            driver.get(PAGE)

            ack = driver.bidi.subscribe(BidiEvent.LOG_ENTRY_ADDED)
            assert ack.get("type") == "success", f"subscribe ack={ack!r}"
            print("  ok: bidi.subscribe(log.entryAdded)")

            driver.execute_script("console.log('bidi-hello');")

            ev = driver.bidi.next_event(BidiEvent.LOG_ENTRY_ADDED, timeout_ms=8000)
            assert ev is not None, "no log.entryAdded event received"
            assert ev.get("method") == BidiEvent.LOG_ENTRY_ADDED, f"event={ev!r}"
            # the logged text rides in params.args[0].value
            assert "bidi-hello" in json.dumps(ev), f"event missing text: {ev!r}"
            print("  ok: log.entryAdded event received async, carries the text")

            # a raw BiDi command through the same channel (session.status).
            status = driver.bidi.command("session.status")
            assert status.get("type") == "success", f"status={status!r}"
            print("  ok: bidi.command(session.status)")

            print("PASS: live BiDi test green")
        finally:
            driver.quit()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

