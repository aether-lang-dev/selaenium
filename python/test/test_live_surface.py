"""Live surface-coverage test: exercises the wider WebDriver surface — cookies,
windows, navigation history, timeouts, screenshots, W3C actions, execute_script
return shapes — against a real headless Chrome served by a local HTTP server (so
cookies and navigation have a real http:// origin, which data: URLs lack).

The whole pipeline is proven for each command: Python -> ctypes ->
libselenium_core.so -> std.http.client -> chromedriver -> Chrome. Skips loudly
if chromedriver is absent.
"""

import base64
import http.server
import os
import pytest
import shutil
import socket
import socketserver
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from selenium.webdriver import By, Chrome  # noqa: E402


PAGE_ONE = b"""<!doctype html><html><head><title>Page One</title></head>
<body><h1 id="hdr">One</h1>
<a id="go" href="/two">to two</a>
<button id="btn" onclick="document.getElementById('hdr').textContent='clicked'">b</button>
</body></html>"""

PAGE_TWO = b"""<!doctype html><html><head><title>Page Two</title></head>
<body><h1 id="hdr">Two</h1></body></html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = PAGE_TWO if self.path.startswith("/two") else PAGE_ONE
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


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


def test_live_surface():
    driver_bin = shutil.which("chromedriver")
    if not driver_bin:
        pytest.skip("chromedriver not on PATH")

    # Local content server.
    web_port = _free_port()
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", web_port), Handler)
    httpd.daemon_threads = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{web_port}"

    cd_port = _free_port()
    proc = subprocess.Popen([driver_bin, f"--port={cd_port}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not _wait_up(cd_port):
            pytest.skip("chromedriver did not come up")
        opts = {"goog:chromeOptions": {"args": ["--headless=new", "--no-sandbox",
                                                "--disable-gpu", "--disable-dev-shm-usage"]}}
        d = Chrome(f"http://127.0.0.1:{cd_port}", options=opts)
        try:
            # timeouts (no throw = accepted by the remote end)
            d.implicitly_wait(500)
            d.set_page_load_timeout(30000)
            print("  ok: setTimeout (implicit + pageLoad)")

            d.get(base + "/one")
            assert d.title == "Page One", d.title
            print("  ok: navigate to served page")

            # navigation history
            d.find_element(By.ID, "go").click()
            assert d.title == "Page Two", d.title
            d.back()
            assert d.title == "Page One", f"after back: {d.title}"
            d.forward()
            assert d.title == "Page Two", f"after forward: {d.title}"
            d.back()
            print("  ok: back / forward navigation history")

            # cookies (real http origin)
            d.delete_all_cookies()
            d.add_cookie({"name": "flavor", "value": "mint"})
            cookies = d.get_cookies()
            assert any(c.get("name") == "flavor" and c.get("value") == "mint" for c in cookies), cookies
            one = d.get_cookie("flavor")
            assert one["value"] == "mint", one
            d.delete_cookie("flavor")
            assert all(c.get("name") != "flavor" for c in d.get_cookies())
            print("  ok: add / get / get-one / delete cookies")

            # window handles + rect
            handles = d.window_handles
            assert isinstance(handles, list) and len(handles) >= 1, handles
            assert d.current_window_handle in handles
            d.set_window_rect(width=900, height=650)
            rect = d.get_window_rect()
            assert rect["width"] == 900 and rect["height"] == 650, rect
            print("  ok: window handles + set/get window rect")

            # execute_script return-value shapes
            assert d.execute_script("return 6 * 7;") == 42
            assert d.execute_script("return 'hi';") == "hi"
            assert d.execute_script("return [1,2,3];") == [1, 2, 3]
            assert d.execute_script("return {a: 1, b: 'x'};") == {"a": 1, "b": "x"}
            assert d.execute_script("return arguments[0] + arguments[1];", 40, 2) == 42
            print("  ok: execute_script scalar/array/object/args returns")

            # W3C actions: a pointer click on the button via the actions endpoint.
            btn = d.find_element(By.ID, "btn")
            rect = btn.rect
            cx = int(rect["x"] + rect["width"] / 2)
            cy = int(rect["y"] + rect["height"] / 2)
            d._execute("actions", {"actions": [{
                "type": "pointer", "id": "mouse", "parameters": {"pointerType": "mouse"},
                "actions": [
                    {"type": "pointerMove", "duration": 0, "x": cx, "y": cy},
                    {"type": "pointerDown", "button": 0},
                    {"type": "pointerUp", "button": 0},
                ],
            }]})
            assert d.find_element(By.ID, "hdr").text == "clicked", "actions click did not fire"
            d._execute("clearActions")
            print("  ok: W3C actions (pointer click) + clearActions")

            # screenshot -> valid base64 PNG
            shot = d.get_screenshot_as_base64()
            raw = base64.b64decode(shot)
            assert raw[:8] == b"\x89PNG\r\n\x1a\n", "screenshot is not a PNG"
            print(f"  ok: screenshot ({len(raw)} bytes PNG)")

            print("PASS: live surface test green")
            return
        finally:
            d.quit()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        httpd.shutdown()

