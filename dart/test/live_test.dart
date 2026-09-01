// Live end-to-end + surface test (Dart): a real headless Chrome session driven
// through the pure-Aether engine via dart:ffi. The content server runs
// out-of-process (test/content_server.dart) because the synchronous FFI calls
// block the isolate. Skips if chromedriver is absent.
import 'dart:convert';
import 'dart:io';

import 'package:selenium_core/selenium_core.dart';
import 'package:test/test.dart';

String? which(String cmd) {
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(':')) {
    final f = File('$dir/$cmd');
    if (f.existsSync()) return f.path;
  }
  return null;
}

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

Future<bool> waitUp(int port, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final s = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 500));
      await s.close();
      return true;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  return false;
}

void main() {
  test('live chrome + surface', () async {
    final driverBin = which('chromedriver');
    if (driverBin == null) {
      markTestSkipped('chromedriver not on PATH');
      return;
    }

    // Out-of-process content server.
    final server = await Process.start(
        Platform.resolvedExecutable, ['run', 'test/content_server.dart']);
    final portLine = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('PORT '));
    final webPort = int.parse(portLine.substring(5).trim());
    final base = 'http://127.0.0.1:$webPort';

    final cdPort = await freePort();
    final cd = await Process.start(driverBin, ['--port=$cdPort']);
    try {
      if (!await waitUp(cdPort, const Duration(seconds: 10))) {
        markTestSkipped('chromedriver did not come up');
        return;
      }

      final d = WebDriver.headlessChrome('http://127.0.0.1:$cdPort');
      try {
        expect(d.sessionId, isNotEmpty);

        d.get('$base/one');
        expect(d.title, 'Page One');
        expect(d.findElement(By.id, 'hdr').text, 'One');
        expect(d.findElement(By.css, '#go').tagName.toLowerCase(), 'a');

        // navigation history
        d.findElement(By.id, 'go').click();
        expect(d.title, 'Page Two');
        d.back();
        expect(d.title, 'Page One');
        d.forward();
        expect(d.title, 'Page Two');
        d.back();

        // cookies
        d.deleteAllCookies();
        d.addCookie({'name': 'flavor', 'value': 'mint'});
        expect((d.getCookie('flavor') as Map)['value'], 'mint');
        d.deleteCookie('flavor');

        // windows
        final handles = d.windowHandles;
        expect(handles, isNotEmpty);
        expect(handles, contains(d.currentWindowHandle));
        d.setWindowRect({'width': 900, 'height': 650});
        expect((d.getWindowRect() as Map)['width'], 900);

        // execute_script shapes
        expect(d.executeScript('return 6*7;'), 42);
        expect(d.executeScript("return 'hi';"), 'hi');
        expect(d.executeScript('return [1,2,3];'), [1, 2, 3]);
        expect(d.executeScript('return arguments[0]+arguments[1];', [40, 2]), 42);

        // timeout setter + async script: the async callback is arguments[last].
        d.setScriptTimeout(10000);
        expect(
            d.executeAsyncScript('arguments[arguments.length-1](42);'), 42);

        // W3C actions: pointer click on the button.
        final rect = d.findElement(By.id, 'btn').rect;
        final cx = ((rect['x'] as num) + (rect['width'] as num) / 2).round();
        final cy = ((rect['y'] as num) + (rect['height'] as num) / 2).round();
        d.performActions([
          {
            'type': 'pointer',
            'id': 'mouse',
            'parameters': {'pointerType': 'mouse'},
            'actions': [
              {'type': 'pointerMove', 'duration': 0, 'x': cx, 'y': cy},
              {'type': 'pointerDown', 'button': 0},
              {'type': 'pointerUp', 'button': 0},
            ],
          }
        ]);
        expect(d.findElement(By.id, 'hdr').text, 'clicked');
        d.clearActions();

        // screenshot -> PNG
        final raw = base64Decode(d.screenshotBase64());
        expect(String.fromCharCodes(raw.sublist(1, 4)), 'PNG');

        // negative path
        expect(() => d.findElement(By.id, 'does-not-exist'),
            throwsA(isA<NoSuchElementError>()));
      } finally {
        d.quit();
      }
    } finally {
      cd.kill();
      server.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('live chrome + atoms', () async {
    final driverBin = which('chromedriver');
    if (driverBin == null) {
      markTestSkipped('chromedriver not on PATH');
      return;
    }

    final cdPort = await freePort();
    final cd = await Process.start(driverBin, ['--port=$cdPort']);
    try {
      if (!await waitUp(cdPort, const Duration(seconds: 10))) {
        markTestSkipped('chromedriver did not come up');
        return;
      }

      final d = WebDriver.headlessChrome('http://127.0.0.1:$cdPort');
      try {
        // A self-contained fixture served straight from a data: URL.
        const html = '<!doctype html><title>Atoms</title>'
            '<h1 id="hdr">Header</h1>'
            '<button id="btn">click me</button>'
            '<p id="gone" style="display:none">hidden</p>'
            '<a id="lnk" href="https://example.com/x">link</a>';
        d.get('data:text/html,${Uri.encodeComponent(html)}');

        // isDisplayed: the atom's real visibility algorithm.
        expect(d.findElement(By.id, 'hdr').isDisplayed(), isTrue);
        expect(d.findElement(By.id, 'gone').isDisplayed(), isFalse);

        // getAttribute via the atom (property-or-attribute).
        final href = d.findElement(By.id, 'lnk').getAttribute('href');
        expect(href, isA<String>());
        expect(href as String, contains('example.com/x'));

        // findRelative: the button sits below the header.
        final below = d.findRelative('button', [
          {'kind': 'below', 'sel': '#hdr'}
        ]);
        expect(below.length, greaterThanOrEqualTo(1));
        expect(below.first.getAttribute('id'), 'btn');
      } finally {
        d.quit();
      }
    } finally {
      cd.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('live driver orchestration', () async {
    // Driver orchestration over the engine: resolve + spawn a chromedriver
    // in-binding (no chromedriver on PATH, no Grid), drive a page through the
    // self-launched driver, and tear the process down — the ensureDriver ->
    // url -> open -> stop flow the C-ABI exposes for FFI bindings.

    // Resolve only — self-skip if the engine can't produce a driver here
    // (offline + empty cache). Deliberately does NOT consult PATH.
    final path = resolveDriver(browser: 'chrome');
    if (path.isEmpty) {
      markTestSkipped('engine cannot resolve a chromedriver (offline, no cache)');
      return;
    }
    expect(File(path).existsSync(), isTrue,
        reason: 'resolveDriver returned a non-file: $path');

    // ensureDriver spawns it; the handle exposes url + pid, independent of any
    // W3C session.
    final proc = ensureDriver(browser: 'chrome');
    expect(proc, isNotNull);
    try {
      expect(proc!.url, startsWith('http'), reason: 'driver url=${proc.url}');
      expect(proc.pid, greaterThan(0), reason: 'driver pid=${proc.pid}');
    } finally {
      proc!.stop();
      expect(proc.pid, 0, reason: 'stop() should clear the handle');
    }

    // LocalChrome ties it together: spawn its own driver, run a session, and
    // stop the driver on quit — the whole point of the orchestration ABI.
    final chromeBinary = Platform.environment['SEL_CHROME_BINARY'];
    final d = LocalChrome.headless(chromeBinary: chromeBinary);
    try {
      expect(d.sessionId, isNotEmpty);
      const html = '<!doctype html><title>Aether Selenium</title>'
          '<h1 id="hdr">Hello</h1>';
      d.get('data:text/html,${Uri.encodeComponent(html)}');
      expect(d.title, 'Aether Selenium');
      expect(d.findElement(By.id, 'hdr').text, 'Hello');
    } finally {
      d.quit();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('live chrome + bidi', () async {
    final driverBin = which('chromedriver');
    if (driverBin == null) {
      markTestSkipped('chromedriver not on PATH');
      return;
    }

    // Out-of-process content server.
    final server = await Process.start(
        Platform.resolvedExecutable, ['run', 'test/content_server.dart']);
    final portLine = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('PORT '));
    final webPort = int.parse(portLine.substring(5).trim());
    final base = 'http://127.0.0.1:$webPort';

    final cdPort = await freePort();
    final cd = await Process.start(driverBin, ['--port=$cdPort']);
    try {
      if (!await waitUp(cdPort, const Duration(seconds: 10))) {
        markTestSkipped('chromedriver did not come up');
        return;
      }

      final d = WebDriver.headlessChrome('http://127.0.0.1:$cdPort');
      try {
        expect(d.bidiAvailable, isTrue);

        d.get('$base/one');

        // subscribe -> ack success
        final ack = d.bidi.subscribe([BidiEvent.logEntryAdded]);
        expect(ack['type'], 'success');

        // emit a console log through the classic session
        d.executeScript("console.log('bidi-hello');");

        // the event streams over the BiDi channel
        final ev =
            d.bidi.nextEvent(BidiEvent.logEntryAdded, timeoutMs: 8000);
        expect(ev, isNotNull);
        expect(ev!['method'], BidiEvent.logEntryAdded);
        expect(jsonEncode(ev), contains('bidi-hello'));

        // a plain command round-trips too
        final status = d.bidi.command('session.status');
        expect(status['type'], 'success');

        // typed convenience commands: getTree/topContext, script.evaluate
        expect(d.bidi.topContext(), isNotNull);
        expect(d.bidi.evaluateValue('6*7'), 42);
        // script.evaluate awaits a returned promise
        expect(d.bidi.evaluateValue('Promise.resolve(41+1)'), 42);

        // network interception: pause a request, then release it.
        d.bidi.subscribe([BidiEvent.beforeRequestSent]);
        final ic = d.bidi.addIntercept(urlPattern: '');
        expect(ic, isNotNull);
        d.executeScript(
            "fetch('https://example.com/blocked').catch(()=>{});");
        final netEv =
            d.bidi.nextEvent(BidiEvent.beforeRequestSent, timeoutMs: 8000);
        expect(netEv, isNotNull);
        final rid = BiDi.eventRequestId(netEv!);
        expect(rid, isNotNull);
        expect(d.bidi.continueRequest(rid!)['type'], 'success');

        // request mocking: fulfil a paused request with a mock response.
        d.executeScript("window.__mock='';"
            "fetch('https://example.com/api').then((r)=>r.text())"
            ".then((t)=>{window.__mock=t;}).catch((e)=>{});");
        final ev2 =
            d.bidi.nextEvent(BidiEvent.beforeRequestSent, timeoutMs: 8000);
        expect(ev2, isNotNull);
        final rid2 = BiDi.eventRequestId(ev2!);
        expect(rid2, isNotNull);
        final resp = d.bidi.provideResponse(rid2!,
            status: 200, contentType: 'text/plain', body: 'MOCKED-BODY');
        expect(resp['type'], 'success');

        var mocked = '';
        for (var i = 0; i < 25; i++) {
          mocked = (d.executeScript('return window.__mock;') as String?) ?? '';
          if (mocked.contains('MOCKED-BODY')) break;
          sleep(const Duration(milliseconds: 200));
        }
        expect(mocked, contains('MOCKED-BODY'));

        // setCacheBehavior: disable then restore the session HTTP cache.
        expect(d.bidi.setCacheBehavior('bypass')['type'], 'success');
        expect(d.bidi.setCacheBehavior('default')['type'], 'success');
      } finally {
        d.quit();
      }
    } finally {
      cd.kill();
      server.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
