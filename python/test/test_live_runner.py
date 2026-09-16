"""Live runner-surface test: exercises the interactive runner substrate — the
shell, the run/step/continue controller, the SUT-adjacent console bridge, and
.side playback — against a real headless Chrome.

Mirrors the D binding's runner-surface live checks (d/tests/live_test.d): the
engine owns the shell grammar, the runner controller, the iframe bridge, and
.side playback; this proves the Python face over that C ABI drives a live
browser. Skips loudly if chromedriver is absent.
"""

import os
import http.server
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
<body><h1 id="hdr">One</h1></body></html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE_ONE)))
        self.end_headers()
        self.wfile.write(PAGE_ONE)

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


def test_live_runner():
    driver_bin = shutil.which("chromedriver")
    if not driver_bin:
        pytest.skip("chromedriver not on PATH")

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
            # Runner shell: one line -> a JSON result, dispatched engine-side.
            ro = d.shell("open data:text/html,<title>Sh</title><h1 id=q>hey</h1>")
            assert ro["ok"], ro
            assert d.shell("title")["value"] == "Sh", d.shell("title")
            assert d.shell("text #q")["value"] == "hey", d.shell("text #q")
            assert d.shell("eval return 6*7;")["value"] == 42
            assert d.shell("bogusverb")["ok"] is False, "unknown verb -> ok:false"
            print("  ok: shell (open / title / text / eval / unknown-verb)")

            # Runner controller: run/step/continue over the multiplexed lane.
            r = d.runner()
            try:
                # run mode: eval executes immediately, reply carries the result.
                rr = r.eval("open data:text/html,<title>Run</title><h1 id=z>go</h1>")
                assert "result" in rr and rr["result"]["ok"], rr
                assert r.eval("title")["result"]["value"] == "Run"
                # a command-finished event fired
                saw_finished = False
                ev = r.next_event()
                while ev is not None:
                    if ev.get("method") == "command-finished":
                        saw_finished = True
                    ev = r.next_event()
                assert saw_finished, "expected a command-finished event"
                # step mode: queue a line, then step runs it.
                assert r.mode("step")["result"]["mode"] == "step"
                q = r.eval("text #z")
                assert "queued" in q["result"], q
                st = r.step()["result"]
                assert st["stepped"] and st["result"]["value"] == "go", st
            finally:
                r.close()
            print("  ok: runner (run-mode eval, command-finished event, step mode)")

            # SUT-adjacent console bridge: install the shim + iframe, then drive
            # one request through the bridge and read the reply back out of the
            # page — the executeScript transport, end to end against live Chrome.
            d.get(base + "/one")   # Page One: <h1 id=hdr>One</h1>
            br = d.bridge()
            try:
                br.inject()   # installs window.__selaenium + console iframe
                # The console would postMessage this up; simulate by pushing it
                # straight into the outbox the shim drains (bypassing the iframe).
                d.execute_script(
                    "window.__selaenium.out.push(JSON.stringify("
                    "{id:7001,method:'eval',params:{line:'text #hdr'}}));"
                    "window.__selaenium.__replies=[];"
                    "window.addEventListener('message',function(e){"
                    "  if(e.data&&e.data.selaenium==='rep')window.__selaenium.__replies.push(e.data.body);});"
                )
                assert br.pump() >= 1, "bridge pump processed the queued request"
                captured = None
                for _ in range(20):
                    reps = d.execute_script(
                        "return JSON.stringify(window.__selaenium.__replies||[]);"
                    )
                    import json as _json
                    arr = _json.loads(reps)
                    if isinstance(arr, list) and arr:
                        for item in arr:
                            if isinstance(item, dict) and "result" in item:
                                captured = item
                        if captured is not None:
                            break
                    time.sleep(0.05)
                assert captured is not None, "a reply was delivered back into the page"
                assert captured["result"]["value"] == "One", captured
            finally:
                br.close()
            print("  ok: bridge (inject + pump round-trips 'text #hdr' -> 'One')")

            # .side playback: play a real Selenium IDE project and check the
            # report — parse -> per-command shell dispatch -> pass/fail, live.
            side = (
                '{"name":"d","tests":[{"name":"t","commands":['
                '{"command":"open","target":"data:text/html,<title>SideOK</title>'
                '<h1 id=z>hi</h1>","value":""},'
                '{"command":"assertTitle","target":"","value":"SideOK"},'
                '{"command":"assertText","target":"id=z","value":"hi"}]}]}'
            )
            rep = d.play_side(side)
            assert rep["tests"] == 1, rep
            assert rep["passed"] == 1 and rep["failed"] == 0, rep
            assert rep["results"][0]["ok"], rep
            # a deliberately-wrong assertion must fail the test
            bad = (
                '{"name":"d","tests":[{"name":"wrong","commands":['
                '{"command":"open","target":"data:text/html,<title>Real</title>","value":""},'
                '{"command":"assertTitle","target":"","value":"NotReal"}]}]}'
            )
            assert d.play_side(bad)["failed"] == 1, "a wrong assertion fails the test"
            print("  ok: play_side (passed==1 failed==0; wrong assertion fails)")

            print("PASS: live runner-surface test green")
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
