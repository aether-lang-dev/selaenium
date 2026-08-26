/// The ergonomic Dart WebDriver surface over the shared Aether core. Carries no
/// protocol logic — every command is one native execute() call plus JSON
/// marshalling. Calls are synchronous (the engine's FFI round-trip blocks).
library;

import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkgffi;

import 'native.dart';

const String w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// Locator strategies. Values match the engine's by_locator strategy strings;
/// id/name/className are rewritten to CSS in the engine.
class By {
  static const String id = 'id';
  static const String name = 'name';
  static const String css = 'css selector';
  static const String className = 'className';
  static const String tagName = 'tag name';
  static const String linkText = 'link text';
  static const String partialLinkText = 'partial link text';
  static const String xpath = 'xpath';
}

class WebDriverError implements Exception {
  final String message;
  final int code;
  WebDriverError(this.message, this.code);
  @override
  String toString() => 'WebDriverError($code): $message';
}

class NoSuchElementError extends WebDriverError {
  NoSuchElementError(super.m, super.c);
}

class StaleElementReferenceError extends WebDriverError {
  StaleElementReferenceError(super.m, super.c);
}

class TimeoutError extends WebDriverError {
  TimeoutError(super.m, super.c);
}

WebDriverError _classify(int code, String message) {
  switch (code) {
    case 17:
      return NoSuchElementError(message, code);
    case 23:
      return StaleElementReferenceError(message, code);
    case 21:
    case 24:
      return TimeoutError(message, code);
    default:
      return WebDriverError(message, code);
  }
}

// ---- string arg helper: to a native UTF-8 buffer, freed after the call ----
T _withCStr<T>(String s, T Function(ffi.Pointer<pkgffi.Utf8>) fn) {
  final p = s.toNativeUtf8();
  try {
    return fn(p);
  } finally {
    pkgffi.malloc.free(p);
  }
}

// ---- pure engine helpers ----
String route(String command) =>
    _withCStr(command, (c) => Native.instance.takeString(Native.instance.route(c)));

int errorCode(String w3cError) =>
    _withCStr(w3cError, (c) => Native.instance.errorCode(c));

String locator(String by, String value) => _withCStr(
    by, (b) => _withCStr(value, (v) => Native.instance.takeString(Native.instance.byLocator(b, v))));

Map<String, dynamic> _decodeBy(String by, String value) =>
    jsonDecode(locator(by, value)) as Map<String, dynamic>;

class WebElement {
  final WebDriver _driver;
  final String id;
  WebElement(this._driver, this.id);

  dynamic _exec(String command, [Map<String, dynamic>? params]) {
    final p = <String, dynamic>{...?params, 'id': id};
    return _driver.execute(command, p);
  }

  void click() => _exec('clickElement');
  void clear() => _exec('clearElement');
  void sendKeys(String text) =>
      _exec('sendKeysToElement', {'text': text, 'value': text.split('')});
  String get text => _exec('getElementText') as String;
  String get tagName => _exec('getElementTagName') as String;
  dynamic getAttribute(String name) => _exec('getDomAttribute', {'name': name});
  dynamic getProperty(String name) => _exec('getElementProperty', {'name': name});
  bool isEnabled() => _exec('isElementEnabled') == true;
  bool isSelected() => _exec('isElementSelected') == true;
  Map<String, dynamic> get rect => _exec('getElementRect') as Map<String, dynamic>;
}

class WebDriver {
  ffi.Pointer<ffi.Void> _handle;

  WebDriver._(this._handle);

  factory WebDriver.chrome(String commandExecutor,
      {Map<String, dynamic>? options}) {
    final caps = <String, dynamic>{'browserName': 'chrome', ...?options};
    return WebDriver._create(commandExecutor, caps);
  }

  factory WebDriver.headlessChrome(String commandExecutor) =>
      WebDriver.chrome(commandExecutor, options: {
        'goog:chromeOptions': {
          'args': ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
        },
      });

  factory WebDriver._create(String commandExecutor, Map<String, dynamic> caps) {
    final handle = _withCStr(commandExecutor, (c) => Native.instance.open(c));
    if (handle == ffi.nullptr) {
      throw WebDriverError('failed to open session handle', -1);
    }
    final d = WebDriver._(handle);
    d.execute('newSession', {
      'capabilities': {'alwaysMatch': caps}
    });
    return d;
  }

  /// Pin an explicit native library path (wins over env/bundled).
  static void configureNativeLib(String path) => Native.configure(path);

  // ---- the FFI seam ----
  dynamic execute(String command, [Map<String, dynamic>? params]) {
    final paramsJson = jsonEncode(params ?? {});
    final rc = _withCStr(command,
        (c) => _withCStr(paramsJson, (p) => Native.instance.execute(_handle, c, p)));
    if (rc != 0) {
      final code = Native.instance.lastErrorCode(_handle);
      final message = Native.instance.takeString(Native.instance.lastError(_handle));
      if (rc == -1 && code == 0) {
        throw WebDriverError(message.isEmpty ? 'transport failure' : message, -1);
      }
      throw _classify(code, message);
    }
    final raw = Native.instance.takeString(Native.instance.lastValue(_handle));
    if (raw.isEmpty) return null;
    return jsonDecode(raw);
  }

  // ---- navigation ----
  void get(String url) => execute('get', {'url': url});
  String get currentUrl => execute('getCurrentUrl') as String;
  String get title => execute('getTitle') as String;
  String get pageSource => execute('getPageSource') as String;
  void back() => execute('goBack');
  void forward() => execute('goForward');
  void refresh() => execute('refresh');

  // ---- elements ----
  WebElement findElement(String by, String value) {
    final r = execute('findElement', _decodeBy(by, value)) as Map<String, dynamic>;
    return WebElement(this, r[w3cElementKey] as String);
  }

  List<WebElement> findElements(String by, String value) {
    final r = execute('findElements', _decodeBy(by, value)) as List<dynamic>;
    return r
        .map((e) => WebElement(this, (e as Map<String, dynamic>)[w3cElementKey] as String))
        .toList();
  }

  // ---- script ----
  dynamic executeScript(String script, [List<dynamic> args = const []]) =>
      execute('executeScript', {'script': script, 'args': args});

  // ---- windows ----
  List<String> get windowHandles =>
      (execute('getWindowHandles') as List<dynamic>).cast<String>();
  String get currentWindowHandle => execute('getCurrentWindowHandle') as String;
  dynamic setWindowRect(Map<String, dynamic> rect) => execute('setWindowRect', rect);
  dynamic getWindowRect() => execute('getWindowRect');

  // ---- cookies ----
  void addCookie(Map<String, dynamic> cookie) => execute('addCookie', {'cookie': cookie});
  dynamic getCookies() => execute('getCookies');
  dynamic getCookie(String name) => execute('getCookie', {'name': name});
  void deleteCookie(String name) => execute('deleteCookie', {'name': name});
  void deleteAllCookies() => execute('deleteAllCookies');

  // ---- actions ----
  void performActions(List<dynamic> actions) => execute('actions', {'actions': actions});
  void clearActions() => execute('clearActions');

  // ---- timeouts ----
  void setTimeouts(Map<String, dynamic> timeouts) => execute('setTimeout', timeouts);

  // ---- screenshots ----
  String screenshotBase64() => execute('screenshot') as String;

  // ---- lifecycle ----
  String get sessionId => Native.instance.takeString(Native.instance.sessionId(_handle));

  void quit() {
    try {
      execute('quit');
    } finally {
      _close();
    }
  }

  void _close() {
    if (_handle != ffi.nullptr) {
      Native.instance.close(_handle);
      _handle = ffi.nullptr;
    }
  }
}
