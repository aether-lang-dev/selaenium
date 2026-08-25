// Out-of-process content server for the live test. The binding's FFI calls are
// synchronous and block the Dart isolate, so a same-isolate HTTP server could
// not answer while a d.get() blocks. Prints "PORT <n>" once listening.
import 'dart:io';

const pageOne = '<!doctype html><title>Page One</title><h1 id="hdr">One</h1>'
    '<a id="go" href="/two">to two</a>'
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
const pageTwo = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  stdout.writeln('PORT ${server.port}');
  await for (final req in server) {
    final body = req.uri.path.startsWith('/two') ? pageTwo : pageOne;
    req.response.headers.contentType = ContentType.html;
    req.response.write(body);
    await req.response.close();
  }
}
