package org.openqa.selenium;

import java.util.Collections;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;

/**
 * An unmodifiable {@link Capabilities} bag. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.ImmutableCapabilities}, including the varargs-style
 * key/value constructors and {@link #copyOf(Capabilities)}.
 */
public class ImmutableCapabilities implements Capabilities {

  private final Map<String, Object> delegate;

  public ImmutableCapabilities() {
    this.delegate = Collections.emptyMap();
  }

  public ImmutableCapabilities(String k, Object v) {
    Objects.requireNonNull(k, "Capability must not be null");
    Objects.requireNonNull(v, "Value must not be null");
    Map<String, Object> d = new TreeMap<>();
    d.put(k, v);
    this.delegate = Collections.unmodifiableMap(d);
  }

  public ImmutableCapabilities(String k1, Object v1, String k2, Object v2) {
    Map<String, Object> d = new TreeMap<>();
    d.put(Objects.requireNonNull(k1), Objects.requireNonNull(v1));
    d.put(Objects.requireNonNull(k2), Objects.requireNonNull(v2));
    this.delegate = Collections.unmodifiableMap(d);
  }

  public ImmutableCapabilities(String k1, Object v1, String k2, Object v2, String k3, Object v3) {
    Map<String, Object> d = new TreeMap<>();
    d.put(Objects.requireNonNull(k1), Objects.requireNonNull(v1));
    d.put(Objects.requireNonNull(k2), Objects.requireNonNull(v2));
    d.put(Objects.requireNonNull(k3), Objects.requireNonNull(v3));
    this.delegate = Collections.unmodifiableMap(d);
  }

  public ImmutableCapabilities(
      String k1, Object v1, String k2, Object v2, String k3, Object v3, String k4, Object v4) {
    Map<String, Object> d = new TreeMap<>();
    d.put(Objects.requireNonNull(k1), Objects.requireNonNull(v1));
    d.put(Objects.requireNonNull(k2), Objects.requireNonNull(v2));
    d.put(Objects.requireNonNull(k3), Objects.requireNonNull(v3));
    d.put(Objects.requireNonNull(k4), Objects.requireNonNull(v4));
    this.delegate = Collections.unmodifiableMap(d);
  }

  public ImmutableCapabilities(
      String k1, Object v1, String k2, Object v2, String k3, Object v3, String k4, Object v4,
      String k5, Object v5) {
    Map<String, Object> d = new TreeMap<>();
    d.put(Objects.requireNonNull(k1), Objects.requireNonNull(v1));
    d.put(Objects.requireNonNull(k2), Objects.requireNonNull(v2));
    d.put(Objects.requireNonNull(k3), Objects.requireNonNull(v3));
    d.put(Objects.requireNonNull(k4), Objects.requireNonNull(v4));
    d.put(Objects.requireNonNull(k5), Objects.requireNonNull(v5));
    this.delegate = Collections.unmodifiableMap(d);
  }

  public ImmutableCapabilities(Capabilities other) {
    this(other.asMap());
  }

  public ImmutableCapabilities(Map<?, ?> capabilities) {
    Objects.requireNonNull(capabilities, "Capabilities must not be null");
    Map<String, Object> d = new TreeMap<>();
    capabilities.forEach(
        (key, value) -> {
          Objects.requireNonNull(value, "Capability value must not be null");
          d.put(String.valueOf(key), value);
        });
    this.delegate = Collections.unmodifiableMap(d);
  }

  @Override
  public Object getCapability(String capabilityName) {
    Objects.requireNonNull(capabilityName, "Capability name must not be null");
    return delegate.get(capabilityName);
  }

  @Override
  public Map<String, Object> asMap() {
    return delegate;
  }

  @Override
  public int hashCode() {
    return delegate.hashCode();
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

  public static ImmutableCapabilities copyOf(Capabilities capabilities) {
    Objects.requireNonNull(capabilities, "Capabilities must not be null");
    if (capabilities instanceof ImmutableCapabilities) {
      return (ImmutableCapabilities) capabilities;
    }
    return new ImmutableCapabilities(capabilities);
  }
}
