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
TARGET=php/.tests.ae ci/run.sh --no-toolchain   # one node
```

`ci/run.sh` builds the engine, runs the target set, and prints an honest summary:
how many nodes **executed green** vs **skipped** (their toolchain/driver absent
on this box) vs **failed**. It exits non-zero only on a real failure — a skip is
green.

## Pieces

| File | Role |
|------|------|
| `versions.env`  | the pinned `AETHER_REF` (ae) + `AEB_REF` (aeb) — the one place to bump |
| `toolchain.sh`  | idempotently install ae + aeb at the pins (public curl-pipe installers; needs only curl/tar/make/cc) |
| `run.sh`        | the entry point: toolchain → engine → target set → summary |

## The target sets (aeb `.build.ae` / `.tests.ae` edges)

- **`.presubmit.ae`** (repo root) — the full gate: engine build + engine probe +
  all 18 binding `.tests.ae` + the 11 consumer-install `.example.ae` proofs. This
  is what must be green before pushing.
- **`selenium_core/tests/.tests.ae`** — the pure-Aether engine probe alone (no
  FFI, no browser). The `--offline` lane; runs anywhere with just ae/aeb.

## Skips are expected, and are green

aeb selects toolchains from `PATH` (see `docs/Architecture.md`). A binding whose
compiler/runtime is missing or too old **skips loudly and returns 0** — the
binding is correct, the box is under-provisioned. `run.sh` lists every skip so a
green run is never mistaken for "everything ran". The reference box with the full
toolchain set (newer Ruby/Kotlin/Groovy/PHP-FFI + GHC via ghcup) is **catchyos**
(`192.168.0.160`); the live-browser leg of each binding additionally needs a
`chromedriver` on `PATH`, which most boxes lack, so it self-skips too.

## Reproducibility note

The pins in `versions.env` make a run reproducible; bump them deliberately and
re-verify the full presubmit on catchyos. aeb tags are "later means later"
markers, not semver — pin, don't float.
