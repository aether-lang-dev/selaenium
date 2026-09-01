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

  /// Whether the element is shown (the isDisplayed atom, run in-page by the
  /// engine — the visibility algorithm, not a naive style check).
  bool isDisplayed() => _driver._atomIsDisplayed(id) == true;

  /// The classic getAttribute(name): property-or-attribute (boolean attrs,
  /// live properties like value/checked), via the shared engine atom. Use
  /// [getDomAttribute] for the raw W3C DOM attribute.
  dynamic getAttribute(String name) => _driver._atomGetAttribute(id, name);

  /// The literal DOM attribute (W3C getDomAttribute), no property fallback.
  dynamic getDomAttribute(String name) => _exec('getDomAttribute', {'name': name});
  dynamic getProperty(String name) => _exec('getElementProperty', {'name': name});
  bool isEnabled() => _exec('isElementEnabled') == true;
  bool isSelected() => _exec('isElementSelected') == true;
  Map<String, dynamic> get rect => _exec('getElementRect') as Map<String, dynamic>;
}

class WebDriver {
  ffi.Pointer<ffi.Void> _handle;

  // The BiDi endpoint negotiated at newSession (webSocketUrl), and the channel
  // opened lazily over it on first `.bidi` use — a classic script never opens
  // the WebSocket.
  String _wsUrl = '';
  BiDi? _bidi;

  /// Generative session constructor: open a handle against [commandExecutor],
  /// apply TLS trust config, then newSession with [caps]. Subclasses (e.g.
  /// [LocalChrome]) call this via `super`.
  WebDriver._session(String commandExecutor, Map<String, dynamic> caps,
      {String? caPath, bool insecure = false})
      : _handle = _openSession(commandExecutor, caPath, insecure) {
    // Request a BiDi channel so `.bidi` is available on demand; the channel
    // itself is opened lazily.
    final matched = <String, dynamic>{...caps, 'webSocketUrl': true};
    final result = execute('newSession', {
      'capabilities': {'alwaysMatch': matched}
    });
    // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
    if (result is Map<String, dynamic>) {
      final sessionCaps = result['capabilities'];
      if (sessionCaps is Map<String, dynamic>) {
        final url = sessionCaps['webSocketUrl'];
        if (url is String) _wsUrl = url;
      }
    }
  }

  // Open a session handle and apply TLS trust config BEFORE newSession (the
  // first request). caPath pins a private-CA bundle; insecure skips
  // verification entirely (self-signed dev/staging Grid — trust out-of-band).
  static ffi.Pointer<ffi.Void> _openSession(
      String commandExecutor, String? caPath, bool insecure) {
    final handle = _withCStr(commandExecutor, (c) => Native.instance.open(c));
    if (handle == ffi.nullptr) {
      throw WebDriverError('failed to open session handle', -1);
    }
    if (caPath != null && caPath.isNotEmpty) {
      _withCStr(caPath, (c) => Native.instance.setCa(handle, c));
    }
    if (insecure) {
      Native.instance.setInsecure(handle, 1);
    }
    return handle;
  }

  factory WebDriver.chrome(String commandExecutor,
      {Map<String, dynamic>? options, String? caPath, bool insecure = false}) {
    final caps = <String, dynamic>{'browserName': 'chrome', ...?options};
    return WebDriver._create(commandExecutor, caps,
        caPath: caPath, insecure: insecure);
  }

  factory WebDriver.headlessChrome(String commandExecutor,
          {String? caPath, bool insecure = false}) =>
      WebDriver.chrome(commandExecutor,
          caPath: caPath,
          insecure: insecure,
          options: {
            'goog:chromeOptions': {
              'args': [
                '--headless=new',
                '--no-sandbox',
                '--disable-gpu',
                '--disable-dev-shm-usage'
              ],
            },
          });

  factory WebDriver._create(String commandExecutor, Map<String, dynamic> caps,
          {String? caPath, bool insecure = false}) =>
      WebDriver._session(commandExecutor, caps,
          caPath: caPath, insecure: insecure);

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

  // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

  /// Drain last_value after an atom call, applying the same typed-error mapping
  /// as [execute].
  dynamic _atomResult(int rc) {
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

  dynamic _atomIsDisplayed(String elementId) => _withCStr(elementId,
      (e) => _atomResult(Native.instance.isDisplayed(_handle, e)));

  dynamic _atomGetAttribute(String elementId, String name) => _withCStr(
      elementId,
      (e) => _withCStr(
          name, (n) => _atomResult(Native.instance.getAttributeAtom(_handle, e, n))));

  /// Relative locators: elements matching [baseCss] filtered by spatial relation
  /// to anchors, nearest first. Each filter is a map
  /// `{"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"}`
  /// (`near` also accepts `"dist"`). Returns a list of [WebElement].
  List<WebElement> findRelative(String baseCss, List<Map<String, dynamic>> filters) {
    final filtersJson = jsonEncode(filters);
    final result = _withCStr(
        baseCss,
        (b) => _withCStr(filtersJson,
            (f) => _atomResult(Native.instance.findRelative(_handle, b, f))));
    final refs = (result as List<dynamic>?) ?? const [];
    return refs
        .map((e) => WebElement(this, (e as Map<String, dynamic>)[w3cElementKey] as String))
        .toList();
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

  dynamic executeAsyncScript(String script, [List<dynamic> args = const []]) =>
      execute('executeAsyncScript', {'script': script, 'args': args});

  // ---- windows ----
  List<String> get windowHandles =>
      (execute('getWindowHandles') as List<dynamic>).cast<String>();
  String get currentWindowHandle => execute('getCurrentWindowHandle') as String;
  void switchToWindow(String handle) => execute('switchToWindow', {'handle': handle});
  dynamic setWindowRect(Map<String, dynamic> rect) => execute('setWindowRect', rect);
  dynamic getWindowRect() => execute('getWindowRect');
  dynamic maximizeWindow() => execute('maximizeWindow');
  dynamic minimizeWindow() => execute('minimizeWindow');
  dynamic fullscreenWindow() => execute('fullscreenWindow');

  // ---- cookies ----
  void addCookie(Map<String, dynamic> cookie) => execute('addCookie', {'cookie': cookie});
  dynamic getCookies() => execute('getCookies');
  dynamic getCookie(String name) => execute('getCookie', {'name': name});
  void deleteCookie(String name) => execute('deleteCookie', {'name': name});
  void deleteAllCookies() => execute('deleteAllCookies');

  // ---- actions ----
  void performActions(List<dynamic> actions) => execute('actions', {'actions': actions});
  void clearActions() => execute('clearActions');

  // ---- alerts ----
  void acceptAlert() => execute('acceptAlert');
  void dismissAlert() => execute('dismissAlert');
  String get alertText => execute('getAlertText') as String;
  void sendAlertText(String text) => execute('setAlertValue', {'text': text});

  // ---- timeouts ----
  void setTimeouts(Map<String, dynamic> timeouts) => execute('setTimeout', timeouts);
  void setPageLoadTimeout(int ms) => execute('setTimeout', {'pageLoad': ms});
  void setScriptTimeout(int ms) => execute('setTimeout', {'script': ms});
  void implicitlyWait(int ms) => execute('setTimeout', {'implicit': ms});

  // ---- screenshots ----
  String screenshotBase64() => execute('screenshot') as String;

  // ---- WebDriver-BiDi ----

  /// The event-driven BiDi surface for this session, lazily opened over the
  /// negotiated webSocketUrl. Throws if the remote end granted no BiDi URL.
  ///
  /// ```dart
  /// driver.bidi.subscribe([BidiEvent.logEntryAdded]);
  /// driver.get(url);
  /// final ev = driver.bidi.nextEvent(BidiEvent.logEntryAdded, timeoutMs: 5000);
  /// ```
  BiDi get bidi {
    var channel = _bidi;
    if (channel == null) {
      if (_wsUrl.isEmpty) {
        throw WebDriverError(
            'BiDi not available: the session negotiated no webSocketUrl', 0);
      }
      final handle = _withCStr(_wsUrl, (c) => Native.instance.bidiOpen(c));
      if (handle == ffi.nullptr) {
        throw WebDriverError('BiDi channel failed to open', -1);
      }
      channel = BiDi._(handle);
      _bidi = channel;
    }
    return channel;
  }

  /// True if this session can use BiDi (a webSocketUrl was negotiated).
  bool get bidiAvailable => _wsUrl.isNotEmpty;

  // ---- lifecycle ----
  String get sessionId => Native.instance.takeString(Native.instance.sessionId(_handle));

  void quit() {
    try {
      _closeBidi();
      execute('quit');
    } finally {
      _close();
    }
  }

  void _closeBidi() {
    _bidi?.close();
    _bidi = null;
  }

  void _close() {
    if (_handle != ffi.nullptr) {
      Native.instance.close(_handle);
      _handle = ffi.nullptr;
    }
  }
}

/// The common WebDriver-BiDi event names (W3C spec). Pass to
/// [BiDi.subscribe] and match in [BiDi.nextEvent].
class BidiEvent {
  static const String logEntryAdded = 'log.entryAdded';
  static const String contextCreated = 'browsingContext.contextCreated';
  static const String contextDestroyed = 'browsingContext.contextDestroyed';
  static const String navigationStarted = 'browsingContext.navigationStarted';
  static const String domContentLoaded = 'browsingContext.domContentLoaded';
  static const String load = 'browsingContext.load';
  static const String downloadWillBegin = 'browsingContext.downloadWillBegin';
  static const String beforeRequestSent = 'network.beforeRequestSent';
  static const String authRequired = 'network.authRequired';
  static const String responseStarted = 'network.responseStarted';
  static const String responseCompleted = 'network.responseCompleted';
  static const String fetchError = 'network.fetchError';
  static const String realmCreated = 'script.realmCreated';
  static const String realmDestroyed = 'script.realmDestroyed';
  static const String message = 'script.message';
}

/// The event-driven BiDi channel for a session (over the demux C ABI).
///
/// Commands and events multiplex over one WebSocket via the engine's shape-C
/// demux (a single reader routes replies to an id table and events to a bounded
/// queue), so replies stay correlated while events stream. Command ids are
/// supplied automatically from a per-channel monotonic counter.
class BiDi {
  ffi.Pointer<ffi.Void> _handle;
  int _nextId = 1;

  BiDi._(this._handle);

  int _id() => _nextId++;

  /// session.subscribe to one or more event names; wait for the ack and return
  /// its payload. After this, matching events arrive on the queue (drain via
  /// [nextEvent]).
  Map<String, dynamic> subscribe(List<String> events, {int timeoutMs = 10000}) {
    final csv = events.join(',');
    final raw = _withCStr(csv,
        (c) => Native.instance.takeString(
            Native.instance.bidiSubscribe(_handle, _id(), c, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Map<String, dynamic> unsubscribe(List<String> events,
      {int timeoutMs = 10000}) {
    final csv = events.join(',');
    final raw = _withCStr(csv,
        (c) => Native.instance.takeString(
            Native.instance.bidiUnsubscribe(_handle, _id(), c, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Block until an event whose [method] matches arrives, or timeout. Returns
  /// the event map, or null on timeout/close. (Subscribe first.)
  Map<String, dynamic>? nextEvent(String method, {int timeoutMs = 5000}) {
    final raw = _withCStr(method,
        (m) => Native.instance.takeString(
            Native.instance.bidiWaitEvent(_handle, m, timeoutMs)));
    return raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Issue any BiDi command and return its reply payload. Lets a caller reach
  /// BiDi methods with no dedicated wrapper (script.evaluate,
  /// browsingContext.captureScreenshot, network.*, …).
  Map<String, dynamic> command(String method,
      {Map<String, dynamic>? params, int timeoutMs = 10000}) {
    final paramsJson = jsonEncode(params ?? {});
    final cid = _id();
    // send + pump until this id's reply arrives (the engine's convenience).
    final rc = _withCStr(
        method,
        (m) => _withCStr(
            paramsJson, (p) => Native.instance.bidiSend(_handle, cid, m, p)));
    if (rc != 0) {
      throw WebDriverError('BiDi send failed: $method', -1);
    }
    var waited = 0;
    const step = 50;
    while (waited < timeoutMs) {
      final reply =
          Native.instance.takeString(Native.instance.bidiPollReply(_handle, cid));
      if (reply.isNotEmpty) return jsonDecode(reply) as Map<String, dynamic>;
      if (Native.instance.bidiPump(_handle, step) < 0) break;
      waited += step;
    }
    throw TimeoutError('BiDi command timed out: $method', 0);
  }

  // ---- typed convenience commands ----

  /// browsingContext.getTree — the browsing contexts (each with a "context" id).
  Map<String, dynamic> getTree({int timeoutMs = 10000}) {
    final raw = Native.instance
        .takeString(Native.instance.bidiGetTree(_handle, _id(), timeoutMs));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// The top-level browsing context id (the anchor for evaluate/navigate), or
  /// null if the session has no context yet.
  String? topContext({int timeoutMs = 10000}) {
    final result = getTree(timeoutMs: timeoutMs)['result'];
    final contexts = (result is Map<String, dynamic> ? result['contexts'] : null);
    if (contexts is List && contexts.isNotEmpty) {
      final first = contexts.first;
      if (first is Map<String, dynamic>) return first['context'] as String?;
    }
    return null;
  }

  /// script.evaluate an expression in the top context's realm, awaiting a
  /// returned promise. Returns the reply; `["result"]["result"]` is the
  /// BiDi-typed value (e.g. `{"type": "number", "value": 42}`). BiDi's richer
  /// alternative to executeScript — real realms, promise-awaiting, structured
  /// value types.
  Map<String, dynamic> evaluate(String expr, {int timeoutMs = 30000}) {
    final ctx = topContext(timeoutMs: timeoutMs);
    if (ctx == null) {
      throw WebDriverError('no browsing context for script.evaluate', 0);
    }
    final raw = _withCStr(
        expr,
        (e) => _withCStr(
            ctx,
            (c) => Native.instance.takeString(Native.instance
                .bidiScriptEvaluate(_handle, _id(), e, c, timeoutMs))));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// script.evaluate, returning just the unwrapped value (the `.value` of the
  /// BiDi-typed result), or null if it wasn't a simple value.
  dynamic evaluateValue(String expr, {int timeoutMs = 30000}) {
    final result = evaluate(expr, timeoutMs: timeoutMs)['result'];
    final inner = (result is Map<String, dynamic> ? result['result'] : null);
    return inner is Map<String, dynamic> ? inner['value'] : null;
  }

  /// browsingContext.navigate the top context to url (wait: complete).
  Map<String, dynamic> navigate(String url, {int timeoutMs = 30000}) {
    final ctx = topContext(timeoutMs: timeoutMs);
    if (ctx == null) {
      throw WebDriverError('no browsing context for navigate', 0);
    }
    final raw = _withCStr(
        ctx,
        (c) => _withCStr(
            url,
            (u) => Native.instance.takeString(
                Native.instance.bidiNavigate(_handle, _id(), c, u, timeoutMs))));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  // ---- network interception (observe / release / block requests) ----

  /// network.addIntercept for a URL pattern (a full parseable URL as a "string"
  /// pattern; empty intercepts all) at the given comma-separated [phases].
  /// Subscribe to the matching network.* event first if you want the
  /// paused-request events. Returns the intercept id, or null.
  String? addIntercept(
      {String phases = 'beforeRequestSent',
      String urlPattern = '',
      int timeoutMs = 10000}) {
    final raw = _withCStr(
        phases,
        (ph) => _withCStr(
            urlPattern,
            (up) => Native.instance.takeString(Native.instance
                .bidiNetworkAddIntercept(_handle, _id(), ph, up, timeoutMs))));
    final reply = raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
    final result = reply['result'];
    return result is Map<String, dynamic> ? result['intercept'] as String? : null;
  }

  Map<String, dynamic> removeIntercept(String interceptId,
      {int timeoutMs = 10000}) {
    final raw = _withCStr(
        interceptId,
        (i) => Native.instance.takeString(Native.instance
            .bidiNetworkRemoveIntercept(_handle, _id(), i, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Let a paused (intercepted) request proceed unchanged. [requestId] comes
  /// from a network event's `params.request.request`.
  Map<String, dynamic> continueRequest(String requestId,
      {int timeoutMs = 10000}) {
    final raw = _withCStr(
        requestId,
        (r) => Native.instance.takeString(Native.instance
            .bidiNetworkContinueRequest(_handle, _id(), r, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Block a paused request (the ad/tracker-blocking case).
  Map<String, dynamic> failRequest(String requestId, {int timeoutMs = 10000}) {
    final raw = _withCStr(
        requestId,
        (r) => Native.instance.takeString(Native.instance
            .bidiNetworkFailRequest(_handle, _id(), r, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Fulfil a paused (intercepted) request with a mock response
  /// (network.provideResponse) — the request never reaches the network.
  /// [requestId] comes from a network event's `params.request.request`. The
  /// engine adds `Access-Control-Allow-Origin: *` so cross-origin fetches see
  /// the mock. Returns the command reply.
  Map<String, dynamic> provideResponse(String requestId,
      {int status = 200,
      String contentType = '',
      String body = '',
      int timeoutMs = 10000}) {
    final raw = _withCStr(
        requestId,
        (r) => _withCStr(
            contentType,
            (ct) => _withCStr(
                body,
                (b) => Native.instance.takeString(
                    Native.instance.bidiNetworkProvideResponse(
                        _handle, _id(), r, status, ct, b, timeoutMs)))));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Answer an HTTP auth challenge (a paused authRequired request) with
  /// credentials — automates basic/digest auth that classic WebDriver can't
  /// handle in headless. [requestId] comes from a network event's
  /// `params.request.request`.
  Map<String, dynamic> continueWithAuth(
      String requestId, String username, String password,
      {int timeoutMs = 10000}) {
    final raw = _withCStr(
        requestId,
        (r) => _withCStr(
            username,
            (u) => _withCStr(
                password,
                (p) => Native.instance.takeString(
                    Native.instance.bidiNetworkContinueWithAuth(
                        _handle, _id(), r, u, p, timeoutMs)))));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Set the session HTTP cache behavior: `"bypass"` to disable it (so every
  /// request hits the network / an intercept), `"default"` to restore it.
  Map<String, dynamic> setCacheBehavior(
      [String behavior = 'bypass', int timeoutMs = 10000]) {
    final raw = _withCStr(
        behavior,
        (b) => Native.instance.takeString(Native.instance
            .bidiNetworkSetCacheBehavior(_handle, _id(), b, timeoutMs)));
    return raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// The network.request id out of a network.beforeRequestSent (or other
  /// network) event: `params.request.request`.
  static String? eventRequestId(Map<String, dynamic> event) {
    final params = event['params'];
    final request = (params is Map<String, dynamic> ? params['request'] : null);
    return request is Map<String, dynamic> ? request['request'] as String? : null;
  }

  /// How many events the bounded queue has dropped since the last call (then
  /// resets) — so a consumer knows it missed events.
  int lostEvents() => Native.instance.bidiLostEvents(_handle);

  void close() {
    if (_handle != ffi.nullptr) {
      Native.instance.bidiClose(_handle);
      _handle = ffi.nullptr;
    }
  }
}

// ---- driver orchestration (spawn / adopt a driver process in-binding) --------
// The engine can resolve, download-or-cache, and launch a browser driver process
// itself — so a caller needs neither a driver on PATH nor a running Grid. These
// wrap the driver-handle C ABI (independent of the W3C session handle).

/// Resolve the local driver binary path for [browser] without launching it
/// (detect/download/cache as needed). [hint] pins a version or path; ''
/// auto-detects. Returns '' if none resolvable (offline, no cache).
String resolveDriver({String browser = 'chrome', String hint = ''}) =>
    _withCStr(
        browser,
        (b) => _withCStr(
            hint,
            (h) => Native.instance
                .takeString(Native.instance.resolveDriver(b, h))));

/// A driver process launched by the engine. Owns the driver handle; call [stop]
/// to terminate it (the handle is one-shot — [pid] reads 0 once stopped).
class DriverProcess {
  ffi.Pointer<ffi.Void> _handle;
  DriverProcess._(this._handle);

  /// The base URL the driver is listening on — pass to a [WebDriver] ctor.
  String get url => _handle == ffi.nullptr
      ? ''
      : Native.instance.takeString(Native.instance.driverUrl(_handle));

  /// The driver process id (0 if not running / stopped).
  int get pid =>
      _handle == ffi.nullptr ? 0 : Native.instance.driverPid(_handle);

  /// Terminate the driver process and clear the handle.
  void stop() {
    if (_handle != ffi.nullptr) {
      Native.instance.stopDriver(_handle);
      _handle = ffi.nullptr;
    }
  }
}

/// Launch a driver at an explicit binary path. Returns a [DriverProcess], or
/// null if it did not come up within [timeoutMs].
DriverProcess? launchDriver(String driverPath, {int timeoutMs = 15000}) {
  final h =
      _withCStr(driverPath, (p) => Native.instance.launchDriver(p, timeoutMs));
  return h == ffi.nullptr ? null : DriverProcess._(h);
}

/// Resolve (detect/download/cache) AND launch a driver for [browser] in one
/// step. Returns a running [DriverProcess], or null if none could be
/// resolved/launched.
DriverProcess? ensureDriver(
    {String browser = 'chrome', String hint = '', int timeoutMs = 15000}) {
  final h = _withCStr(
      browser,
      (b) => _withCStr(
          hint, (h) => Native.instance.ensureDriver(b, h, timeoutMs)));
  return h == ffi.nullptr ? null : DriverProcess._(h);
}

/// A Chrome session that spawns its own chromedriver via the engine — no driver
/// on PATH, no Grid. The driver process is stopped on [quit].
///
/// Throws [WebDriverError] if the driver cannot be resolved/launched.
class LocalChrome extends WebDriver {
  final DriverProcess _proc;

  LocalChrome._(this._proc, Map<String, dynamic> caps,
      {String? caPath, bool insecure = false})
      : super._session(_proc.url, caps, caPath: caPath, insecure: insecure);

  factory LocalChrome(
      {Map<String, dynamic>? options,
      String hint = '',
      int timeoutMs = 15000,
      String? caPath,
      bool insecure = false}) {
    final proc = ensureDriver(hint: hint, timeoutMs: timeoutMs);
    if (proc == null) {
      throw WebDriverError('could not resolve/launch chromedriver', -1);
    }
    final caps = <String, dynamic>{'browserName': 'chrome', ...?options};
    return LocalChrome._(proc, caps, caPath: caPath, insecure: insecure);
  }

  /// Convenience: a headless LocalChrome with the usual CI-safe flags. Pass
  /// [chromeBinary] to point at a specific Chrome (honoured as
  /// `goog:chromeOptions.binary`).
  factory LocalChrome.headless({String? chromeBinary}) {
    final chromeOptions = <String, dynamic>{
      'args': [
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        '--disable-dev-shm-usage'
      ],
    };
    if (chromeBinary != null && chromeBinary.isNotEmpty) {
      chromeOptions['binary'] = chromeBinary;
    }
    return LocalChrome(options: {'goog:chromeOptions': chromeOptions});
  }

  @override
  void quit() {
    try {
      super.quit();
    } finally {
      _proc.stop();
    }
  }
}
