# release — cross-built engine artifacts + on-target attestation

The engine (`libselenium_core`) is pure Aether, so it **cross-compiles for the
whole platform matrix from one Linux host** — no per-OS runner for the build.
Pushing a release tag triggers GitHub Actions to build and publish nine engine
libraries, official binding package files, and checksums. v0.11.0 adds Linux musl
(x86_64/arm64) and FreeBSD x86_64 to the original six Linux/macOS/Windows
libraries; published v0.10.0 assets stay unchanged. On-target
*testing* is done out of band and recorded as an attestation keyed by SHA256.

## Build

```sh
release/build.sh                     # linux glibc/musl + macos, x86_64 + arm64
RELEASE_TAG=v1.2.3 release/build.sh   # stamp a tag into the artifact names
RELEASE_EXTRA_TARGETS=1 release/build.sh   # + windows (slow) + freebsd (needs AETHER_SYSROOT)
TARGETS="aarch64-macos" release/build.sh   # just one
```

Needs `ae` + `zig` on PATH (run `ci/toolchain.sh` first) and `sha256sum`.
Outputs into `release/dist/` (gitignored):

- `libselenium_core-<tag>-<os>-<arch>.{so,dylib,dll}` — the artifact
- `<artifact>.sha256` — its checksum (sidecar)
- `SHA256SUMS.txt` — all artifacts in one manifest

Each is stripped (`--size`). `so`=linux ELF, `dylib`=macOS Mach-O, `dll`=Windows.

**Windows:** both `x86_64-windows` and `aarch64-windows` cross-build to real
PE32+ DLLs (via `RELEASE_EXTRA_TARGETS=1`). Each DLL also gets a `<dll>.lib`
import library beside it — needed only by a consumer that *links* the DLL at
build time; our FFI bindings `dlopen` at runtime and don't use it, but it is
checksummed and shipped so Windows is first-class. So a full run with extras
produces 6 core + 2 Windows (× 2 files each) + 1 FreeBSD library. FreeBSD needs
`AETHER_SYSROOT` and skips loudly without it.

## Cut a GitHub release

Prepare the engine version, commit the changes, then push a tag at that commit:

```sh
python3 release/version.py --set v0.11.0
python3 release/version.py --check v0.11.0
# Stage the version changes shown by git diff, then:
git commit -m '[release] prepare engine v0.11.0'
git push origin main
git tag v0.11.0
git push origin v0.11.0
```

Choose a new unused version for each release. Pushing to `main` alone does not
release anything. The [release workflow](../.github/workflows/release.yml) also
supports a manual run with an existing tag. It checks out that exact tag,
verifies the version pins, installs the pinned Aether, aeb, and Zig toolchains,
and runs `release/build.sh` on one Ubuntu runner. All nine engine builds must succeed;
a failing platform prevents publication. The workflow loads the Linux x86_64
library and checks every declared C ABI export, then creates the GitHub release
and downloads the assets again to verify their checksums and ABI.

The workflow runs inside the pinned
`mcr.microsoft.com/devcontainers/universal:6.1.10-noble` image. This Ubuntu x86-64
image supplies the C toolchain and the Java, Ruby, Python, and Node SDKs used to
produce the native-bearing packages; the workflow installs .NET 8 explicitly
because the image's preinstalled SDK set may move forward. It builds three Java
jars, a Ruby gem, a Python wheel, an npm tarball, and a .NET NuGet package alongside source
archives for Crystal and Julia and the nine native engine libraries. Native-
bearing packages bundle the Linux x86_64 engine; Java's standalone jar contains
its six-platform matrix. Crystal and Julia archives contain source only and
fetch the consumer's OS/CPU engine at build/runtime. Every release file is checksummed and
download-verified. Registry publishing remains separate because it requires
registry credentials. The workflow does not run a browser or desktop CI test
matrix. Required ABI exports remain mandatory in bindings; there are no
compatibility fallbacks for an older engine. The workflow does not replace an
existing release; use a new tag for changed binaries.

### Manual alternative

The existing local build/upload script remains available for manual cuts
(including optional Java jars). Disable the automatic release workflow before
using this route, so the two publishers do not race on the same tag:

```sh
release/publish.sh v1.2.3            # build the matrix + create the release, assets attached
release/publish.sh v1.2.3 --draft    # create as a draft to review first
release/publish.sh v1.2.3 --no-build # attach whatever is already in release/dist
```

`publish.sh` builds (unless `--no-build`), then `gh release create <tag>` with
every artifact, its `.sha256`, and `SHA256SUMS.txt`. It uses your existing `gh` auth
— **nothing in GitHub Settings, no Actions, no secrets.** (Registry publishing —
PyPI/npm/Maven/… — is deliberately out of scope here; that would need per-registry
secrets.)

### Advance the engine downloads with every release

The Selaenium engine release tag versions the `.so`, `.dylib`, and `.dll`.
It is separate from the Aether and aeb toolchain versions in `ci/versions.env`.

`release/version.py --set <tag>` updates `SELENIUM_CORE_VERSION`, the Aether
package version, all binding copies of the engine pin, and their version
assertions together. Commit those changes **before tagging**, so the tagged
bindings download the engine from their own release. The workflow rejects any
drift between the tag and these pins. Do not distribute packages from that
preparation commit until the engine assets are published successfully.

After publication:

1. Verify that the actual engine binaries and their checksums are downloadable;
   a tag or release page alone does not prove the engine is available. The
   workflow does this automatically for all nine libraries, and loads the
   downloaded Linux library to check every C ABI export.
2. Check `python3 release/version.py --check <tag>` on the current branch too:
   all download pins must name **the engine just released**. Update the README's
   engine requirement and link to the published release.
   Keep historical release records intact.
3. Run binding tests and consumer-install proofs using the fetched engine.
   For Dart, for example:

   ```sh
   aeb dart/.tests.ae dart/.example.ae \
       --overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae
   ```

Confirm that the loaded/bundled library matches the release artifact's checksum;
an existing local build must not satisfy this check. Keep required FFI symbols
mandatory: missing exports mean the binding and engine versions are incompatible.
Do not finish a release with the download pins still pointing at the previous
engine.

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

- **Additional binding packages**: the release currently includes Java, Ruby,
  Python, JavaScript, .NET, Crystal, and Julia artifacts. Other `.package.ae`
  nodes can be added as their distributable format and release naming are settled.
- **Registry publish** (PyPI/Maven/npm/…): a separate credentialed step; not
  part of the cross-build story.
