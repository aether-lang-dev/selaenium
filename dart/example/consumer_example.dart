// Third-party consumer example. Depends on the INSTALLED selenium package
// (via a pub path dep to the staged copy — NOT the repo source) and proves the
// bundled engine .so loads and drives the protocol, with SELENIUM_CORE_LIB unset
// so only the package's own bundled native/ can satisfy the load.
//
// Discovery: a real consumer resolves the installed package's bundled .so via
// its package URI, then pins it with configureNativeLib(). Modes: ffi | discovery
// | live.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:selenium/selenium.dart';

Future<String?> bundledSoPath() async {
  final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:selenium/selenium.dart'));
  if (uri == null) return null;
  // <pkg>/lib/selenium.dart -> <pkg>/native/libselenium_core.so
  final libDir = File.fromUri(uri).parent; // .../lib
  final pkgRoot = libDir.parent; // pkg root
  final so = File('${pkgRoot.path}/native/libselenium_core.so');
  return so.existsSync() ? so.path : null;
}

void fail(String msg) {
  stderr.writeln('FAIL: $msg');
  exit(1);
}

Future<void> configureBundled() async {
  final so = await bundledSoPath();
  if (so == null) fail('bundled native/libselenium_core.so not found in the installed package');
  WebDriver.configureNativeLib(so!);
}

Future<void> modeFfi() async {
  await configureBundled();
  if (route('get') != 'POST /session/:sessionId/url') fail('route mismatch');
  if (errorCode('no such element') != 17) fail('errorCode mismatch');
  final byId = By.id('main');
  final loc = jsonDecode(locator(byId.strategy, byId.value)) as Map;
  if (loc['value'] != '*[id="main"]') fail('locator mismatch: $loc');
  try {
    WebDriver.chrome('http://127.0.0.1:1');
    fail('expected transport failure');
  } on WebDriverException catch (e) {
    if (e.code != -1) fail('wrong transport code ${e.code}');
  }
  print('consumer(ffi): OK — installed package loaded its bundled .so and marshalled');
}

Future<void> modeDiscovery() async {
  final env = Platform.environment['SELENIUM_CORE_LIB'];
  if (env != null && env.isNotEmpty) fail('SELENIUM_CORE_LIB set; discovery must run without it');
  final so = await bundledSoPath();
  if (so == null) fail('no bundled .so discovered in the installed package');
  WebDriver.configureNativeLib(so!);
  if (route('newSession') != 'POST /session') fail('route mismatch (bundled .so did not load)');
  print('consumer(discovery): OK — zero-config bundled-.so discovery works');
}

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
  final p = s.port;
  await s.close();
  return p;
}

Future<bool> waitUp(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
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

Future<void> modeLive() async {
  final driver = which('chromedriver');
  if (driver == null) {
    print('consumer(live): SKIPPED — chromedriver not on PATH');
    return;
  }
  await configureBundled();
  final port = await freePort();
  final cd = await Process.start(driver, ['--port=$port'],
      mode: ProcessStartMode.detachedWithStdio);
  try {
    if (!await waitUp(port)) {
      print('consumer(live): SKIPPED — chromedriver did not come up');
      return;
    }
    final d = WebDriver.headlessChrome('http://127.0.0.1:$port');
    try {
      const html = '<!doctype html><title>Installed</title><h1 id="h">Hi</h1>';
      d.get('data:text/html;charset=utf-8,${Uri.encodeComponent(html)}');
      if (d.title != 'Installed') fail('title=${d.title}');
      if (d.findElement(By.id('h')).text != 'Hi') fail('text mismatch');
      print('consumer(live): OK — installed package drove real headless Chrome');
    } finally {
      d.quit();
    }
  } finally {
    cd.kill();
  }
}

Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args[0] : 'ffi';
  switch (mode) {
    case 'ffi':
      await modeFfi();
      break;
    case 'discovery':
      await modeDiscovery();
      break;
    case 'live':
      await modeLive();
      break;
    default:
      fail('unknown mode: $mode');
  }
  // Exit explicitly: a killed chromedriver child can otherwise keep the Dart
  // process alive on its attached stdio, hanging after a successful run.
  exit(0);
}
