# .getFromGitHubReleases.ae — two queued simplifications (pending an ae pin bump)

`selenium_core/.getFromGitHubReleases.ae` (the pure-stdlib engine-fetch node)
carries one temporary shim and one open opportunity. Both are **blocked on
bumping the pinned ae** (`ci/versions.env` AETHER_REF, currently `v0.680.0`) and
should land together with that bump — verified against the actual pinned
binary, not on a peer's report of the release.

## 1. Drop the `uname -m` shim → `os.arch()`

`_arch()` currently shells a single `os.exec("uname -m")` and normalizes the
result to the release-asset vocabulary (`x86_64` / `arm64`), because stdlib had
no CPU-arch accessor.

`os.arch()` is reported to have shipped (aether #2051). If the pinned ae exposes
it, `_arch()`'s body collapses to `return os.arch()` **with no normalizer** —
os.arch() is reported to already return the normalized ecosystem vocab
(`x86_64` never `amd64`, `arm64` never `aarch64`; also i386/arm/riscv64/ppc64le/
s390x/wasm32/wasm64/unknown) and to report the **target** arch under
cross-compile (uname -m reports the build host — matters for cross-fetch).

**Verify before swapping**: confirm `os.arch()` exists in the pinned binary AND
that its return tokens are exactly what the release-asset names use (spot-check
x86_64 + arm64). If the vocab ever diverges, keep a thin normalizer rather than
a bare `return os.arch()` — the current in-file comment optimistically says
"bare return", but correctness depends on the token match.

## 2. Optional: `_download_bytes` + sha check → aeb's `fetch._fetch_verified`

Per the aeb session, aeb added a download+verify+cache convenience
`fetch._fetch_verified` (aeb commit 910902d). This is an **aeb-side** primitive,
NOT stdlib — std deliberately keeps `http.client` and
`cryptography.sha256_file` as separate primitives, so there is no stdlib fetch
helper coming to wait for. Adopting `fetch._fetch_verified` could replace the
hand-rolled `_download_bytes` + sha256 verify + cache-stage logic here. Treat as
a separate, optional cleanup — evaluate it on its own once the aeb pin (AEB_REF)
that ships it is the pinned one; do not conflate with the `os.arch()` swap.

## When bumping the ae pin (whichever release lands)
- Confirm os.arch() against the real binary (item 1).
- Rebuild the engine `.so` and `nm`-verify the `aether_sel_embed_*` symbols —
  NOT just build success. A big version jump has a codegen-bug history
  (0.677 sha1.free_ctx whole-program bug produced a broken .so masked by stale
  copies); a green build is not proof.
- Re-run the fetch node end-to-end: fetch the real engine, then seal it into a
  package via `--overrideDep`.
- Check whether AEB_REF is coupled (its AETHER_PIN must match AETHER_REF — the
  ci/versions.env notes flag these as coupled pins).
