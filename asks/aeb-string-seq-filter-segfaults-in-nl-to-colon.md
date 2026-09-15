# aeb: SIGSEGV in string.seq_filter via bldr._nl_to_colon when building the Java node

Reproducible crash in aeb's own build binary. Not a selaenium source problem:
it reproduces on a clean checkout (commit 77dc4b2, before any of the live-run
work) in a fresh `git worktree`.

## Observed

    $ aeb java/.tests.ae
      tests:   java     10.12s [miss] 52/52 PASS
      build:   java      0.09s [miss] FAILED
    make: *** [target/.aeb/bldr.mk:4: java_.build.ae] Error 139

Error 139 is SIGSEGV. `target/.aeb/logs/java.log` is **empty** — the crash
happens before any output, so the failure arrives with no diagnostic at all.

The 52 Java tests themselves pass; it is the `build: java` target in the same
graph that dies.

## Trigger

Graph-dependent, which is what makes it confusing:

    aeb java/.build.ae     # OK  (build: java  2.99s)
    aeb java/.tests.ae     # SIGSEGV in the java build target

Both drive the same `java/.build.ae` node. Building it alone is fine; building
it as the dependency of `java/.tests.ae` segfaults. Wiping `target/build/java`
and `target/.aeb` makes the standalone build succeed again but does not help
the `.tests.ae` path.

## Stack

    #0  string_seq_filter        (_ae_build_all + 0x47058)
    #1  bldr__nl_to_colon        (_ae_build_all + 0x1326b)
    #2  java__D_build_D_ae       (_ae_build_all + 0x21052)
    #3  main

`_nl_to_colon` (lib/bldr/module.ae:1854) is the newline -> colon classpath
conversion:

    _nl_to_colon(s: string) -> string {
        if string.length(s) == 0 { return "" }
        parts = string.lines(s)
        kept = string.seq_filter(parts, _drop_empty)
        ...

The guard covers `s == ""` but not what `string.lines` returns for it, and the
crash is inside `string.seq_filter` on the sequence that comes back. The likely
shape is `string.lines` handing back a null/!-terminated sequence for some input
that only occurs when the classpath is assembled with the test node in the
graph (an absent `jvm_classpath_deps_including_transitive` artifact would give
exactly that), and `seq_filter` walking it unguarded.

## Suggested fix

- Null/empty-guard the sequence in `string.seq_filter` rather than trusting the
  caller — it is a stdlib primitive taking a caller-supplied pointer.
- In `_nl_to_colon`, check the `string.lines` result before filtering.
- Separately: a segfaulting build step currently produces an EMPTY log, so the
  user sees "FAILED" with nothing to go on. A crashed step should report the
  signal (`Error 139` -> "killed by SIGSEGV") in the node summary.

## Impact here

`aeb java/.tests.ae` cannot go green even though the Java tests pass, so the
Java node is red for a reason that has nothing to do with the binding. Every
other binding node in the repo is unaffected.

## Status

Filed from selaenium; NOT mirrored into ~/scm/aeb/asks this time, because the
task that found it was explicitly scoped "don't touch the aeb repo". Worth
copying upstream.
