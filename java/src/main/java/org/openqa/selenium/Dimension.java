package org.openqa.selenium;

import java.util.Objects;

/**
 * A width/height value class. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.Dimension} (public final fields plus getters).
 */
public class Dimension {

  public final int width;
  public final int height;

  public Dimension(int width, int height) {
    this.width = width;
    this.height = height;
  }

  public int getWidth() {
    return width;
  }

  public int getHeight() {
    return height;
  }

  @Override
  public boolean equals(Object o) {
    if (!(o instanceof Dimension)) {
      return false;
    }
    Dimension other = (Dimension) o;
    return other.width == width && other.height == height;
  }

  @Override
  public int hashCode() {
    return Objects.hash(width, height);
  }

  @Override
  public String toString() {
    return String.format("(%d, %d)", width, height);
  }
}
