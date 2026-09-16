# ae 0.677 codegen: whole-program build emits an unresolved `sha1.free_ctx`

> **STATUS: FIXED upstream — aether PR #2045 (2026-09-16), lands in 0.678.0+.**
> Root cause: the typechecker tracked imported namespaces in a FIXED
> `char* imported_namespaces[64]` and `register_namespace` guarded
> `if (namespace_count < 64)`, so a merged `--emit=lib` unit registering >64
> namespaces silently DROPPED every one past the 64th; a qualified call into a
> dropped namespace then failed to resolve → the spurious E0301, including the
> compiler-generated `sha1.free_ctx` cleanup for a `Sha1Ctx` reached through
> std.http/std.cryptography. 0.677's crypto/TLS graph pushed the count past 64;
> the cap itself was old (latent on 0.675, as observed here). The fix grows both
> namespace tables dynamically (2×, seeded at 64) — no cap; the threshold is
> gone, not merely raised. Pinned by aether tests/integration/many_namespaces_
> qualified_call. NOT released yet — held at 0.675 until 0.678.0+ tags.
>
> When 0.678.0+ tags, re-test a fresh `aeb selenium_core/.build.ae` on it, then:
> (1) bump `AETHER_REF` past 0.677 in ci/versions.env + README; (2) move the
> `.side` playback engine out of shell.ae back into its own side_run.ae module
> (it was folded into shell.ae only to stay under the namespace count).

Found porting Selenium (selaenium): after bumping the toolchain to ae 0.677.0,
the pure-Aether engine shared library stopped compiling — with an error that
points at no line of our source.

## Observed

`aeb selenium_core/.build.ae` (which runs `ae build --emit=lib --with=net …` over
`selenium_core/embed.ae` and its import graph) fails type-checking with:

    error[E0301]: Undefined function 'sha1.free_ctx'
      --> …/selenium_core/embed.ae:623:24     (a MERGED-unit line; embed.ae is 512 lines)

`sha1.free_ctx` appears nowhere in our source. `std.cryptography.sha1` both
**defines** `free_ctx` (module.ae:322) and **exports** it (module.ae:19), and
the module is byte-identical between 0.675 and 0.677 (same `free_ctx` count). No
Aether std module textually calls `sha1.free_ctx` either — the reference is
compiler-generated (an auto cleanup call for a `Sha1Ctx` reached transitively
through the http/TLS graph).

The trigger is **whole-program graph size**, not any one module's content:

- The exact same engine source builds **clean on ae 0.675** and **fails on ae
  0.677** (fresh build; a stale cached .so masks it).
- On 0.675 the current engine builds, but adding **any one extra module** to
  `embed.ae`'s imports — even a no-op `foo() -> string { return "x" }` that
  imports only `std.string` — makes 0.675 emit the same `sha1.free_ctx` error.
  So the bug is latent on 0.675 too; 0.677 simply lowered the threshold below our
  present module count.

So: the compiler generates an unresolved cross-module `sha1.free_ctx` cleanup
call once the merged `--emit=lib` unit passes a size/complexity threshold, and
0.677 regressed that threshold under our existing graph.

## Minimal repro (on 0.677)

Take any Aether library whose import graph transitively pulls `std.http` /
`std.cryptography` (selaenium's `embed.ae` does, via `std.http.client` in
`selenium_core.ae` + `selenium_bidi.ae`), then add ONE trivial module to its
imports:

    // extra.ae
    import std.string
    noop() -> int { return 0 }

    // embed.ae  (add these two)
    import extra
    sel_embed_probe(x: int) -> int { return extra.noop() }

`ae build --emit=lib --with=net,os,fs embed.ae -o out.so` then fails with
`Undefined function 'sha1.free_ctx'`, though `extra.ae` has nothing to do with
crypto. Remove the extra module → builds clean.

## Impact

Blocks any growth of the engine's module set and blocks the whole 0.677 line for
selaenium. It is not selaenium-specific: any Aether `--emit=lib` program whose
graph reaches the crypto/TLS modules and is near this threshold will hit it.

## Suggested fix

The auto-generated `Sha1Ctx` cleanup call must resolve `sha1.free_ctx` through
the same module-export path a hand-written `sha1.free_ctx` call uses (it is
exported). Likely the whole-program merge drops or mis-qualifies the generated
free call's module reference above the threshold — the codegen should emit the
same qualified symbol the resolver already accepts for explicit calls, or elide
the cleanup when the ctx is owned elsewhere.

## Workaround in place

`ci/versions.env` holds `AETHER_REF=v0.675.0` (aeb stays at v0.312, whose 0.677
AETHER_PIN is a floor recommendation, not a hard gate — every node builds green
on 0.675). Re-test a fresh `aeb selenium_core/.build.ae` on any candidate ae past
0.677 before bumping.
