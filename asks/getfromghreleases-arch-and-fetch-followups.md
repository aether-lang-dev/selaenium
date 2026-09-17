# .getFromGitHubReleases.ae — two queued simplifications (pending an ae pin bump)

`selenium_core/.getFromGitHubReleases.ae` (the pure-stdlib engine-fetch node)
carries one temporary shim and one open opportunity. Both are **blocked on
bumping the pinned ae** (`ci/versions.env` AETHER_REF, currently `v0.680.0`) and
should land together with that bump — verified against the actual pinned
binary, not on a peer's report of the release.

## 1. Drop the `uname -m` shim → `os.arch()`  ✅ DONE (2026-09-17, commit 0ca3737)

`os.arch()` shipped in aether 0.681.0 (#2051), returning the normalized
ecosystem vocab (`x86_64` never `amd64`, `arm64` never `aarch64`) — exactly the
release-asset tokens — so `_arch()` collapsed to `return os.arch()` with NO
normalizer. AETHER_REF bumped 0.680.0 → 0.681.0 (aeb v0.314's AETHER_PIN 0.680.0
is a FLOOR, so no coupled AEB move). The node is now fully shell-free.

Verified on the RELEASED 0.681.0 binary (ae + aetherc both 0.681.0):
`os.platform()+"-"+os.arch()` = `linux-x86_64` live; engine .so rebuilds clean
and byte-identical (sha aea3cbbb…), 66 `aether_sel_embed_*` exports intact; the
`--overrideDep` ruby-gem seal fetched the real v0.8.0 engine end-to-end with the
cache CLEARED (928928 bytes, sha 4516753c…) and sealed it.

## 2. Optional: `_download_bytes` + sha check → aeb's `fetch._fetch_verified`

Per the aeb session, aeb added a download+verify+cache convenience
`fetch._fetch_verified` (aeb commit 910902d). This is an **aeb-side** primitive,
NOT stdlib — std deliberately keeps `http.client` and
`cryptography.sha256_file` as separate primitives, so there is no stdlib fetch
helper coming to wait for. Adopting `fetch._fetch_verified` could replace the
hand-rolled `_download_bytes` + sha256 verify + cache-stage logic here. Treat as
a separate, optional cleanup — evaluate it on its own once the aeb pin (AEB_REF)
that ships it is the pinned one; do not conflate with the `os.arch()` swap.

## When bumping the ae pin (whichever release lands) — the discipline that held for 0.681
- Confirm the new stdlib you depend on against the real binary (item 1 did this
  for os.arch()). NOTE the toolchain-install trap hit on 0.681: `ci/toolchain.sh`
  "skip if ae present" does NOT compare to AETHER_REF (left 0.680 in place); and
  a plain install left `ae` at 0.681 but `aetherc` (the codegen) at 0.680 — a
  Frankenstein toolchain. The fix is `ae version install <v> && ae version use
  <v>` so BOTH come from one build; `ae version doctor`'s compile probe confirms.
- Rebuild the engine `.so` and `nm`-verify the `aether_sel_embed_*` symbols —
  NOT just build success. A big version jump has a codegen-bug history
  (0.677 sha1.free_ctx whole-program bug produced a broken .so masked by stale
  copies); a green build is not proof.
- Re-run the fetch node end-to-end: fetch the real engine, then seal it into a
  package via `--overrideDep`.
- Check whether AEB_REF is coupled (its AETHER_PIN must match AETHER_REF — the
  ci/versions.env notes flag these as coupled pins).
