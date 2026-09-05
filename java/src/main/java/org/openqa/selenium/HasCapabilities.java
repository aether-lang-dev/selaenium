package org.openqa.selenium;

/**
 * Implemented by drivers that can report the capabilities their session was
 * created with. Mirrors Selenium 4.x's {@code org.openqa.selenium.HasCapabilities}.
 */
public interface HasCapabilities {

  /** The capabilities the remote end negotiated for this session. */
  Capabilities getCapabilities();
}
