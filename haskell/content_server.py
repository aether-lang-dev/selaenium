# Out-of-process content server for the Haskell live test, spawned by test/Live.hs
# (which reads the "PORT <n>" line below and builds its own base URL). It runs in
# its own process because the binding's FFI calls are synchronous — an in-process
# server would deadlock behind a blocking get(). Serves /one and /two.
import http.server
import socketserver
import sys

ONE = (
    b'<!doctype html><title>Page One</title><h1 id="hdr">One</h1>'
    b'<a id="go" href="/two">to two</a>'
    b"<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
)
TWO = b'<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>'


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = TWO if self.path.startswith("/two") else ONE
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


httpd = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
sys.stdout.write("PORT %d\n" % httpd.server_address[1])
sys.stdout.flush()
httpd.serve_forever()
