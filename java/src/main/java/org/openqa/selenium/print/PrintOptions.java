package org.openqa.selenium.print;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Options for {@code driver.print(...)} (the W3C print-page command). Mirrors
 * mainstream Selenium's {@code org.openqa.selenium.print.PrintOptions}: a mutable
 * builder whose {@link #toMap()} is the exact params object sent to the engine.
 */
public class PrintOptions {

  public enum Orientation {
    PORTRAIT("portrait"),
    LANDSCAPE("landscape");

    private final String serialFormat;

    Orientation(String serialFormat) {
      this.serialFormat = serialFormat;
    }

    @Override
    public String toString() {
      return serialFormat;
    }
  }

  private Orientation orientation = Orientation.PORTRAIT;
  private double scale = 1.0;
  private boolean background = false;
  private boolean shrinkToFit = true;
  private String[] pageRanges = null;
  private PageSize pageSize = new PageSize();
  private PageMargin pageMargin = new PageMargin();

  public Orientation getOrientation() {
    return orientation;
  }

  public PrintOptions setOrientation(Orientation orientation) {
    this.orientation = orientation;
    return this;
  }

  public double getScale() {
    return scale;
  }

  public PrintOptions setScale(double scale) {
    if (scale < 0.1 || scale > 2.0) {
      throw new IllegalArgumentException("Scale value should be between 0.1 and 2.0");
    }
    this.scale = scale;
    return this;
  }

  public boolean getBackground() {
    return background;
  }

  public PrintOptions setBackground(boolean background) {
    this.background = background;
    return this;
  }

  public boolean getShrinkToFit() {
    return shrinkToFit;
  }

  public PrintOptions setShrinkToFit(boolean value) {
    this.shrinkToFit = value;
    return this;
  }

  public String[] getPageRanges() {
    return pageRanges;
  }

  public PrintOptions setPageRanges(String firstRange, String... ranges) {
    pageRanges = new String[ranges.length + 1];
    pageRanges[0] = firstRange;
    System.arraycopy(ranges, 0, pageRanges, 1, ranges.length);
    return this;
  }

  public PrintOptions setPageRanges(List<String> ranges) {
    pageRanges = ranges.toArray(new String[0]);
    return this;
  }

  public PageSize getPageSize() {
    return pageSize;
  }

  public PrintOptions setPageSize(PageSize pageSize) {
    this.pageSize = pageSize;
    return this;
  }

  public PageMargin getPageMargin() {
    return pageMargin;
  }

  public PrintOptions setPageMargin(PageMargin margin) {
    this.pageMargin = margin;
    return this;
  }

  /** The exact params object for the W3C {@code print} command. */
  public Map<String, Object> toMap() {
    Map<String, Object> options = new HashMap<>(7);
    options.put("page", pageSize.toMap());
    options.put("orientation", orientation.toString());
    options.put("scale", scale);
    options.put("shrinkToFit", shrinkToFit);
    options.put("background", background);
    if (pageRanges != null) {
      options.put("pageRanges", Arrays.asList(pageRanges));
    }
    options.put("margin", pageMargin.toMap());
    return options;
  }
}
