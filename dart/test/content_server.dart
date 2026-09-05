// Out-of-process content server for the live test. The binding's FFI calls are
// synchronous and block the Dart isolate, so a same-isolate HTTP server could
// not answer while a d.get() blocks. Prints "PORT <n>" once listening.
import 'dart:io';

const pageOne = '<!doctype html><title>Page One</title><h1 id="hdr">One</h1>'
    '<a id="go" href="/two">to two</a>'
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
const pageTwo = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>';

// A page exercising the convenience tier: a <select>, a right-click target, and
// a "results appear late" element the explicit waits poll for.
const pageForm = '<!doctype html><title>Form</title>'
    '<select id="color">'
    '<option value="r">Red</option>'
    '<option value="g">Green</option>'
    '<option value="b">Blue</option>'
    '</select>'
    '<div id="picked"></div>'
    '<button id="ctx" oncontextmenu="'
    "document.getElementById('picked').textContent='ctx';return false;"
    '">right-click me</button>'
    '<div id="late"></div>'
    '<script>'
    "document.getElementById('color').addEventListener('change',function(e){"
    "document.getElementById('picked').textContent=e.target.value;});"
    // The "server push arrives late" case the waits are for.
    "setTimeout(function(){document.getElementById('late').textContent='ready';},700);"
    '</script>';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  stdout.writeln('PORT ${server.port}');
  await for (final req in server) {
    final path = req.uri.path;
    final body = path.startsWith('/two')
        ? pageTwo
        : path.startsWith('/form')
            ? pageForm
            : pageOne;
    req.response.headers.contentType = ContentType.html;
    req.response.write(body);
    await req.response.close();
  }
}
