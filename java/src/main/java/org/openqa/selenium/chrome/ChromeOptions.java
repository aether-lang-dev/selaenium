package org.openqa.selenium.chrome;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.openqa.selenium.Capabilities;
import org.openqa.selenium.MutableCapabilities;

/**
 * Chrome/Chromium options. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.chrome.ChromeOptions}: collect {@code --flags} via
 * {@link #addArguments}, experimental options via {@link #setExperimentalOption},
 * and a binary path via {@link #setBinary}; {@link #asMap()} assembles the W3C
 * capabilities with a {@code goog:chromeOptions} block, exactly as upstream. A
 * {@code new RemoteWebDriver(url, options)} in this binding reads {@link #asMap()}.
 *
 * <p>Extends {@link MutableCapabilities} (per the binding's simplified option
 * hierarchy) rather than the upstream {@code ChromiumOptions} class; the
 * user-visible method surface a program touches is the same.
 */
public class ChromeOptions extends MutableCapabilities {

  /** Key used to store a set of ChromeOptions in a capabilities object. */
  public static final String CAPABILITY = "goog:chromeOptions";

  public static final String LOGGING_PREFS = "goog:loggingPrefs";

  private final List<String> args = new ArrayList<>();
  private final List<String> extensionFiles = new ArrayList<>();
  private final Map<String, Object> experimentalOptions = new TreeMap<>();
  private String binary;

  public ChromeOptions() {
    setCapability("browserName", "chrome");
  }

  /** Add one or more command-line arguments (e.g. {@code --headless=new}). */
  public ChromeOptions addArguments(String... arguments) {
    return addArguments(Arrays.asList(arguments));
  }

  public ChromeOptions addArguments(List<String> arguments) {
    args.addAll(arguments);
    return this;
  }

  /** Path to the Chrome/Chromium binary to launch. */
  public ChromeOptions setBinary(String path) {
    binary = path;
    return this;
  }

  /** Set an experimental option passed under {@code goog:chromeOptions}. */
  public ChromeOptions setExperimentalOption(String name, Object value) {
    experimentalOptions.put(name, value);
    return this;
  }

  public Object getExperimentalOption(String name) {
    return experimentalOptions.get(name);
  }

  /** Add extension file paths (as absolute paths). */
  public ChromeOptions addExtensions(String... paths) {
    extensionFiles.addAll(Arrays.asList(paths));
    return this;
  }

  @Override
  public ChromeOptions merge(Capabilities extraCapabilities) {
    ChromeOptions newInstance = new ChromeOptions();
    for (String name : this.getCapabilityNames()) {
      newInstance.setCapability(name, this.getCapability(name));
    }
    newInstance.args.addAll(this.args);
    newInstance.extensionFiles.addAll(this.extensionFiles);
    newInstance.experimentalOptions.putAll(this.experimentalOptions);
    newInstance.binary = this.binary;
    if (extraCapabilities != null) {
      extraCapabilities.asMap().forEach(newInstance::setCapability);
    }
    return newInstance;
  }

  /** The {@code goog:chromeOptions} block this options object accumulated. */
  private Map<String, Object> chromeOptionsBlock() {
    Map<String, Object> block = new TreeMap<>(experimentalOptions);
    block.put("args", new ArrayList<>(args));
    if (!extensionFiles.isEmpty()) {
      block.put("extensions", new ArrayList<>(extensionFiles));
    }
    if (binary != null) {
      block.put("binary", binary);
    }
    return block;
  }

  @Override
  public Map<String, Object> asMap() {
    Map<String, Object> caps = new TreeMap<>(super.asMap());
    caps.put(CAPABILITY, chromeOptionsBlock());
    return Collections.unmodifiableMap(caps);
  }

  @Override
  public Object getCapability(String capabilityName) {
    if (CAPABILITY.equals(capabilityName)) {
      return chromeOptionsBlock();
    }
    return super.getCapability(capabilityName);
  }

  /** The W3C capabilities dict, including the {@code goog:chromeOptions} block. */
  public Map<String, Object> toCapabilities() {
    return asMap();
  }
}
