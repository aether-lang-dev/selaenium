# selenium (Kotlin) — idiomatic Kotlin over the Java jar

Selenium WebDriver for Kotlin — a thin layer of Kotlin/Java interop over the
Java binding, in the mainstream `org.openqa.selenium` package (Kotlin sugar in
`org.openqa.selenium.kotlin`).

Kotlin adds **no engine of its own**. The engine is one pure, reentrant shared
library — a single .so/.dylib/.dll … NOT an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. Kotlin
reaches it **through the host artifact — the Java FFM jar** (the one JVM binding
to the engine, Panama `java.lang.foreign`), so the whole engine story — the
three jars, how the `.so` travels, `SELENIUM_CORE_LIB` — lives in
[`java/README.md`](../java/README.md). One jar backs the entire JVM family
(Kotlin/Clojure/Groovy/Scala); a Kotlin-specific FFI would only be a second copy
of the marshalling rules to drift.

> **Name note.** The classes are the mainstream `org.openqa.selenium` — an
> ABI/name match to upstream Selenium-Java. Nothing here is on a public registry;
> your platform team builds and publishes the jar to your internal Maven repo
> (see `java/README.md`).

## Using it (Kotlin app developer)

Depend on the Java jar from your internal Maven repo, then use the Kotlin sugar
(`org.openqa.selenium.kotlin.Selenium`), or the `org.openqa.selenium` classes
directly:

```kotlin
import org.openqa.selenium.kotlin.headlessChrome
import org.openqa.selenium.kotlin.By
import org.openqa.selenium.kotlin.find

headlessChrome("http://127.0.0.1:9515") { d ->
    d.get("https://example.com")
    println(d.getTitle())
    println(d.find(By.id("main")).getText())
}   // the driver is quit for you at the end of the block
```

What Kotlin adds: `chrome { }` / `headlessChrome { }` / `localChrome { }`
`use`-style builders that quit the session on exit; `d.find(by)` / `d.findAll(by)`
and `d.script(js, *args)` extensions; and a `By` object re-exporting the Java
`By` factory. Everything else is the Java surface reached over seamless interop.

## Layout

```
src/main/kotlin/org/openqa/selenium/kotlin/Selenium.kt   the Kotlin sugar (builders, By, extensions)
src/test/kotlin/org/openqa/selenium/kotlin/LiveTest.kt   FFI + live-surface test (interop over the Java jar)
.tests.ae                                                aeb node → deps java/.build.ae + the engine, runs the test
```

Kotlin adds no engine — see [`java/README.md`](../java/README.md) for the jars
and how the engine is bundled.
