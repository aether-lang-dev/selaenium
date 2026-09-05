package org.openqa.selenium;

import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;

/**
 * A mutable {@link Capabilities} bag. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.MutableCapabilities}: accumulate capabilities with
 * {@code setCapability}, and (as upstream) an option block set under one of the
 * known browser-options keys is flattened when the value is itself a
 * {@link Capabilities}. {@code ChromeOptions} extends this class.
 */
public class MutableCapabilities implements Capabilities {

  private static final Set<String> OPTION_KEYS;

  static {
    HashSet<String> keys = new HashSet<>();
    keys.add("goog:chromeOptions");
    keys.add("ms:edgeOptions");
    keys.add("moz:firefoxOptions");
    keys.add("se:ieOptions");
    OPTION_KEYS = Collections.unmodifiableSet(keys);
  }

  private final Map<String, Object> caps = new TreeMap<>();

  public MutableCapabilities() {}

  public MutableCapabilities(Capabilities other) {
    this(other.asMap());
  }

  public MutableCapabilities(Map<String, ?> capabilities) {
    capabilities.forEach(
        (key, value) -> {
          if (value != null) {
            setCapability(key, value);
          }
        });
  }

  @Override
  public MutableCapabilities merge(Capabilities other) {
    MutableCapabilities newInstance = new MutableCapabilities(this);
    if (other != null) {
      other.asMap().forEach(newInstance::setCapability);
    }
    return newInstance;
  }

  public void setCapability(String capabilityName, boolean value) {
    setCapability(capabilityName, (Object) value);
  }

  public void setCapability(String capabilityName, String value) {
    setCapability(capabilityName, (Object) value);
  }

  public void setCapability(String key, Object value) {
    Objects.requireNonNull(key, "Capability name must not be null");
    if (OPTION_KEYS.contains(key) && value instanceof Capabilities) {
      ((Capabilities) value).asMap().forEach(this::setCapability);
      return;
    }
    if (value == null) {
      caps.remove(key);
      return;
    }
    caps.put(key, value);
  }

  @Override
  public Map<String, Object> asMap() {
    return Collections.unmodifiableMap(caps);
  }

  @Override
  public Object getCapability(String capabilityName) {
    return caps.get(capabilityName);
  }

  @Override
  public Set<String> getCapabilityNames() {
    return Collections.unmodifiableSet(caps.keySet());
  }

  public Map<String, Object> toJson() {
    return asMap();
  }

  @Override
  public int hashCode() {
    return caps.hashCode();
  }

  @Override
  public boolean equals(Object o) {
    if (!(o instanceof Capabilities)) {
      return false;
    }
    return asMap().equals(((Capabilities) o).asMap());
  }

  @Override
  public String toString() {
    return "Capabilities " + asMap();
  }
}
