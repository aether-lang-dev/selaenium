# selenium-client (Java) — the JVM engine jar

Selenium WebDriver for Java — a thin Panama FFM (`java.lang.foreign`) binding over
the shared pure-Aether WebDriver engine (`libselenium_core`), in the mainstream
`org.openqa.selenium` package.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` reached through the JVM's Foreign Function & Memory API (N
independent sessions per process). It is **not** an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. The jar
carries no protocol logic — the W3C command map, routing, `By` normalization,
error decode and the HTTP round trip all live in that one library. Needs a JDK
with the FFM API (Java 21+).

This jar is the **engine host for the whole JVM family** — Kotlin, Clojure,
Groovy and Scala all consume it (they add no engine of their own; see their
READMEs).

> **Name note.** The package is `org.openqa.selenium` — an ABI/name match to
> mainstream Selenium-Java (your code is identical to upstream). These jars are
> **not published to Maven Central**; your platform team builds and publishes them
> to your internal Maven repo (below).

## Using it (JVM app developer)

Depend on the jar from your internal Maven repo, then:

```java
import org.openqa.selenium.RemoteWebDriver;
import org.openqa.selenium.By;

var d = RemoteWebDriver.headlessChrome("http://127.0.0.1:9515");
d.get("https://example.com");
System.out.println(d.getTitle());
System.out.println(d.findElement(By.id("main")).getText());
d.quit();
```

The engine ships **inside** the platform jar (see the three jars below) and the
FFM binding loads it — nothing to install, compile, or configure. To point at a
specific engine, set `SELENIUM_CORE_LIB=/abs/path/libselenium_core.so`.

## The three jars (platform / DevOps)

`aeb java/.package.ae` builds three artifacts, differing only in how the engine
travels:

| Jar | Contents | Use |
|-----|----------|-----|
| `selenium-client.jar` | classes only (LEAN) | bring-your-own-native: supply the engine via `SELENIUM_CORE_LIB` |
| `selenium-client-<os>-<arch>.jar` | classes + the engine for ONE platform (in `/native/`) | a self-contained dev jar for your box |
| `selenium-client-standalone.jar` | classes + engines for ALL platforms (in `/native/<os>-<arch>/`) | one jar that runs anywhere |

At load, `Native.locate()` resolves the engine: `SELENIUM_CORE_LIB` →
`/native/<os>-<arch>/<lib>` (standalone) → `/native/<lib>` (single-platform). So
the standalone and platform jars are self-contained; the lean jar is BYO-native.

Build the jars from source (the platform/standalone jars cross-build the engine
for every target):

```sh
aeb java/.package.ae
```

Then publish the jars to your internal Maven repo (`mvn deploy:deploy-file`, or
your CI's publish step). See
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md).

> **No-toolchain fetch, jar caveat.** The other bindings can fetch a single
> prebuilt engine via `--overrideDep selenium_core/.build.ae=…getFromGitHubReleases.ae`.
> The multi-platform jars depend on `selenium_core/.crossbuild.ae` (all 6 platform
> engines), and a *fetch-all-6* crossbuild substitute node does **not exist yet**
> — so cutting the standalone/platform jars without the Aether toolchain is a
> tracked follow-up. Today they're built from source. (A lean `selenium-client.jar`
> needs no engine at all — it's BYO-native.)

## Layout

```
src/main/java/org/openqa/selenium/   the WebDriver / WebElement / By / … surface
  Native.java                        the Panama FFM binding + engine locate()
.package.ae                          aeb node → builds the three jars
.tests.ae                            aeb node → the binding test suite
.example.ae                          aeb node → consumes a built jar clean + drives Chrome
```
