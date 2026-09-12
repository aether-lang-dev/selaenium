# aeb: a node whose toolchain is missing reports "tests PASSED"

Found 2026-09-12 running the full presubmit on a dev box. Upstream bug in
**aeb**, not in this repo. This is the one that matters most of the three asks
here, because it makes a green presubmit mean less than it looks like it means.

## Symptom

`d/.tests.ae` declares `prereq("dmd")`. `dmd` is not installed. Expected: the
node is skipped. Actual — `target/.aeb/logs/tests_d.log` in full:

```
sh: line 1: dmd: command not found
sh: line 1: dmd: command not found
tests:d: dmd -run tests/ffi_test.d
tests:d: dmd -run tests/live_test.d
tests:d: tests PASSED (2 file(s))
```

and the run summary line:

```
tests:   d    0.01s [n/a] 2/2 PASS
```

Two separate failures in one:

1. **`prereq("dmd")` did not gate the node.** The commands ran anyway.
2. **The `d.test()` builder ignored their exit status.** Both invocations failed
   with `command not found` and the node still reported `tests PASSED
   (2 file(s))` — it counted the files it intended to run, not results.

There is no SKIPPED marker anywhere, so nothing downstream can tell this apart
from a real pass. `ci/run.sh` greps per-node logs for `FAILED`; this log has no
such line, so it passes that check too.

## A second shape of the same thing

`swift/.tests.ae` (`prereq("swift")`). `swift` IS on PATH but cannot execute —
`swift: error while loading shared libraries: libncurses.so.6`. The node
contradicts itself in four lines:

```
tests:swift: build FAILED
tests:swift: FAILED — build FAILED
tests:swift: running tests (swift test)
tests:swift: tests PASSED
```

It prints FAILED, carries on to the test phase anyway, and ends on PASSED. Here
`ci/run.sh`'s `: FAILED` grep does catch it — but only by luck, because this
builder happens to print the word.

Note this case also shows `prereq` cannot be a PATH-presence check: a tool can be
present and unrunnable.

## Impact

"presubmit green" does not mean "28 bindings tested". On this box two bindings
were not tested at all and nothing said so.

## Worked around in this repo, not fixed

`ci/coverage.sh` re-derives the answer independently: it reads each node's
declared `prereq(...)` and probes that toolchain **by running it**, then prints a
tested / NOT-TESTED table. `ci/run.sh` now prints that in its summary and grows a
`--strict` flag that fails the run when any binding could not be tested, so CI
can demand full coverage while a dev box stays usable. That is a check on top of
aeb, not a fix for it — the node still lies.

## Suggested fix, in order

1. A builder must propagate the exit status of the command it ran. `command not
   found` must never reach a `PASSED` line.
2. `prereq(...)` must actually gate, and must emit a SKIPPED marker when it does,
   so a skip is machine-visible and distinguishable from a pass.
3. A node should not continue to a later phase after printing FAILED for an
   earlier one (the swift case).
