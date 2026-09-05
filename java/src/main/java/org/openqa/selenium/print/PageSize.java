package org.openqa.selenium.print;

import java.util.HashMap;
import java.util.Map;

/**
 * The paper size for {@link PrintOptions}, in centimetres (the unit the W3C
 * print command expects). Mirrors mainstream Selenium's
 * {@code org.openqa.selenium.print.PageSize}, including the standard presets.
 */
public class PageSize {

  private final double height;
  private final double width;

  // Standard sizes in cm (height, width), matching mainstream.
  public static final PageSize ISO_A4 = new PageSize(29.7, 21.0);
  public static final PageSize US_LEGAL = new PageSize(35.56, 21.59);
  public static final PageSize ANSI_TABLOID = new PageSize(43.18, 27.94);
  public static final PageSize US_LETTER = new PageSize(27.94, 21.59);

  /** Default page size (ISO A4). */
  public PageSize() {
    this(29.7, 21.0);
  }

  public PageSize(double height, double width) {
    this.height = height;
    this.width = width;
  }

  public double getHeight() {
    return height;
  }

  public double getWidth() {
    return width;
  }

  public Map<String, Object> toMap() {
    Map<String, Object> map = new HashMap<>(2);
    map.put("height", height);
    map.put("width", width);
    return map;
  }
}
