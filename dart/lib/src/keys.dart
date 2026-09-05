/// Special keys, the Dart face of mainstream Selenium's `Keys`.
///
/// These are the W3C WebDriver Unicode private-use code points (§17.4.2) for
/// non-text keys. Send them through [WebElement.sendKeys] or the [Actions]
/// builder exactly as in mainstream Selenium — the values are the same code
/// points the protocol defines, so the engine forwards them unchanged.
///
/// ```dart
/// driver.findElement(By.name('q')).sendKeys('selenium${Keys.enter}');
/// ```
library;

/// The W3C Unicode PUA key constants. camelCase to match Dart conventions;
/// the code points are identical to mainstream Selenium's `Keys`.
class Keys {
  Keys._();

  static const String nul = '';
  static const String cancel = '';
  static const String help = '';
  static const String backspace = '';
  static const String backSpace = backspace;
  static const String tab = '';
  static const String clear = '';
  static const String returnKey = '';
  static const String enter = '';
  static const String shift = '';
  static const String leftShift = shift;
  static const String control = '';
  static const String leftControl = control;
  static const String alt = '';
  static const String leftAlt = alt;
  static const String pause = '';
  static const String escape = '';
  static const String space = '';
  static const String pageUp = '';
  static const String pageDown = '';
  static const String end = '';
  static const String home = '';
  static const String left = '';
  static const String arrowLeft = left;
  static const String up = '';
  static const String arrowUp = up;
  static const String right = '';
  static const String arrowRight = right;
  static const String down = '';
  static const String arrowDown = down;
  static const String insert = '';
  static const String delete = '';
  static const String semicolon = '';
  static const String equals = '';

  static const String numpad0 = '';
  static const String numpad1 = '';
  static const String numpad2 = '';
  static const String numpad3 = '';
  static const String numpad4 = '';
  static const String numpad5 = '';
  static const String numpad6 = '';
  static const String numpad7 = '';
  static const String numpad8 = '';
  static const String numpad9 = '';
  static const String multiply = '';
  static const String add = '';
  static const String separator = '';
  static const String subtract = '';
  static const String decimal = '';
  static const String divide = '';

  static const String f1 = '';
  static const String f2 = '';
  static const String f3 = '';
  static const String f4 = '';
  static const String f5 = '';
  static const String f6 = '';
  static const String f7 = '';
  static const String f8 = '';
  static const String f9 = '';
  static const String f10 = '';
  static const String f11 = '';
  static const String f12 = '';

  static const String meta = '';
  static const String command = '';

  /// The classic `Keys.chord` helper: concatenate [keys] and append [nul] so
  /// the browser releases every held modifier at the end of the sequence. Send
  /// the result through [WebElement.sendKeys], e.g.
  /// `element.sendKeys(Keys.chord([Keys.control, 'a']))` to select-all.
  static String chord(List<String> keys) => keys.join() + nul;
}
