# FIXED — ae add must distinguish musl and glibc binary packages

Upstream issue: https://github.com/aether-lang-dev/aether/issues/3073
Producer-side companion: https://github.com/aether-lang-dev/aeb/issues/17

Fixed by Aether `9918f257` (released in 0.838.0) and aeb `466de8f`
(released in v0.329, also included in v0.330). aeb `22cc8b1` in v0.330
also makes its SDKs compile on Aether 0.838.0. Selaenium now pins that
released pair. GNU and musl names remain distinct on both CPU architectures.

The temporary musl ae-add exclusion described below belongs to the sibling
servirtium-vcr binary-package release path. Selaenium's `aether.toml` exports
source modules; its raw FFI downloads already have distinct musl names.
Original findings follow for reference.

`tools/ae.c`'s `ae_host_triple()` returns plain `linux-x86_64`/`linux-arm64`
without a libc distinction. Meanwhile aeb's `_ae_build_triple_to_asset()` folds
`*-linux-musl` to the same plain-Linux asset name. Its tests explicitly assert
that folding, so publishing glibc and musl ae-add packages in one release can
overwrite one with incompatible bytes.

The servirtium-vcr release workflow published musl raw FFI libraries under distinct
`linux-{x86_64,arm64}-musl` names, and deliberately leaves them out of ae-add.
The seven existing ae-add targets keep their original identities.

The fix belongs upstream: agree distinct musl identities in the emitter and
installer; retain glibc names; test both CPU variants and ensure neither libc's
assets can overwrite or be selected for the other. Explicit foreign-target
fetching should use the same naming contract. This finding comes from source
inspection, not an Alpine runtime test.
