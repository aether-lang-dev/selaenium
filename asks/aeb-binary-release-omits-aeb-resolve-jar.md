# aeb: the binary release omits aeb-resolve.jar, so every JVM node fails

Found 2026-09-12 after installing the pinned toolchain per the README.
Upstream gap in **aeb's release packaging**, not in this repo.

## Symptom

A fresh `AEB_REF=v0.307` binary install has no
`$AEB_HOME/tools/aeb-resolve.jar`. Every node that resolves Maven coordinates
then fails, and fails *confusingly*:

```
tests:java: resolving maven dependencies
tests:java: warning: no maven jars resolved
...
100 errors
only showing the first 100 errors, of 330 total
Error: Could not find or load main class org.junit.platform.console.ConsoleLauncher
tests:java: javac (test) failed
```

The 330 errors are all `cannot find symbol: assertEquals` and friends — javac
ran with NO JUnit on the classpath. The real cause is one line above, demoted to
a *warning*, and then the build carried on anyway. Reading the wall of errors,
the obvious (wrong) conclusion is that the test code is broken.

`scala/.tests.ae` fails earlier and more honestly:
`Error: Unable to access jarfile .../tools/aeb-resolve.jar`.

## Cause

`tools/aeb-resolve.jar` is built out-of-band by `tools/resolver/.dist.ae` from
`tools/resolver/BldResolve.java`, and is gitignored. The Makefile already carries
a comment about a prior bug where `make install` reclaimed the jar "with no way
to rebuild it — the jar is gitignored, so it's then gone for good and every
maven/java/scala/kotlin build breaks."

The binary release tarball has the same hole: the jar simply is not in it.

## Why this should be easy to close

**Anything that needs the resolver already has a JDK.** Every node that resolves
Maven coordinates declares `prereq("jdk:22")`, and `lib/maven` invokes the
resolver as `java -jar aeb-resolve.jar`. The resolver's own build node says it
plainly: *"Build needs only a JDK + curl."*

So the machine that needs it can always build it. Confirmed here — from a bare
checkout of aeb:

```
$ aeb tools/resolver/.dist.ae
  dist: tools/resolver    2.09s
$ cp target/dist/tools/resolver/bin/{aeb-resolve.jar,bld-2.3.0.jar} $AEB_HOME/tools/
```

Two seconds. After that, `aeb java/.tests.ae` goes from 330 phantom errors to
**52/52 PASS**.

## Suggested fix, in order of preference

1. **Build it on demand.** When `lib/maven` needs the resolver and the jar is
   absent, build it — the JDK it is about to use for the compile is the same JDK
   the resolver needs. No new dependency, no packaging change.
2. **Ship it in the release tarball.** It is 8 KB (plus the 2 MB bld jar it
   names on its Class-Path).
3. **Failing both, fail fast and clearly.** `warning: no maven jars resolved`
   should be a hard error naming the missing jar and how to build it, not a
   warning followed by a doomed compile that buries the cause under 330
   unrelated errors.

## Note for this repo

`ci/toolchain.sh` could paper over this by building the jar after installing
aeb, but that means selaenium carrying a workaround for aeb's packaging. Left
undone pending an upstream decision.
