package org.openqa.selenium.print;

import java.util.HashMap;
import java.util.Map;

/**
 * The page margins for {@link PrintOptions}, in centimetres. Mirrors mainstream
 * Selenium's {@code org.openqa.selenium.print.PageMargin} (default 1cm on every
 * side).
 */
public class PageMargin {

  private final double top;
  private final double bottom;
  private final double left;
  private final double right;

  public PageMargin() {
    this(1.0, 1.0, 1.0, 1.0);
  }

  public PageMargin(double top, double bottom, double left, double right) {
    this.top = top;
    this.bottom = bottom;
    this.left = left;
    this.right = right;
  }

  public double getTop() {
    return top;
  }

  public double getBottom() {
    return bottom;
  }

  public double getLeft() {
    return left;
  }

  public double getRight() {
    return right;
  }

  public Map<String, Object> toMap() {
    Map<String, Object> map = new HashMap<>(4);
    map.put("top", top);
    map.put("bottom", bottom);
    map.put("left", left);
    map.put("right", right);
    return map;
  }
}
