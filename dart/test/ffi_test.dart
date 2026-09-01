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
}
