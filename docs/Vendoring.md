# Vendoring Selaenium source and native libraries

[`scripts/vendor.py`](../scripts/vendor.py) creates a reviewable snapshot from a
Selaenium release tag without cloning the Selaenium repository. It copies any
number of explicitly selected source paths into consumer-chosen destinations,
and can copy selected release `.so`, `.dylib`, and `.dll` files to a separate
destination. It does not generate a build file such as `pom.xml`.

The script itself is part of Selaenium and can be fetched without cloning the
repo. Its revision is independent of the release tag whose files are being
vendored. For example, from the consuming repository:

```sh
TAG=v0.11.0
SCRIPT_REF=main # Prefer a reviewed, pinned commit once the helper is adopted.
mkdir -p tools
gh api -H 'Accept: application/vnd.github.raw' \
  "repos/aether-lang-dev/selaenium/contents/scripts/vendor.py?ref=$SCRIPT_REF" \
  > tools/selaenium-vendor.py
```

Review and commit that helper in the consuming repository. It uses the `gh`
CLI to resolve the tag, read the tagged source archive, and download release
assets. `gh` must be installed and authenticated. Native assets must already be
published for the tag, so wait for the tag-triggered release workflow to finish.

For example, vendor the Java main sources, the Apache license, and Linux
x86_64-glibc plus macOS arm64 libraries:

```sh
python3 tools/selaenium-vendor.py sync --tag "$TAG" \
  --source-set java/src/main/java=java \
  --source-set LICENSE=license \
  --native-libs native \
  --platform linux-x86_64 \
  --platform macos-arm64 \
  --manifest third_party/selaenium/manifest.json
```

Each `--source-set` takes a path in the Selaenium repository and a destination
directory relative to the manifest's parent. A file is copied under that
directory by its filename; a directory's contents are copied beneath it.
Repeat the option for additional, non-overlapping trees or files. This can
include the source sets for other bindings when desired.
The native destination stores each library under a platform directory, such as
`native/linux-x86_64/libselenium_core.so` or
`native/windows-arm64/selenium_core.dll`. Linux musl libraries use distinct
`linux-*-musl` directories. Pass the explicit library path to `SELENIUM_CORE_LIB`
when a consumer's loader does not distinguish glibc and musl automatically.

Supported `--platform` values are:

```text
linux-x86_64  linux-arm64  linux-x86_64-musl  linux-arm64-musl
macos-x86_64  macos-arm64
windows-x86_64  windows-arm64
freebsd-x86_64
```

The manifest records the tag, resolved commit, selected source paths and
platforms, and a SHA256 for every copied file. Release libraries are checked
against the `.sha256` sidecars during both sync and verification. Verify the
snapshot later with:

```sh
python3 tools/selaenium-vendor.py verify third_party/selaenium/manifest.json
```

Verification resolves the tag again, downloads the source archive by its
recorded commit and the selected release assets, checks their hashes against
the manifest, then checks the vendored files on disk. A moved/deleted tag, a
changed source file, a changed native library, or an incomplete release fails
verification. Keep the helper, manifest, and vendored files in the same
reviewable consumer commit; project-specific build files and policies remain
with the consumer.
