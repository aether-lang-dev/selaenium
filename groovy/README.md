# selenium (Groovy) — idiomatic Groovy over the Java jar

Selenium WebDriver for Groovy — a thin layer of Groovy/Java interop over the
Java binding's `org.openqa.selenium` classes (Groovy sugar in
`org.openqa.selenium.groovy`).

Groovy adds **no engine of its own**. The engine is one pure, reentrant shared
library — a single .so/.dylib/.dll … NOT an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. Groovy
reaches it **through the host artifact — the Java FFM jar** (the one JVM binding
to the engine, Panama `java.lang.foreign`), so the whole engine story — the
three jars, how the `.so` travels, `SELENIUM_CORE_LIB` — lives in
[`java/README.md`](../java/README.md). One jar backs the entire JVM family
(Kotlin/Clojure/Groovy/Scala); a Groovy-specific FFI would only be a second copy
of the marshalling rules to drift.

> **Name note.** The classes are the mainstream `org.openqa.selenium` — an
> ABI/name match to upstream Selenium-Java. Nothing here is on a public registry;
> your platform team builds and publishes the jar to your internal Maven repo
> (see `java/README.md`).

## Using it (Groovy app developer)

Put the Java jar on your classpath (from your internal Maven repo). Groovy
already makes the Java surface terse, so most calls are just the Java methods;
the `Selenium` helper adds a closure form that quits on exit:

```groovy
import org.openqa.selenium.By
import org.openqa.selenium.groovy.Selenium

Selenium.withHeadlessChrome("http://127.0.0.1:9515") { d ->
    d.get("https://example.com")
    println d.getTitle()
    println d.findElement(By.id("main")).getText()
}   // the driver is quit for you at the end of the closure
```

What Groovy adds: `withChrome` / `withHeadlessChrome` / `withLocalChrome`
closure forms that quit the session on exit. Everything else is calling the Java
methods directly (Groovy maps/lists coerce to `java.util.Map`/`List` for params).

## Layout

```
src/main/groovy/org/openqa/selenium/groovy/Selenium.groovy   the withChrome/withHeadlessChrome/withLocalChrome closures
test/live_test.groovy                                        FFI + live-surface test (interop over the Java jar)
.tests.ae                                                    aeb node → deps java/.build.ae + the engine, runs the script
```

Groovy adds no engine — see [`java/README.md`](../java/README.md) for the jars
and how the engine is bundled.
