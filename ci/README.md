# CI — aeb is the CI

This repo has **no GitHub Actions** (they were the inherited classic Selenium
Bazel/RBE + SeleniumHQ-org workflows; all removed). CI here is **in-repo scripts
that drive `aeb`** — the same green-gate you run locally is the one a runner runs.
Nothing about the check is hidden in a `.yml` you can't execute yourself.

## Run it

```sh
ci/run.sh                # install pinned toolchain, then the full presubmit
ci/run.sh --offline      # engine probe only — fast, no per-binding toolchain
ci/run.sh --no-toolchain # ae/aeb already on PATH; skip the install step
ci/run.sh --strict       # ALSO fail if this box could not test every binding
ci/coverage.sh           # just the table: what could this box actually test?
TARGET=php/.tests.ae ci/run.sh --no-toolchain   # one node
```

`ci/run.sh` builds the engine, runs the target set, and prints a summary: nodes
that **failed**, plus a **coverage** section saying which bindings this box could
actually test. It exits non-zero on a real failure, and — with `--strict` — also
when coverage is incomplete. **CI should use `--strict`.**

## Pieces

| File | Role |
|------|------|
| `versions.env`  | the pinned `AETHER_REF` (ae) + `AEB_REF` (aeb) — the one place to bump |
| `toolchain.sh`  | idempotently install ae + aeb at the pins — a prebuilt aeb release `.tar.gz`, **SHA256-verified**, when one exists for this platform+tag (fast, no compile), else the public curl-pipe source build; needs only curl/tar/make/cc. `NO_BINARY=1` forces source. |
| `run.sh`        | the entry point: toolchain → engine → target set → summary |
| `coverage.sh`   | reads each node's `prereq(...)` and probes that toolchain **by running it**, then prints a tested / NOT-TESTED table. `--strict` exits non-zero when anything could not be tested. This is a check *on top of* aeb — see below for why it has to exist. |

## The target sets (aeb `.build.ae` / `.tests.ae` edges)

- **`.presubmit.ae`** (repo root) — the full gate: engine build + engine probe +
  every binding's `.tests.ae` (28 languages) + the grid hub. This
  is what must be green before pushing.
- **`selenium_core/tests/.tests.ae`** — the pure-Aether engine probe alone (no
  FFI, no browser). The `--offline` lane; runs anywhere with just ae/aeb.

## Skips, and why "green" needs a second check

The intent: aeb selects toolchains from `PATH` (see `docs/Architecture.md`), and
a binding whose compiler/runtime is missing skips and returns 0 — the binding is
correct, the box is under-provisioned.

**The intent is not what happens.** A node whose toolchain is absent can report
`tests PASSED` with no skip marker at all, so nothing downstream can tell it from
a real pass. Observed on a dev box with no `dmd`:

```
tests_d.log:  sh: line 1: dmd: command not found
              tests:d: tests PASSED (2 file(s))
```

`run.sh` greps per-node logs for `FAILED`; that log has no such line. So the
older claim here — that listing skips means "a green run is never mistaken for
everything ran" — was wrong, because the skip was never announced.

`ci/coverage.sh` therefore re-derives the answer independently of what aeb said:
it reads each node's declared `prereq(...)` and **runs** that toolchain to see if
it works. Running it matters — `swift` can be on `PATH` and still fail with
`error while loading shared libraries: libncurses.so.6`, which a `command -v`
check would call present.

The underlying aeb bug is written up in
[`asks/aeb-missing-toolchain-reports-tests-passed.md`](../asks/aeb-missing-toolchain-reports-tests-passed.md);
`coverage.sh` is a guard, not a fix.

The reference box with the full toolchain set (newer Ruby/Kotlin/Groovy/PHP-FFI +
GHC via ghcup) is **catchyos** (`192.168.0.160`); the live-browser leg of each
binding additionally needs a `chromedriver` on `PATH`, which most boxes lack, so
it self-skips too — that kind of skip IS announced, and `run.sh` lists it.

## Reproducibility note

The pins in `versions.env` make a run reproducible; bump them deliberately and
re-verify the full presubmit on catchyos. aeb tags are "later means later"
markers, not semver — pin, don't float.
