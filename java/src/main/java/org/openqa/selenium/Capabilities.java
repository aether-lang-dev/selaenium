package org.openqa.selenium;

import java.io.Serializable;
import java.util.Collections;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * A read view over a set of WebDriver capabilities. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.Capabilities}: {@link #asMap()} /
 * {@link #getCapability(String)} are the primitives, and the default helpers
 * ({@link #getBrowserName()}, {@link #is(String)}, {@link #merge(Capabilities)},
 * …) are computed from them.
 */
public interface Capabilities extends Serializable {

  default String getBrowserName() {
    return String.valueOf(Optional.ofNullable(getCapability("browserName")).orElse(""));
  }

  default String getBrowserVersion() {
    return String.valueOf(Optional.ofNullable(getCapability("browserVersion")).orElse(""));
  }

  /** @return the capabilities as a map. */
  Map<String, Object> asMap();

  /**
   * @param capabilityName the capability to return
   * @return the value, or null if not set
   */
  Object getCapability(String capabilityName);

  @SuppressWarnings("unchecked")
  default <T> T get(String capabilityName) {
    return (T) getCapability(capabilityName);
  }

  /**
   * @param capabilityName the capability to check
   * @return whether the value is not null and not false
   */
  default boolean is(String capabilityName) {
    Object cap = getCapability(capabilityName);
    if (cap == null) {
      return false;
    }
    return cap instanceof Boolean ? (Boolean) cap : Boolean.parseBoolean(String.valueOf(cap));
  }

  /**
   * Merge two {@link Capabilities} together and return the union as a new
   * instance. Capabilities from {@code other} override those in {@code this}.
   */
  default Capabilities merge(Capabilities other) {
    return new ImmutableCapabilities(new MutableCapabilities(this).merge(other));
  }

  default Set<String> getCapabilityNames() {
    return Collections.unmodifiableSet(asMap().keySet());
  }
}
