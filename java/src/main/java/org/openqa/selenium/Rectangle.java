package org.openqa.selenium;

import java.util.Objects;

/**
 * An (x, y, width, height) rectangle value class. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.Rectangle} (public final fields plus getters and
 * the {@code (Point, Dimension)} constructor).
 */
public class Rectangle {

  public final int x;
  public final int y;
  public final int height;
  public final int width;

  public Rectangle(int x, int y, int height, int width) {
    this.x = x;
    this.y = y;
    this.height = height;
    this.width = width;
  }

  public Rectangle(Point p, Dimension d) {
    x = p.x;
    y = p.y;
    height = d.height;
    width = d.width;
  }

  public int getX() {
    return x;
  }

  public int getY() {
    return y;
  }

  public int getHeight() {
    return height;
  }

  public int getWidth() {
    return width;
  }

  public Point getPoint() {
    return new Point(x, y);
  }

  public Dimension getDimension() {
    return new Dimension(width, height);
  }

  @Override
  public boolean equals(Object o) {
    if (this == o) {
      return true;
    }
    if (o == null || getClass() != o.getClass()) {
      return false;
    }
    Rectangle rectangle = (Rectangle) o;
    return x == rectangle.x
        && y == rectangle.y
        && height == rectangle.height
        && width == rectangle.width;
  }

  @Override
  public int hashCode() {
    return Objects.hash(x, y, height, width);
  }
}
