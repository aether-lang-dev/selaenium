# selenium (Clojure) — idiomatic Clojure over the Java jar

Selenium WebDriver for Clojure — an idiomatic `selenium` namespace of
Clojure/Java interop over the Java binding's `org.openqa.selenium` classes.

Clojure adds **no engine of its own**. The engine is one pure, reentrant shared
library — a single .so/.dylib/.dll … NOT an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. Clojure
reaches it **through the host artifact — the Java FFM jar** (the one JVM binding
to the engine, Panama `java.lang.foreign`), so the whole engine story — the
three jars, how the `.so` travels, `SELENIUM_CORE_LIB` — lives in
[`java/README.md`](../java/README.md). One jar backs the entire JVM family
(Kotlin/Clojure/Groovy/Scala); a Clojure-specific FFI would only be a second
copy of the marshalling rules to drift.

> **Name note.** The underlying classes are the mainstream `org.openqa.selenium`
> — an ABI/name match to upstream Selenium-Java. Nothing here is on a public
> registry; your platform team builds and publishes the jar to your internal
> Maven repo (see `java/README.md`).

## Using it (Clojure app developer)

Put the Java jar on your classpath (from your internal Maven repo), then
`require` the `selenium` namespace:

```clojure
(require '[selenium :as sel])

(sel/with-chrome [d "http://127.0.0.1:9515"]      ; headless; quits on exit
  (sel/navigate d "https://example.com")
  (println (sel/get-title d))
  (println (sel/text (sel/find-element d :id "main"))))
```

What Clojure adds: keyword-friendly locators (the `by` map: `:id`, `:css`,
`:class-name`, `:xpath`, …), a `with-chrome` macro that quits on exit, and
value-returning functions (`navigate`, `get-title`, `find-element`, `text`,
`click`, `execute-script`, cookies, windows, actions, …) over the Java methods.
Params are Clojure maps (converted to `java.util.Map`); results come back as the
Java binding decodes them.

## Layout

```
src/selenium.clj        the idiomatic selenium namespace (by map, with-chrome, fns)
test/live_test.clj      FFI + live-surface test (interop over the Java jar)
.tests.ae               aeb node → deps java/.build.ae + the engine, runs live-test's -main
```

Clojure adds no engine — see [`java/README.md`](../java/README.md) for the jars
and how the engine is bundled.
