# aeb `get.sh`: an unversioned (source-built) aeb on PATH can never be upgraded

Found 2026-09-12 while bringing a dev box onto the repo's pinned toolchain by
following the README one-liner. Upstream bug in **aeb's `get.sh`**, not in this
repo. Related to — and not fixed by — the earlier
`asks/get-sh-skips-on-presence-ignores-explicit-aeb-ref.md`.

## Symptom

The box had a source-built `aeb` reporting `0.0.0-dev+a283f1f51d25 (git
v0.286-54-g21597e7)`. `ci/versions.env` pins `AEB_REF=v0.307`. Running the
README's own install line:

```sh
curl -fsSL https://raw.githubusercontent.com/aether-lang-dev/aeb/main/get.sh \
  | AE_PIN=0.650.0 AEB_REF=v0.307 sh
```

upgraded `ae` to 0.650.0 as asked, then said:

```
aeb-get: aeb (source build, unversioned) already on PATH — skipping floor check
aeb-get: using aeb: /home/paul/.local/bin/aeb
aeb-get: done. Pin this in CI with: AE_PIN=0.650.0 AEB_REF=v0.307
```

It exits 0 and claims the pin is satisfied, but aeb was NOT upgraded — the
v0.286 build stayed. Every `aeb <node>` then failed with

```
error: unresolved import 'cache': no module of that name was found in
       src/, the project root, and installed packages
```

on *every* node, including untouched pre-existing ones, which is what makes it
look like a repo problem rather than a toolchain one.

## Cause

In `aeb_ensure`, the unversioned case returns before any pin comparison:

```sh
if [ "$_have" = "0.0.0" ]; then
    say "aeb (source build, unversioned) already on PATH — skipping floor check"
    say "using aeb: $(command -v aeb)"; return 0
fi
if [ -n "$_want" ] && [ -n "$_have" ] && [ "$_want" != "$_have" ]; then
    if version_ge "$_have" "$_want" && [ -z "${AEB_FORCE:-}" ]; then   # <- AEB_FORCE only here
```

`AEB_FORCE=1` does not help: it is only consulted in the *newer-than-requested*
branch, which the early return makes unreachable. So there is no supported way
to move a source-built aeb onto a pinned one.

The earlier ask fixed the "explicit AEB_REF ignored" case for *versioned*
installs; the `0.0.0` path was left with the original unconditional skip.

## Workaround

Move the unversioned binary aside and re-run — then it installs v0.307 cleanly
(sha256-verified binary):

```sh
mv ~/.local/bin/aeb ~/.local/bin/aeb.stale.bak
curl -fsSL .../get.sh | AE_PIN=0.650.0 AEB_REF=v0.307 sh
```

Note also that the `ae` half installs to `~/.local/bin/ae`, which a box using
the `~/.aether/bin` version manager will shadow — `ae --version` still reported
0.638.0 afterwards. `ae install 0.650.0 && ae version use v0.650.0` is what
actually switches such a box.

## Suggested fix

Honour an explicit `AEB_REF` (or at minimum `AEB_FORCE=1`) in the `0.0.0` case:
an unversioned build is the one we know LEAST about, so it is the weakest
candidate for "already fine, skip", not the strongest.
