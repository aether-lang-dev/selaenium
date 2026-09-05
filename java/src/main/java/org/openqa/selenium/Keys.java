package org.openqa.selenium;

import java.util.List;

/**
 * Special (non-text) keys as W3C Unicode private-use code points. Mirrors
 * Selenium 4.x's {@code org.openqa.selenium.Keys}: an enum that is itself a
 * {@link CharSequence}, so a constant like {@code Keys.ENTER} flows straight into
 * {@code element.sendKeys(Keys.ENTER)}. The code points are exactly those the
 * protocol defines; the engine forwards them unchanged.
 */
public enum Keys implements CharSequence {

  // Basic control characters
  NULL(''),
  CANCEL(''), // ^break
  HELP(''),
  BACK_SPACE(''),
  TAB(''),
  CLEAR(''),
  RETURN(''),
  ENTER(''),
  SHIFT(''),
  LEFT_SHIFT(Keys.SHIFT),
  CONTROL(''),
  LEFT_CONTROL(Keys.CONTROL),
  ALT(''),
  LEFT_ALT(Keys.ALT),
  PAUSE(''),
  ESCAPE(''),
  SPACE(''),
  PAGE_UP(''),
  PAGE_DOWN(''),
  END(''),
  HOME(''),
  LEFT(''),
  ARROW_LEFT(Keys.LEFT),
  UP(''),
  ARROW_UP(Keys.UP),
  RIGHT(''),
  ARROW_RIGHT(Keys.RIGHT),
  DOWN(''),
  ARROW_DOWN(Keys.DOWN),
  INSERT(''),
  DELETE(''),
  SEMICOLON(''),
  EQUALS(''),

  // Number pad keys
  NUMPAD0(''),
  NUMPAD1(''),
  NUMPAD2(''),
  NUMPAD3(''),
  NUMPAD4(''),
  NUMPAD5(''),
  NUMPAD6(''),
  NUMPAD7(''),
  NUMPAD8(''),
  NUMPAD9(''),
  MULTIPLY(''),
  ADD(''),
  SEPARATOR(''),
  SUBTRACT(''),
  DECIMAL(''),
  DIVIDE(''),

  // Function keys
  F1(''),
  F2(''),
  F3(''),
  F4(''),
  F5(''),
  F6(''),
  F7(''),
  F8(''),
  F9(''),
  F10(''),
  F11(''),
  F12(''),

  META(''),
  COMMAND(Keys.META),

  // Extended macOS/ChromeDriver keys (based on observed Chrome usage)
  RIGHT_SHIFT(''),
  RIGHT_CONTROL(''),
  RIGHT_ALT(''),
  RIGHT_COMMAND(''),

  // macOS-friendly alias (do NOT introduce new codes)
  OPTION(Keys.ALT),

  /**
   * @deprecated FN has no distinct protocol code point; it aliases RIGHT_CONTROL
   *     purely for source compatibility with upstream.
   */
  @Deprecated
  FN(Keys.RIGHT_CONTROL),

  ZENKAKU_HANKAKU('');

  private final char keyCode;
  private final int codePoint;

  Keys(Keys key) {
    this(key.charAt(0));
  }

  Keys(char keyCode) {
    this.keyCode = keyCode;
    this.codePoint = String.valueOf(keyCode).codePoints().findFirst().getAsInt();
  }

  public int getCodePoint() {
    return codePoint;
  }

  @Override
  public char charAt(int index) {
    if (index != 0) {
      throw new IndexOutOfBoundsException("Index: " + index + ", Length: 1");
    }
    return keyCode;
  }

  @Override
  public int length() {
    return 1;
  }

  @Override
  public CharSequence subSequence(int start, int end) {
    if (start == 0 && end == 1) {
      return String.valueOf(keyCode);
    }
    throw new IndexOutOfBoundsException();
  }

  @Override
  public String toString() {
    return String.valueOf(keyCode);
  }

  /**
   * Concatenate a sequence of keys and append {@link #NULL} (which releases any
   * modifiers) — the mainstream {@code Keys.chord(...)}.
   */
  public static String chord(CharSequence... value) {
    return chord(List.of(value));
  }

  public static String chord(Iterable<CharSequence> value) {
    StringBuilder builder = new StringBuilder();
    for (CharSequence seq : value) {
      builder.append(seq);
    }
    builder.append(Keys.NULL);
    return builder.toString();
  }

  /** The {@link Keys} constant for a code point, or null if none matches. */
  public static Keys getKeyFromUnicode(char key) {
    for (Keys unicodeKey : values()) {
      if (unicodeKey.charAt(0) == key) {
        return unicodeKey;
      }
    }
    return null;
  }
}
