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

Future<void> modeLive() async {
  await configureBundled();
  // The engine starts the driver, so the whole tree (browser included) ends on
  // stop() and when this process dies.
  final cd = ensureDriver(browser: 'chrome');
  if (cd == null) {
    print('consumer(live): SKIPPED — the engine cannot resolve a chromedriver');
    return;
  }
  try {
    final d = WebDriver.headlessChrome(cd.url);
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
    cd.stop();
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
  // Exit explicitly so a lingering isolate or handle cannot hang a finished run.
  exit(0);
}
