# OPEN — ae add must distinguish musl and glibc binary packages

Upstream issue: https://github.com/aether-lang-dev/aether/issues/3073
Producer-side companion: https://github.com/aether-lang-dev/aeb/issues/17

`tools/ae.c`'s `ae_host_triple()` returns plain `linux-x86_64`/`linux-arm64`
without a libc distinction. Meanwhile aeb's `_ae_build_triple_to_asset()` folds
`*-linux-musl` to the same plain-Linux asset name. Its tests explicitly assert
that folding, so publishing glibc and musl ae-add packages in one release can
overwrite one with incompatible bytes.

The release workflow publishes musl raw FFI libraries under distinct
`linux-{x86_64,arm64}-musl` names, and deliberately leaves them out of ae-add.
The seven existing ae-add targets keep their original identities.

The fix belongs upstream: agree distinct musl identities in the emitter and
installer; retain glibc names; test both CPU variants and ensure neither libc's
assets can overwrite or be selected for the other. Explicit foreign-target
fetching should use the same naming contract. This finding comes from source
inspection, not an Alpine runtime test.
