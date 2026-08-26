// No-browser FFI test: proves the Dart dart:ffi binding loads
// libselenium_core.so and marshals correctly, exercising the pure engine
// helpers and the transport error path.
import 'dart:convert';

import 'package:selenium_core/selenium_core.dart';
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

  test('locator css', () {
    expect(jsonDecode(locator(By.css, 'div.foo')),
        {'using': 'css selector', 'value': 'div.foo'});
  });

  test('locator id rewrite', () {
    expect(jsonDecode(locator(By.id, 'main')),
        {'using': 'css selector', 'value': '*[id="main"]'});
  });

  test('transport failure', () {
    expect(
      () => WebDriver.chrome('http://127.0.0.1:1'),
      throwsA(isA<WebDriverError>().having((e) => e.code, 'code', -1)),
    );
  });
}
