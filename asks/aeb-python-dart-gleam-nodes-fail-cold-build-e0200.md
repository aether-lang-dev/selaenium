# aeb: python/dart/gleam nodes cannot COLD-build under ae 0.675 (E0200 narrowing)

> **STATUS: FIXED upstream (2026-09-15)** in aeb `1415206` — the mtime
> accumulators in the python/dart/gleam/moonbit SDK modules are `long` now.
> Mirrored as aeb `asks/mtime-accumulators-narrow-to-32-bit-e0200.md`.

The pinned pair in `ci/versions.env` — `AEB_REF=v0.311`, `AETHER_REF=v0.675.0` —
cannot build the python, dart or gleam nodes **from a clean tree**. A warm tree
hides it completely, which is why it went unnoticed: the generated node objects
are already cached, so the broken step never re-runs.

## Observed

Fresh `git worktree` (no `target/`), any commit — reproduced at 77dc4b2, at
f2fe5e6, and at HEAD, so it is not a selaenium source regression:

    $ aeb python/.tests.ae
    error[E0200]: narrowing assignment to 'newest': its type was inferred as
    32-bit int from its initializer, but a 64-bit value is assigned here and
    would truncate.
      --> target/_aeb/python__D_tests_D_ae.ae:1134:37
    Type checking failed with 1 error(s)
    cc1: fatal error: target/_aeb/python__D_tests_D_ae.c: No such file or directory
    aeb-link: FATAL — failed to link the fan-out orchestrator

Same error for `aeb dart/.tests.ae` and `aeb gleam/.tests.ae`.

## Cause

It is aeb's own SDK code, inlined into the generated node, not anything in this
repo. `lib/python/module.ae:1120` (and the identical helper in `lib/dart`,
`lib/gleam`, `lib/moonbit`):

    _dir_newest_mtime(dir_abs: string) {
        ...
        newest = 0                 // inferred 32-bit int
        ...
                t = file.mtime(full)
                if t > newest { newest = t }   // file.mtime is 64-bit -> E0200

`newest = 0` infers a 32-bit int; `file.mtime()` yields 64 bits. E0200 landed in
ae 0.667+, so aeb v0.311's mtime-staleness helpers stopped type-checking against
the ae version aeb v0.311 itself requires.

`lib/moonbit/module.ae:656` has the same line; there is no moonbit node here, so
it is untested but presumably equally affected.

## Suggested fix

Declare the accumulator 64-bit in all four SDK modules:

    long newest = 0

and likewise `newest_in` / `dir_newest` / `oldest_out` in the same staleness
helpers wherever they hold an mtime.

## Impact

Any CI runner or contributor starting from a clean checkout cannot build three
binding nodes. Locally it only appears once `target/_aeb` is removed. Nothing in
selaenium can route around it — the offending code is inside the aeb SDK that
gets inlined into every generated node.

## Status

Fixed upstream in aeb `1415206` once that scope was lifted, and mirrored into
~/scm/aeb/asks/ as `mtime-accumulators-narrow-to-32-bit-e0200.md`.
