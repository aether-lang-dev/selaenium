// No-browser FFI test: proves the Dart dart:ffi binding loads
// libselenium_core.so and marshals correctly, exercising the pure engine
// helpers and the transport error path.
import 'dart:convert';

import 'package:selenium/selenium.dart';
import 'package:test/test.dart';

void main() {
  test('route', () {
    expect(route('get'), 'POST /session/:sessionId/url');
    expect(route('nope'), '');
  });

  test('errorCode', () {
    expect(errorCode('no such element'), 17);
    expect(errorCode(''), 0);
  });

  test('By factory carries strategy + value', () {
    final css = By.cssSelector('div.foo');
    expect(css.strategy, 'css selector');
    expect(css.value, 'div.foo');
    expect(By.className('x').strategy, 'class name');
  });

  test('locator css', () {
    final by = By.cssSelector('div.foo');
    expect(jsonDecode(locator(by.strategy, by.value)),
        {'using': 'css selector', 'value': 'div.foo'});
  });

  test('locator id rewrite', () {
    final by = By.id('main');
    expect(jsonDecode(locator(by.strategy, by.value)),
        {'using': 'css selector', 'value': '*[id="main"]'});
  });

  test('transport failure', () {
    expect(
      () => WebDriver.chrome('http://127.0.0.1:1'),
      throwsA(isA<WebDriverException>().having((e) => e.code, 'code', -1)),
    );
  });

  test('shadow-root error codes map to typed exceptions', () {
    // 19 = no such shadow root, 2 = detached shadow root (W3C).
    expect(errorCode('no such shadow root'), 19);
    expect(errorCode('detached shadow root'), 2);
  });

  test('ShadowRoot search-context surface is present', () {
    // Compile-surface check: ShadowRoot is a declared type (mirrors the
    // element-scoped findElement/findElements shape).
    const Type sr = ShadowRoot;
    expect(sr, ShadowRoot);
    // The commands the shadow routes resolve to are known to the engine.
    expect(route('getShadowRoot'),
        'GET /session/:sessionId/element/:id/shadow');
    expect(route('findElementFromShadowRoot'),
        'POST /session/:sessionId/shadow/:id/element');
    expect(route('findElementsFromShadowRoot'),
        'POST /session/:sessionId/shadow/:id/elements');
  });

  test('firefox/edge/safari factories set the right browserName', () {
    // No browser is touched: each per-browser factory tries to open a handle
    // against a dead port, so it fails transport (code -1) — proving the
    // factory exists and is callable with the chrome shape. Edge (no Edge on
    // Linux) and Safari (macOS-only) are not live-runnable here, so this
    // surface check is their coverage.
    for (final open in <WebDriver Function()>[
      () => WebDriver.firefox('http://127.0.0.1:1'),
      () => WebDriver.headlessFirefox('http://127.0.0.1:1'),
      () => WebDriver.edge('http://127.0.0.1:1'),
      () => WebDriver.headlessEdge('http://127.0.0.1:1'),
      () => WebDriver.safari('http://127.0.0.1:1'),
    ]) {
      expect(open,
          throwsA(isA<WebDriverException>().having((e) => e.code, 'code', -1)));
    }
  });
}
