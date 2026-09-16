# FreeBSD cross-build (--emit=lib --target=*-freebsd): `--lib` module drops + mcontext_t

> **STATUS: FIXED upstream — aether PR #2047 (2026-09-16), lands in 0.679.0+.**
> Both filed symptoms were red herrings; the real blocker was a link-step bug,
> now fixed:
> - Symptom 1 (`--lib` "drop"): spurious warn-only prepass message printing for
>   every cross target while the build succeeds. Cosmetic; #2047 forwards `--lib`
>   in the prepass so the noise is gone.
> - Symptom 2 (`mcontext_t`): a transient artifact of the parallel full-matrix
>   run. In isolation the exact `zig cc -target x86_64-freebsd.15.0 --sysroot=…`
>   line compiling embed.ae's `.so.c` with `-c` produces a clean 528KB `.o`, no
>   error. The sysroot headers are fine.
> - REAL blocker (isolated here): `ld.lld: error: undefined symbol: main` on
>   `ae build --emit=lib --target=x86_64-freebsd`. Root cause (sibling): the
>   FreeBSD cross-link branch in aether tools/ae_cross.c was written for the exe
>   path and never passed `-shared -fPIC` for `--emit=lib` (linux/macos/windows
>   did); no `-shared` → crt1.o → ld demands `main`. #2047 makes the freebsd
>   branch apply `-shared -fPIC` (+ strip) for `--emit=lib`; exe path untouched.
>   Verified upstream: `--emit=lib` → ELF shared object exporting `aether_*`, no
>   main.
>
> WHEN 0.679.0+ tags: re-run `TARGETS=x86_64-freebsd release/build.sh` (with
> AETHER_SYSROOT set to a FreeBSD base sysroot) to add the freebsd `.so` to a
> release. ONE open item neither box could do: run the linked `.so` under actual
> FreeBSD (only ELF shape + exported symbols verified, not a live load) — smoke-
> test a fetched freebsd `.so` on real FreeBSD after the tag to fully close it.
> Blocks only the FreeBSD leg; v0.8.0 shipped the other 6 artifacts.

Found cutting selaenium v0.8.0: `release/build.sh` cross-compiles the pure-Aether
engine (`libselenium_core`) for the whole matrix from one Linux host via zig. The
core (linux/macos) and Windows targets build cleanly; both FreeBSD targets fail.

## Environment

- ae 0.678.0, zig 0.16.0, Linux host.
- `AETHER_SYSROOT` = the extracted FreeBSD base sysroot shipped by the aether
  0.678.0 release itself (`aether-0.678.0-freebsd-x86_64-sysroot.tar.xz` → a tree
  with `lib/libc.so.7`, `usr/lib/libc.so`, `usr/include/...`).

## The exact command (identical for every target, only `--target` differs)

    cd selenium_core && ae build --emit=lib --with=net,os,fs --lib drivermgr \
      --size --target=x86_64-freebsd embed.ae \
      --extra "$PWD/_embed_strdup.c" -o out.so

`--lib drivermgr` makes the engine's Selenium-Manager module tree (imported by
bare name from embed.ae: `resolve`, `browser`, `cft`, `drivercache`, …) resolvable.
It works for `x86_64-linux`, `aarch64-linux`, `x86_64-macos`, `aarch64-macos`,
`x86_64-windows`, `aarch64-windows`.

## Observed (FreeBSD only)

    error: unresolved import 'resolve': no module of that name was found in
      src/, the project root, and installed packages
    aborting: 1 error(s) found
    ld.lld: error: undefined symbol: main
    Error: cross-linking for x86_64-freebsd.15.0 failed.

And, seen in the full `release/build.sh` run, a second (sysroot-header) symptom:

    .../fbsd-sysroot/usr/include/sys/_ucontext.h:44:2:
      error: unknown type name 'mcontext_t'

Two distinct problems:

1. **`--lib drivermgr` is dropped for a `*-freebsd` target.** The same `--lib`
   resolves the `resolve` module for every other target; under `--target=*-freebsd`
   the compiler reports it unresolved. Something in the freebsd cross path isn't
   adding the `--lib` dir to the module search path (the `undefined symbol: main`
   is the cascade: with embed.ae's imports unresolved, no lib entrypoint is emitted).

2. **`mcontext_t` unknown in the sysroot's `<sys/_ucontext.h>`.** Even past (1),
   the FreeBSD base sysroot's ucontext header doesn't type-check under zig's libc
   for this target — a sysroot/target ABI-header mismatch (note zig resolved the
   triple as `x86_64-freebsd.15.0`; the sysroot may be a different base version,
   or a machine/ucontext include is missing from the shipped sysroot subset).

## Suggested investigation

- Confirm whether `--lib <dir>` is honored on `--target=*-freebsd` the same as on
  linux/macos/windows (looks target-gated — a cross-path that rebuilds the module
  search list may omit the `--lib` entry for freebsd).
- The shipped `aether-*-freebsd-x86_64-sysroot.tar.xz` may be an incomplete subset
  (missing `machine/ucontext.h` or a `sys/` dep) or keyed to a FreeBSD base version
  that doesn't match the `.15.0` triple zig assumes. A matching/complete sysroot,
  or pinning the freebsd OS version in the triple, may clear the `mcontext_t` error.

## Workaround in place

`release/build.sh` already "skips loudly" when `AETHER_SYSROOT` is unset; with it
set, FreeBSD fails as above. v0.8.0 shipped the other 6 engine artifacts (linux
arm64/x86_64 `.so`, macos arm64/x86_64 `.dylib`, windows arm64/x86_64 `.dll`).
FreeBSD is added to a later release once (1) and (2) are fixed upstream.
