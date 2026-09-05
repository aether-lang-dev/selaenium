package org.openqa.selenium;

import java.util.Objects;

/**
 * An (x, y) position value class. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.Point} (public final fields plus getters).
 */
public class Point {

  public final int x;
  public final int y;

  public Point(int x, int y) {
    this.x = x;
    this.y = y;
  }

  public int getX() {
    return x;
  }

  public int getY() {
    return y;
  }

  public Point moveBy(int xOffset, int yOffset) {
    return new Point(x + xOffset, y + yOffset);
  }

  @Override
  public boolean equals(Object o) {
    if (!(o instanceof Point)) {
      return false;
    }
    Point other = (Point) o;
    return other.x == x && other.y == y;
  }

  @Override
  public int hashCode() {
    return Objects.hash(x, y);
  }

  @Override
  public String toString() {
    return String.format("(%d, %d)", x, y);
  }
}
