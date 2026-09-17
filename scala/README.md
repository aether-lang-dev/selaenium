# selenium (Scala) — idiomatic Scala over the Java jar

Selenium WebDriver for Scala — a thin layer of Scala/Java interop over the Java
binding's `org.openqa.selenium` classes (Scala sugar in
`org.openqa.selenium.scala`).

Scala adds **no engine of its own**. The engine is one pure, reentrant shared
library — a single .so/.dylib/.dll … NOT an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. Scala
reaches it **through the host artifact — the Java FFM jar** (the one JVM binding
to the engine, Panama `java.lang.foreign`), so the whole engine story — the
three jars, how the `.so` travels, `SELENIUM_CORE_LIB` — lives in
[`java/README.md`](../java/README.md). One jar backs the entire JVM family
(Kotlin/Clojure/Groovy/Scala); a Scala-specific FFI would only be a second copy
of the marshalling rules to drift.

> **Name note.** The underlying classes are the mainstream `org.openqa.selenium`
> — an ABI/name match to upstream Selenium-Java. Nothing here is on a public
> registry; your platform team builds and publishes the jar to your internal
> Maven repo (see `java/README.md`).

## Using it (Scala app developer)

Put the Java jar on your classpath (from your internal Maven repo), then use the
`Selenium` object (Scala 3):

```scala
import org.openqa.selenium.scala.Selenium.*

headlessChrome("http://127.0.0.1:9515") { d =>
  d.get("https://example.com")
  println(d.getTitle())
  println(d.find(By.cssSelector("#main")).getText())
}   // the driver is quit for you at the end of the body
```

What Scala adds: a `headlessChrome(url) { d => … }` / `localChrome() { d => … }`
loan-pattern that always quits; a `By` factory re-export (all 8 strategies); a
`d.find(by)` extension on `WebDriver`; and the pure engine helpers (`route`,
`errorCode`, `locator`) as functions. Everything else is the Java surface over
interop.

## Layout

```
src/main/scala/org/openqa/selenium/scala/Selenium.scala   the Scala sugar (loan-pattern, By, find extension)
src/test/scala/org/openqa/selenium/scala/FfiTest.scala    FFI + live-BiDi test (interop over the Java jar)
.tests.ae                                                 aeb node → deps java/.build.ae + the engine, runs FfiTest
```

Scala adds no engine — see [`java/README.md`](../java/README.md) for the jars
and how the engine is bundled.
