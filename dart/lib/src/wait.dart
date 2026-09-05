/// Explicit waits — the Dart face of mainstream Selenium's `WebDriverWait`.
///
/// `WebDriverWait(driver, Duration(seconds: 10)).until(condition)` polls
/// `condition(driver)` until it returns a non-null / truthy value (then returns
/// it), or throws [TimeoutException] when the deadline passes. A condition is
/// any `T? Function(WebDriver)` — one of the [waitForElement]/[waitForVisible]/
/// [waitForClickable]/[waitForTitleContains] helpers, or your own closure.
///
/// Unlike a fixed sleep, this returns as soon as the condition holds. The poll
/// loop lives in the binding (the engine issues single commands and holds no
/// thread), exactly as the reference `aether/webdriver.ae` waits do.
///
/// ```dart
/// final el = WebDriverWait(driver, const Duration(seconds: 10))
///     .until(waitForVisible(By.id('result')));
/// ```
library;

import 'dart:io' show sleep;

import 'webdriver.dart';

/// Mainstream default poll cadence (500ms).
const Duration defaultPollFrequency = Duration(milliseconds: 500);

/// Polls a condition against a driver until it holds or a timeout elapses.
///
/// Generic over the driver type [D] — the everyday `WebDriverWait(driver, …)`
/// infers `D = WebDriver`, so the shipped [waitForElement]/[waitForVisible]/…
/// helpers work; the generic parameter also lets the poll loop be unit-tested
/// with a plain fake driver, no browser.
///
/// [NoSuchElementException] and [StaleElementReferenceException] thrown by a
/// condition are swallowed during polling (a not-yet-present / mid-rerender
/// element should retry, not fail) — matching mainstream's ignored exceptions.
class WebDriverWait<D> {
  final D _driver;
  final Duration _timeout;
  final Duration _poll;

  WebDriverWait(this._driver, Duration timeout,
      {Duration pollFrequency = defaultPollFrequency})
      : _timeout = timeout,
        _poll = pollFrequency > Duration.zero
            ? pollFrequency
            : defaultPollFrequency;

  /// Poll [condition] until it returns a non-null, truthy value; return it.
  /// Throws [TimeoutException] if the deadline passes first. [message] overrides
  /// the default timeout text.
  T until<T>(T? Function(D) condition, {String message = ''}) {
    final deadline = DateTime.now().add(_timeout);
    Object? lastError;
    while (true) {
      try {
        final value = condition(_driver);
        if (_truthy(value)) return value as T;
      } on NoSuchElementException catch (e) {
        lastError = e;
      } on StaleElementReferenceException catch (e) {
        lastError = e;
      }
      if (DateTime.now().isAfter(deadline)) break;
      sleep(_poll);
    }
    throw TimeoutException(
        message.isNotEmpty ? message : _timeoutMsg(_timeout, lastError), 21);
  }

  /// Poll [condition] until it returns a falsy / null value (or throws an
  /// ignored exception); return true. Throws [TimeoutException] on timeout.
  bool untilNot<T>(T? Function(D) condition, {String message = ''}) {
    final deadline = DateTime.now().add(_timeout);
    while (true) {
      try {
        final value = condition(_driver);
        if (!_truthy(value)) return true;
      } on NoSuchElementException {
        return true;
      } on StaleElementReferenceException {
        return true;
      }
      if (DateTime.now().isAfter(deadline)) break;
      sleep(_poll);
    }
    throw TimeoutException(
        message.isNotEmpty ? message : _timeoutMsg(_timeout, null), 21);
  }

  static bool _truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is Iterable) return v.isNotEmpty;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  static String _timeoutMsg(Duration timeout, Object? lastError) {
    final base = 'waited ${timeout.inMilliseconds / 1000}s for condition';
    return lastError != null ? '$base (last error: $lastError)' : base;
  }
}

// ---- expected-condition helpers (mirror aether/webdriver.ae wait_for_*) ----

/// Condition: an element matching [by]/[value] is present in the DOM. Returns
/// the element, or null (retry) until located. (classic elementLocated)
WebElement? Function(WebDriver) waitForElement(By by) =>
    (driver) => _findOrNull(driver, by);

/// Condition: the element matching [by]/[value] is present AND displayed.
/// (classic elementLocated + visibilityOf)
WebElement? Function(WebDriver) waitForVisible(By by) => (driver) {
      final el = _findOrNull(driver, by);
      return (el != null && el.isDisplayed()) ? el : null;
    };

/// Condition: the element is present, displayed AND enabled (clickable).
/// (classic elementToBeClickable)
WebElement? Function(WebDriver) waitForClickable(By by) => (driver) {
      final el = _findOrNull(driver, by);
      return (el != null && el.isDisplayed() && el.isEnabled()) ? el : null;
    };

/// Condition: the page title contains [substring]. Returns true when it does.
bool? Function(WebDriver) waitForTitleContains(String substring) =>
    (driver) => driver.title.contains(substring) ? true : null;

/// Condition: the page title equals [title] exactly.
bool? Function(WebDriver) waitForTitleIs(String title) =>
    (driver) => driver.title == title ? true : null;

/// Condition: the current URL contains [substring].
bool? Function(WebDriver) waitForUrlContains(String substring) =>
    (driver) => driver.currentUrl.contains(substring) ? true : null;

WebElement? _findOrNull(WebDriver driver, By by) {
  try {
    return driver.findElement(by);
  } on NoSuchElementException {
    return null;
  }
}
