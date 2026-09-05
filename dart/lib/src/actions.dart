/// Fluent action builder — the Dart face of mainstream Selenium's
/// `ActionChains`, reached via `driver.actions()`.
///
/// Queue gestures with chained calls, then [perform]:
///
/// ```dart
/// driver.actions().moveToElement(menu).click(item).perform();
/// driver.actions().dragAndDrop(source, target).perform();
/// ```
///
/// Each call appends to a W3C actions sequence (a pointer + a key virtual
/// device); [perform] posts the whole sequence in one `actions` command — the
/// same wire shape the reference `aether/webdriver.ae` action helpers emit.
library;

import 'webdriver.dart';

/// A fluent builder over the W3C input-actions protocol. Construct via
/// [WebDriver.actions].
class Actions {
  final DriverLike _driver;
  final List<Map<String, dynamic>> _pointer = [];
  final List<Map<String, dynamic>> _key = [];

  Actions(this._driver);

  // ---- pointer gestures ----

  /// Move the pointer to the centre of [element].
  Actions moveToElement(ElementLike element) {
    _pointer.add({
      'type': 'pointerMove',
      'duration': 100,
      'x': 0,
      'y': 0,
      'origin': {w3cElementKey: element.id},
    });
    return _sync();
  }

  /// Click (left button). Moves to [element] first when given.
  Actions click([ElementLike? element]) {
    if (element != null) moveToElement(element);
    _pointer.add({'type': 'pointerDown', 'button': 0});
    _pointer.add({'type': 'pointerUp', 'button': 0});
    return _sync();
  }

  /// Right-click (context menu). Moves to [element] first when given.
  Actions contextClick([ElementLike? element]) {
    if (element != null) moveToElement(element);
    _pointer.add({'type': 'pointerDown', 'button': 2});
    _pointer.add({'type': 'pointerUp', 'button': 2});
    return _sync();
  }

  /// Double-click (left button). Moves to [element] first when given.
  Actions doubleClick([ElementLike? element]) {
    if (element != null) moveToElement(element);
    for (var i = 0; i < 2; i++) {
      _pointer.add({'type': 'pointerDown', 'button': 0});
      _pointer.add({'type': 'pointerUp', 'button': 0});
    }
    return _sync();
  }

  /// Press and hold the left button. Moves to [element] first when given.
  Actions clickAndHold([ElementLike? element]) {
    if (element != null) moveToElement(element);
    _pointer.add({'type': 'pointerDown', 'button': 0});
    return _sync();
  }

  /// Release the left button. Moves to [element] first when given.
  Actions release([ElementLike? element]) {
    if (element != null) moveToElement(element);
    _pointer.add({'type': 'pointerUp', 'button': 0});
    return _sync();
  }

  /// Press at [source], move onto [target], and release — a drag-and-drop.
  Actions dragAndDrop(ElementLike source, ElementLike target) {
    clickAndHold(source);
    moveToElement(target);
    release();
    return this;
  }

  // ---- key gestures ----

  /// Press [key] down (a modifier held for subsequent gestures). Clicks
  /// [element] first when given (to focus it).
  Actions keyDown(String key, [ElementLike? element]) {
    if (element != null) click(element);
    _key.add({'type': 'keyDown', 'value': key});
    return _sync();
  }

  /// Release [key].
  Actions keyUp(String key, [ElementLike? element]) {
    _key.add({'type': 'keyUp', 'value': key});
    return _sync();
  }

  /// Type [keys] — each code unit becomes a keyDown/keyUp pair.
  Actions sendKeys(String keys) {
    for (final ch in keys.split('')) {
      _key.add({'type': 'keyDown', 'value': ch});
      _key.add({'type': 'keyUp', 'value': ch});
    }
    return _sync();
  }

  /// A [seconds]-long pause on the pointer device.
  Actions pause(double seconds) {
    _pointer.add({'type': 'pause', 'duration': (seconds * 1000).round()});
    return _sync();
  }

  // ---- terminal ----

  /// The W3C `actions` array this builder has accumulated (a device object per
  /// non-empty device). Exposed for inspection/testing; [perform] posts it.
  List<Map<String, dynamic>> toW3c() {
    final actions = <Map<String, dynamic>>[];
    if (_pointer.any((a) => a['type'] != 'pause')) {
      actions.add({
        'type': 'pointer',
        'id': 'mouse',
        'parameters': {'pointerType': 'mouse'},
        'actions': List<Map<String, dynamic>>.from(_pointer),
      });
    }
    if (_key.any((a) => a['type'] != 'pause')) {
      actions.add({
        'type': 'key',
        'id': 'keyboard',
        'actions': List<Map<String, dynamic>>.from(_key),
      });
    }
    return actions;
  }

  /// Post the accumulated gesture sequence in one `actions` command.
  void perform() {
    final actions = toW3c();
    if (actions.isNotEmpty) _driver.performActions(actions);
  }

  /// W3C requires every device's action list to be the same length; pad the
  /// shorter with zero-duration pauses so gestures don't desync ticks.
  Actions _sync() {
    final n = _pointer.length > _key.length ? _pointer.length : _key.length;
    while (_pointer.length < n) {
      _pointer.add({'type': 'pause', 'duration': 0});
    }
    while (_key.length < n) {
      _key.add({'type': 'pause', 'duration': 0});
    }
    return this;
  }
}
