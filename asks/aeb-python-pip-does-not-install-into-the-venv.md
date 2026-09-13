# aeb: `python.pip("pytest")` does not install into the venv it then runs

Found 2026-09-13 on aeb v0.309 / ae 0.666.0. Upstream bug in **aeb's python
SDK**, not in this repo.

## Symptom

`python/.tests.ae` declares:

```aether
python.pip("pytest")
python.install()
python.pytest() { ... }
```

The node fails, and `target/.aeb/logs/tests_python.log` says only:

```
tests:python: installing deps (pip)
tests:python: running tests (pytest)
tests:python: tests FAILED
tests:python: FAILED — tests FAILED
```

The real message is in `target/tests/python/test_output.log`, one line:

```
/home/paul/scm/selenium/.aeb/venv/bin/python: No module named pytest
```

So the "installing deps (pip)" step reported nothing wrong and installed
nothing.

## It is not the box

aeb's own venv is fine, and pip works in it:

```
$ .aeb/venv/bin/python -m pip install -q pytest    # exit 0, instant
$ .aeb/venv/bin/python -c "import pytest; print(pytest.__version__)"
9.1.1
```

With pytest present in that same venv, the node goes straight to **65/65 PASS**
with no other change. The suite itself was never in doubt — the same 65 tests
pass in a hand-rolled venv too.

Worth noting this box is PEP-668 managed (Arch), so a system-wide
`python3 -m pip install` correctly refuses with `externally-managed-environment`.
That is the right behaviour and not the cause: aeb creates and uses its own venv
(`.aeb/venv`, python 3.14 here), where installing is allowed and works.

## Impact

Every `python.pip(...)` dependency is silently absent at test time. Before aeb
v0.308 this compounded with the `| tee` exit-code bug and the node reported
PASS; now it at least reddens, so the damage is a confusing failure rather than
a false green.

## Suggested fix

1. Actually install into the venv that `python.pytest()` will run — the same
   interpreter, not the ambient one.
2. Fail the step if the install fails, and log pip's own stderr. "installing
   deps (pip)" followed by nothing is indistinguishable from success.
3. Consider verifying importability of each declared dep before running the
   suite, so the error names the missing dep rather than surfacing as an
   arbitrary test failure.
