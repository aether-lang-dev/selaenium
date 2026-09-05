/// `<select>` dropdown helper — the Dart face of mainstream Selenium's
/// `Select`.
///
/// Wraps a `<select>` [WebElement] and drives it by finding and clicking its
/// `<option>` children — the same approach mainstream Selenium uses.
///
/// ```dart
/// Select(driver.findElement(By.id('country'))).selectByVisibleText('Spain');
/// ```
library;

import 'webdriver.dart';

/// Drives a native `<select>` element by selecting its `<option>` children.
class Select {
  final ElementLike _el;

  /// Whether this is a multi-select (`<select multiple>`).
  final bool isMultiple;

  /// Wraps [element]; throws [ArgumentError] if it is not a `<select>`.
  Select(ElementLike element)
      : _el = element,
        isMultiple = _computeMultiple(element) {
    final tag = element.tagName.toLowerCase();
    if (tag != 'select') {
      throw ArgumentError('Select only works on <select> elements, not <$tag>');
    }
  }

  static bool _computeMultiple(ElementLike element) {
    final multi = element.getAttribute('multiple');
    if (multi == null) return false;
    if (multi is bool) return multi;
    return multi.toString().isNotEmpty && multi.toString() != 'false';
  }

  /// All `<option>` children, in document order.
  List<ElementLike> get options => _el.findElements(By.tagName('option'));

  /// The `<option>` children that are currently selected.
  List<ElementLike> get allSelectedOptions =>
      options.where((o) => o.isSelected()).toList();

  /// The first selected `<option>`; throws [NoSuchElementException] if none is.
  ElementLike get firstSelectedOption {
    for (final o in options) {
      if (o.isSelected()) return o;
    }
    throw NoSuchElementException('no option is selected', 17);
  }

  /// Select the option whose visible text equals [text].
  void selectByVisibleText(String text) {
    for (final o in options) {
      if (o.text == text) {
        _select(o);
        return;
      }
    }
    throw NoSuchElementException('no option with visible text "$text"', 17);
  }

  /// Select the option whose `value` attribute equals [value].
  void selectByValue(String value) {
    for (final o in options) {
      if (o.getAttribute('value') == value) {
        _select(o);
        return;
      }
    }
    throw NoSuchElementException('no option with value "$value"', 17);
  }

  /// Select the option at position [index] (0-based).
  void selectByIndex(int index) {
    final opts = options;
    if (index < 0 || index >= opts.length) {
      throw NoSuchElementException('no option at index $index', 17);
    }
    _select(opts[index]);
  }

  /// Deselect every option (multi-select only).
  void deselectAll() {
    if (!isMultiple) {
      throw StateError('deselectAll only makes sense on a multi-select');
    }
    for (final o in options) {
      if (o.isSelected()) o.click();
    }
  }

  void _select(ElementLike option) {
    if (!option.isSelected()) option.click();
  }
}
