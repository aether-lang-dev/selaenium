# REOPENED: `scala.scalac_test`'s `env()` still lands in the compiler-classpath slot (v0.310)

> **STATUS: FIXED — shipped in aeb v0.311** (`9a1c520`, "cache an OWNED copy").
> Re-verified 2026-09-15: `aeb scala/.tests.ae` is **1/1 PASS**, and the whole
> JVM family (java, scala, kotlin, clojure, groovy) is green.

> **Upstream copy**: `~/scm/aeb/asks/scalac-test-env-prefix-lands-in-the-compiler-classpath.md`
> (pushed as `e385ee9`). Kept here so the symptom is searchable from this repo.
>
> **STILL OPEN on aeb v0.310** — this is what blocks `aeb scala/.tests.ae`.
> Removing the node's `env()` is NOT a fix: a JVM-family binding needs
> `SELENIUM_CORE_LIB` to locate the engine `.so` at run time.

**Filed by**: selaenium Claude, 2026-09-14, against the **released v0.310**
(`aeb v0.310`, `ae 0.668.0`, node `~/scm/selenium/scala/.tests.ae`).

This is the half of `asks/scalac-test-compiler-classpath-empty.md` that
`0959a64` assessed as *"the ask's env-in-the-cp-slot symptom does not exist in
current main"*. It does. That ask was then deleted as wholly satisfied in
`909bc88`, so re-filing with evidence from the released build rather than
editing a deleted file.

The other half of the original ask — the empty-classpath guard — **is** fixed
and is not what this is about.

## Symptom (unchanged)

```console
$ aeb scala/.tests.ae
Error: Could not find or load main class dotty.tools.dotc.Main
Caused by: java.lang.ClassNotFoundException: dotty.tools.dotc.Main
tests:scala: compiling test code (scalac)
tests:scala: scalac (test) failed
```

The new empty-classpath guard does not fire, because the slot is not empty — it
holds the env assignment.

## Evidence

`AEB_SH_TRACE=1`, the test-compile invocation, verbatim and untruncated at the
front:

```
'/usr/lib/jvm/java-26-openjdk/bin/java' -cp 'SELENIUM_CORE_LIB='/home/paul/scm/selenium/target/build/selenium_core/lib/libselenium_core.so'' dotty.tools.dotc.Main -d '/home/paul/scm/selenium/target/tests/scala/test-classes' -cp '/home/paul/scm/selenium/target/tests/scala/test-classes:…'  @'…/scalac_test_sources.txt'
```

Two `-cp` occurrences, and the FIRST one is the problem:

| position | should be | actually is |
|---|---|---|
| `java -cp …` (before the main class) | the Scala **compiler** classpath (scala3-compiler, tasty-core, …) | `SELENIUM_CORE_LIB=/…/libselenium_core.so` |
| `dotc … -cp …` (after the main class) | the compiled code's classpath | correct |

So the JVM is asked to find `dotty.tools.dotc.Main` on a classpath consisting of
an environment assignment, and cannot. Note also the quoting: the prefix is
emitted as `KEY='value'` and then wrapped in another layer of single quotes
(`-cp 'SELENIUM_CORE_LIB='/…/x.so''`), which is a second symptom of it being
concatenated into an argument rather than exported.

The **main** `scala.scalac()` compile in the same run gets a correct compiler
classpath, so this is specific to `scalac_test`.

## Node that triggers it

```aether
scala.scalac() {
}
scala.scalac_test() {
    env("SELENIUM_CORE_LIB", lib)     // needed at RUN time: JVM-family binding loads the .so
    main_class("org.openqa.selenium.scala.FfiTest")
    skip_below_jdk("22")
    jvm_flag("--enable-native-access=ALL-UNNAMED")
}
```

Remove the `env(...)` and the symptom changes (previously to an empty `-cp`), so
`env()` is the trigger. Keeping it is correct: a JVM-family binding needs
`SELENIUM_CORE_LIB` to locate the engine `.so` at run time.

## Suggested fix

`lib/scala/module.ae:546` applies `bldr._env_export_prefix(_builder)` to the RUN
command, which is right. Something on the `scalac_test` COMPILE path is also
picking it up — either the same prefix is prepended to the compile command, or
the variable holding the compiler classpath is being assigned from it. Worth
checking that `_compiler_classpath(ctx)` is what reaches the compile invocation
in `scalac_test`, the way it does in `scalac`.

Cheap regression guard: assert the token immediately after `java -cp` looks like
a path or classpath, not `KEY=`.
