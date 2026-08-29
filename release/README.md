# release — cross-built engine artifacts + on-target attestation

The engine (`libselenium_core`) is pure Aether, so it **cross-compiles for the
whole platform matrix from one Linux host** — no per-OS runner for the build.
This directory builds those artifacts and checksums them; on-target *testing* is
done out of band and recorded as an attestation keyed by SHA256.

## Build

```sh
release/build.sh                     # core matrix: linux + macos, amd64 + arm64
RELEASE_TAG=v1.2.3 release/build.sh   # stamp a tag into the artifact names
RELEASE_EXTRA_TARGETS=1 release/build.sh   # + windows (slow) + freebsd (needs AETHER_SYSROOT)
TARGETS="aarch64-macos" release/build.sh   # just one
```

Needs `ae` + `zig` on PATH (run `ci/toolchain.sh` first) and `sha256sum`.
Outputs into `release/dist/` (gitignored):

- `libselenium_core-<tag>-<os>-<arch>.{so,dylib,dll}` — the artifact
- `<artifact>.sha256` — its checksum (sidecar)
- `SHA256SUMS` — all artifacts in one manifest

Each is stripped (`--size`). `so`=linux ELF, `dylib`=macOS Mach-O, `dll`=Windows.

**Windows:** both `x86_64-windows` and `aarch64-windows` cross-build to real
PE32+ DLLs (via `RELEASE_EXTRA_TARGETS=1`). Each DLL also gets a `<dll>.lib`
import library beside it — needed only by a consumer that *links* the DLL at
build time; our FFI bindings `dlopen` at runtime and don't use it, but it is
checksummed and shipped so Windows is first-class. So a full run with extras
produces 4 core + 2 Windows (× 2 files each) artifacts. FreeBSD still needs
`AETHER_SYSROOT` and skips loudly without it.

## Cut a GitHub release (manual, no repo settings needed)

```sh
release/publish.sh v1.2.3            # build the matrix + create the release, assets attached
release/publish.sh v1.2.3 --draft    # create as a draft to review first
release/publish.sh v1.2.3 --no-build # attach whatever is already in release/dist
```

`publish.sh` builds (unless `--no-build`), then `gh release create <tag>` with
every artifact, its `.sha256`, and `SHA256SUMS`. It uses your existing `gh` auth
— **nothing in GitHub Settings, no Actions, no secrets.** (Registry publishing —
PyPI/npm/Maven/… — is deliberately out of scope here; that would need per-registry
secrets.)

## Why build-here / test-elsewhere

The **build** is deterministic and platform-agnostic (zig cross-compiles the
exact bytes every time), so building on Linux and running on the target are
testing *identical bytes* — there is no "works on my machine" gap. What a Linux
host cannot do is *run* an arm64-macOS binary. So:

1. **CI (this script, one Linux host):** cross-build the matrix, publish each
   artifact **with its `.sha256`**. The release proceeds without an on-target
   test gate — a slow/unavailable macOS runner never blocks a release.
2. **Attestation (out of band, real hardware — e.g. a homelab):** fetch a
   specific artifact by hash, run the binding suite against it on its target OS,
   and record that **that hash** passed. Because SHA256 identifies the exact
   bytes, the attestation is a durable, verifiable claim about what users
   download.

## What "passed" covers per artifact (be explicit)

TLS splits the coverage (see `../docs/Architecture.md` "Cross-compiled release"):

- **Local driver over `http://`** — works on every cross-built artifact. The
  normal case; a full FFI + live-local-Chrome suite exercises it with no TLS.
- **BiDi over `ws://` / `wss://`** — the WebSocket client covers it (TLS
  included), so BiDi attestation needs nothing special.
- **Remote Grid over `https://`** — needs the pure-Aether TLS Tier-2 helper (not
  wired into `std.http.client` yet). Until that lands, cross-built artifacts do
  **not** cover HTTPS-Grid; say so in the attestation rather than implying full
  coverage.

## Attestation record (suggested format)

One line per (artifact, target, run) in a checked-in `release/ATTESTATIONS.md`,
or a signed file — whatever your trust model wants. The load-bearing fields:

```
sha256=<hex>  artifact=libselenium_core-v1.2.3-macos-arm64.dylib
target=macos-arm64  host=<box>  date=2026-08-29
coverage=ffi+live-local-chrome        # or: +bidi, +https-grid
result=PASS                            # PASS | FAIL
suite=<what ran>  notes=<e.g. "chromedriver 152, no HTTPS Grid tested">
```

A verifier re-hashes the artifact they hold, matches `sha256`, and trusts the
`result` for that `coverage` on that `target`.

## Not here yet

- **Binding packages** (wheel/gem/jar/nupkg/…): the `.package.ae` nodes build
  these with the `.so` bundled; a follow-up can stage them as release assets
  too. This script ships the engine artifact — the one thing that's hard for a
  user to produce — first.
- **Registry publish** (PyPI/Maven/npm/…): a separate credentialed step; not
  part of the cross-build story.
