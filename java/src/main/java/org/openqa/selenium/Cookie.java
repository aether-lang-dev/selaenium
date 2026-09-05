package org.openqa.selenium;

import java.io.Serializable;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Map;
import java.util.Objects;
import java.util.TimeZone;
import java.util.TreeMap;

/**
 * A browser cookie. Mirrors Selenium 4.x's {@code org.openqa.selenium.Cookie}:
 * the same constructor overloads, getters, {@link #toJson()} shape and
 * {@link Builder}. Two cookies are equal when their names and values match.
 */
public class Cookie implements Serializable {

  private static final long serialVersionUID = 4115876353625612383L;

  private final String name;
  private final String value;
  private final String path;
  private final String domain;
  private final Date expiry;
  private final boolean isSecure;
  private final boolean isHttpOnly;
  private final String sameSite;

  public Cookie(String name, String value, String path, Date expiry) {
    this(name, value, null, path, expiry);
  }

  public Cookie(String name, String value, String domain, String path, Date expiry) {
    this(name, value, domain, path, expiry, false);
  }

  public Cookie(String name, String value, String domain, String path, Date expiry, boolean isSecure) {
    this(name, value, domain, path, expiry, isSecure, false);
  }

  public Cookie(
      String name,
      String value,
      String domain,
      String path,
      Date expiry,
      boolean isSecure,
      boolean isHttpOnly) {
    this(name, value, domain, path, expiry, isSecure, isHttpOnly, null);
  }

  public Cookie(
      String name,
      String value,
      String domain,
      String path,
      Date expiry,
      boolean isSecure,
      boolean isHttpOnly,
      String sameSite) {
    this.name = name;
    this.value = value;
    this.path = path == null || path.isEmpty() ? "/" : path;
    this.domain = stripPort(domain);
    this.isSecure = isSecure;
    this.isHttpOnly = isHttpOnly;
    if (expiry != null) {
      this.expiry = new Date(expiry.getTime() / 1000 * 1000);
    } else {
      this.expiry = null;
    }
    this.sameSite = sameSite;
  }

  public Cookie(String name, String value) {
    this(name, value, "/", null);
  }

  public Cookie(String name, String value, String path) {
    this(name, value, path, null);
  }

  public String getName() {
    return name;
  }

  public String getValue() {
    return value;
  }

  public String getDomain() {
    return domain;
  }

  public String getPath() {
    return path;
  }

  public boolean isSecure() {
    return isSecure;
  }

  public boolean isHttpOnly() {
    return isHttpOnly;
  }

  public Date getExpiry() {
    return expiry == null ? null : new Date(expiry.getTime());
  }

  public String getSameSite() {
    return sameSite;
  }

  private static String stripPort(String domain) {
    return (domain == null) ? null : domain.split(":")[0];
  }

  public void validate() {
    if (name == null || name.isEmpty()) {
      throw new IllegalArgumentException("Name must not be empty");
    }
    Objects.requireNonNull(value, "Value must not be null");
    Objects.requireNonNull(path, "Path must not be null");
    if (name.indexOf(';') != -1) {
      throw new IllegalArgumentException("Cookie names cannot contain a ';': " + name);
    }
    if (domain != null && domain.contains(":")) {
      throw new IllegalArgumentException("Domain should not contain a port: " + domain);
    }
  }

  /**
   * The W3C cookie-conversion object. Keys match
   * https://w3c.github.io/webdriver/#dfn-table-for-cookie-conversion.
   */
  public Map<String, Object> toJson() {
    Map<String, Object> toReturn = new TreeMap<>();
    if (getDomain() != null) {
      toReturn.put("domain", getDomain());
    }
    if (getExpiry() != null) {
      toReturn.put("expiry", getExpiry());
    }
    if (getName() != null) {
      toReturn.put("name", getName());
    }
    if (getPath() != null) {
      toReturn.put("path", getPath());
    }
    if (getValue() != null) {
      toReturn.put("value", getValue());
    }
    toReturn.put("secure", isSecure());
    toReturn.put("httpOnly", isHttpOnly());
    if (getSameSite() != null) {
      toReturn.put("sameSite", getSameSite());
    }
    return toReturn;
  }

  @Override
  public String toString() {
    SimpleDateFormat sdf = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z");
    sdf.setTimeZone(TimeZone.getTimeZone("GMT"));
    return name
        + "="
        + value
        + (expiry == null ? "" : "; expires=" + sdf.format(expiry))
        + ("".equals(path) ? "" : "; path=" + path)
        + (domain == null ? "" : "; domain=" + domain)
        + (isSecure ? ";secure;" : "")
        + (sameSite == null ? "" : "; sameSite=" + sameSite);
  }

  @Override
  public boolean equals(Object o) {
    if (this == o) {
      return true;
    }
    if (!(o instanceof Cookie)) {
      return false;
    }
    Cookie cookie = (Cookie) o;
    if (!name.equals(cookie.name)) {
      return false;
    }
    return Objects.equals(value, cookie.value);
  }

  @Override
  public int hashCode() {
    return name.hashCode();
  }

  public static class Builder {
    private final String name;
    private final String value;
    private String path;
    private String domain;
    private Date expiry;
    private boolean secure;
    private boolean httpOnly;
    private String sameSite;

    public Builder(String name, String value) {
      this.name = name;
      this.value = value;
    }

    public Builder domain(String host) {
      this.domain = stripPort(host);
      return this;
    }

    public Builder path(String path) {
      this.path = path;
      return this;
    }

    public Builder expiresOn(Date expiry) {
      this.expiry = expiry == null ? null : new Date(expiry.getTime());
      return this;
    }

    public Builder isSecure(boolean secure) {
      this.secure = secure;
      return this;
    }

    public Builder isHttpOnly(boolean httpOnly) {
      this.httpOnly = httpOnly;
      return this;
    }

    public Builder sameSite(String sameSite) {
      this.sameSite = sameSite;
      return this;
    }

    public Cookie build() {
      return new Cookie(name, value, domain, path, expiry, secure, httpOnly, sameSite);
    }
  }
}
