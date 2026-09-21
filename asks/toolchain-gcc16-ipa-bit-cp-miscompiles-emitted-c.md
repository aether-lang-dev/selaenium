# toolchain: gcc 16 `-O2` miscompiles aetherc-emitted C (IPA bit-CP folds a live `int` parameter to 0)

> **Scope: not a selaenium bug.** Grid's `registry.ae` is correct. This is the
> toolchain: on gcc 16, `aeb`'s default `-O2` (lib/aether/module.ae:1645) silently
> produces a binary in which a function parameter that genuinely varies at runtime
> is replaced by the constant `0`. Any aether program is exposed, not just Grid.

## One-line reproducer (no linking, no running, no libaether)

    aetherc --with=net,os,fs --lib grid --lib selenium_core --lib selenium_core/drivermgr \
            grid/hub.ae /tmp/hub_exe.c
    gcc -E -fwrapv $(ae cflags --cflags) /tmp/hub_exe.c -o /tmp/hub_exe.i
    gcc -O2 -S /tmp/hub_exe.i -o /tmp/bad.s     # <- inspect registry__row

In `registry__row`, the second `string_from_int` call is fed a hard zero:

    	movl	%ecx, %edi
    	call	string_from_int@PLT     # from_int(max)      -- correct
    	xorl	%edi, %edi              # from_int(inuse)    -- WRONG: %r8d discarded
    	call	string_from_int@PLT

With `-fno-ipa-bit-cp` the same source compiles correctly:

    	movl	%ecx, %edi
    	call	string_from_int@PLT     # from_int(max)
    	movl	%r12d, %edi             # from_int(inuse)    -- the real 5th argument
    	call	string_from_int@PLT

`%r8d` is the 5th SysV integer argument — `inuse`. gcc 16 dropped the parameter
entirely; the good build spills it to `%r12d` in the prologue.

## Why the constant is wrong

`registry__row(id, address, browsers, max, inuse, now_ms)` has exactly two call
sites in the translation unit:

    registry__row(id, address, browsers, max, 0, registry__now_ms())   // register()
    registry__row(i, addr, br, max, inuse, last_ms)                    // _drop_and_add()

The second carries a genuine runtime value along an unbroken chain:

    register_node_handler:  inuse = _int_field(root, "inuse")   // parsed from the POST body
      -> registry_report_inuse(ud, id, inuse)
        -> registry__set_inuse(rin, id, n)
          -> registry__drop_and_add(..., inuse, ...)
            -> registry__row(..., inuse, ...)

Meeting a constant `0` with an unknown value must yield unknown. gcc 16 yields `0`.

## Flag matrix (gcc 16.2.1, assembly-level, same `.i` every row)

| flags | `registry__row` |
|---|---|
| `-O0`, `-O1`, `-Og` | ok |
| `-O1 -fipa-cp` | ok |
| `-O1 -fipa-bit-cp` | ok |
| **`-O1 -fipa-cp -fipa-bit-cp`** | **miscompiled** |
| **`-O2` / `-O3` / `-Os`** | **miscompiled** |
| `-O2 -fno-ipa-cp` | ok |
| `-O2 -fno-ipa-bit-cp` | ok |
| `-O2 -fno-wrapv` | miscompiled |
| `-O2 -fno-inline` | miscompiled |
| `-O2 -flto` | ok |

Necessary and sufficient trigger: **`-fipa-cp` and `-fipa-bit-cp` together.**
Confirmed in both directions — removing either from `-O2` fixes it, and adding
both to a clean `-O1` breaks it.

## Cross-compiler control

Same `hub.ae`, same aetherc, byte-identical 1.78 MB emitted C, built on a second
box with **gcc 12.2.0 / glibc 2.36**: correct at `-O0`, `-O1` *and* `-O2`, 5/5 runs.
Broken box is **gcc 16.2.1 / glibc 2.44**. So it is the compiler version, not the
distro, the libc, or the CPU. The window between 12 and 16 is unbisected here
(only gcc 16 is installed on the failing box).

**Confirmed at the ASM level on the gcc-12 box (same `.i`, `gcc -O2 -S`) — the
control is a clean two-compiler instruction diff, not just a runtime A/B:**
`registry__row`'s prologue on gcc 12 SPILLS the 5th arg and USES it at the call:

    	movl	%r8d, %r12d      # prologue: save the 5th SysV int arg (inuse) to %r12d
    	...
    	movl	%ecx, %edi
    	call	string_from_int@PLT   # from_int(max)
    	movl	%r12d, %edi           # from_int(inuse) -- the real value, from %r12d
    	call	string_from_int@PLT

Zero occurrences of `xorl %edi, %edi` in `registry__row` on gcc 12. So the diff is
exactly: **gcc 12 → `movl %r12d,%edi` (real inuse); gcc 16 → `xorl %edi,%edi`
(folded to 0)**, from identical preprocessed input. That is the whole bug in one
instruction, at compile time, on two compilers.

## Why this hid for so long

* **ASAN and UBSAN are both silent.** There is no memory error and no UB — gcc
  simply emits wrong code. Every sanitiser run reported zero errors *while the
  program was misbehaving*.
* **Every probe "fixed" it.** Adding a debug call, adding a gate, adding a second
  caller with a different constant — each changes IPA-CP's lattice, so the
  Heisenbug pattern was the bug's signature, not noise.
* **It looks like data corruption.** The symptom was a registry row losing a
  field, which reads as a use-after-free or a lost write. It is neither.

## Which knob actually matters

`aeb` does **not** compile an `aether.program()` node itself — it shells out to
`ae build`, so the `-O2` that miscompiles the hub is **aether's**, not aeb's:

    execve("/home/paul/.aether/bin/ae", ["ae", "build", ".../grid/hub.ae", "-o", ...])

`ae`'s release C flags are `-O2 -pipe -Wformat -fwrapv` (from `strings` on the
`ae` binary). Overriding the compiler through `AE_CC` fixes the real build:

    $ aeb grid/.build.ae                                  # md5 ef804b04f091 -> "inuse":0
    $ AE_CC="gcc -fno-ipa-bit-cp" aeb grid/.build.ae       # md5 07d2ddc18aa0 -> "inuse":3

(both on a cold `~/.aether/cache` — see the caching note below.)

## What we would like

1. **aether** (primary) — add `-fno-ipa-bit-cp` to the release C flags used by
   `ae build` / `aetherc`, and to the flags used to build the toolchain itself.
   An `ae`/`aetherc` binary built by gcc 16 at `-O2` is exposed to this too, as
   are aeb's own `tools/` (they are built with `ae build`). `-fno-ipa-cp` also
   works but costs more; `-fno-ipa-bit-cp` is the minimal disable. Gating on
   gcc >= 16 is fine, but unconditional is safer — the upper bound is unknown.
2. **aeb** (secondary) — `lib/aether/module.ae`'s *manual* gcc path
   (`aether_link_cmd`, the `opt_flags = "-O2"` site) compiles aetherc-emitted C
   directly and has the same exposure. Patched here with the same flag;
   `tests/test_aether_cmd.ae` expectations updated, 151/151 aeb unit tests pass.
   Not exercised end-to-end by the Grid repro, which takes the `ae build` path.
3. **gcc** — worth an upstream report. The `.i` above is self-contained and the
   check is `gcc -O2 -S` plus one grep; no reduction was attempted here.

## Side finding: the build caches do not key on the C compiler

Neither `~/.aether/cache` (used by `ae build`) nor aeb's result cache includes
the compiler identity or its flags. `AE_CC=... aeb grid/.build.ae` returned a
byte-identical binary from cache until `~/.aether/cache` was moved aside, and
`rm -rf target/` alone never forced a recompile. That is the same hazard as
aeb's existing `asks/cache-key-omits-toolchain-identity.md`, one level down: a
gcc upgrade (or a flag change like this workaround) silently keeps serving
objects built by the old compiler. Anyone verifying this fix must clear
`~/.aether/cache`, or they will measure the cache instead of the compiler.

## Verification

Grid at `7fad6ee` (unmodified `hub.ae`), POST a node with `maxSessions:7, inuse:3`
then GET `/se/grid/status`:

    aeb-built (-O2)                 -> "inuse":0     WRONG
    hand-built -O2 -fno-ipa-bit-cp  -> "inuse":3     correct   (3/3)
    hand-built -O1                  -> "inuse":3     correct
    gcc 12, -O2                     -> "inuse":3     correct   (5/5, second box)

A write/read-side dump inside `report_inuse` on the failing build shows the inputs
are all intact — `n` is 3, the table read is correct, `_find_row` returns the right
row — and only the rebuilt row carries `0`. That is the folded parameter, nothing else.

---

## OUTCOME (2026-09-21): confirmed a gcc bug, not UB in the emitted C

Nic raised the right objection on aether#2128 — if the varying value were
indeterminate on some path, reading it is undefined and gcc's bit lattice may
legitimately meet `0` with "anything" and yield `0`. ASAN/UBSAN silence and
"every probe fixes it" are both consistent with that, and aetherc does hoist
branch-locals as bare declarations (`hoist_if_branch_vars`/`hoist_loop_vars`),
which aether#2131 now zero-initializes. Tested on the failing box. It is not
the cause here, on three independent grounds.

### 1. Defining every automatic does not stop the fold

    gcc -O2                                  -> folded to 0
    gcc -O2 -ftrivial-auto-var-init=zero     -> folded to 0
    gcc -O2 -ftrivial-auto-var-init=pattern  -> folded to 0
    gcc -O2 -fno-ipa-bit-cp -ftrivial-auto-var-init=zero -> correct

`-ftrivial-auto-var-init` defines *every* automatic in the TU, which is a
superset of what aether#2131's hoisted-declaration initializers do. The fold
survives it. `-Wtrivial-auto-var-init` reports nothing it could not initialize,
and `-Wmaybe-uninitialized -Wuninitialized` over the whole TU: **0 warnings**.

### 2. No hoisted branch-local exists anywhere on the `inuse` chain

Bare (uninitialized) scalar declarations in each function of the chain:

| function | bare uninitialized scalar decls |
|---|---|
| `register_node_handler` | 0 |
| `registry_report_inuse` | 0 |
| `registry__set_inuse` | 0 |
| `registry__drop_and_add` | 0 |
| `registry__row` | 0 |

Every binding is initialized at its declaration and defined on every path:

    int inuse = ae_int_field(root, "inuse");   // handler; ae_int_field returns
    if (inuse < 0) { inuse = 0; }              //   0 or json_get_int(v) — total
    registry_report_inuse(ud, id, inuse);      // -> param n
      registry__set_inuse(rows, id, n)
        int inuse = n;                          // initialized
        registry__drop_and_add(..., inuse, ...) // -> param
          registry__row(..., inuse, ...)        // -> param #4

The hoisted `int nl; int line_end; int max; int inuse;` shape Nic describes IS
present in this file — in `registry__pick`, `registry__find_row` and
`registry__drop_row`. None of them is on this chain, and none feeds param #4.
(aether#2131 is still a good change on its own merits; it just is not this.)

### 3. gcc's own lattice dump shows the defect, and it is not a constant fold

`-fdump-ipa-cp-details` on the failing build. The value lattice is **VARIABLE** —
gcc did *not* conclude the parameter is a constant. It is the **known-bits mask**
that is wrong:

    Node: registry__row/298:
      param [4]: VARIABLE                       <- correctly NOT a constant
           Bits: value = 0x0, mask = 0xf..f00000000
           [irange] int [0, +INF]

In this dump, a mask bit of 1 means "unknown". `mask = 0xf..f00000000` says bits
32-63 are unknown and **bits 0-31 are known to be 0** — i.e. for a 32-bit `int`,
the whole value is known zero. Codegen then materialises `xorl %edi,%edi`.

The caller's entry for the same parameter contradicts itself:

    Node: registry__drop_and_add/302:
      param [6]: VARIABLE
           Bits: value = 0x0, mask = 0xf..f00000000        <- low 32 known zero
           [irange] int [0, +INF] MASK 0x7fffffff VALUE 0x0 <- low 31 UNKNOWN

The irange carries the correct `MASK 0x7fffffff` (the clamp `if (inuse < 0)
{ inuse = 0 }` makes it non-negative, so 31 unknown bits). The Bits lattice for
the same parameter has lost exactly those unknown bits. `0xf..f7fffffff` — the
correct mask — appears 11 times elsewhere in the same dump, so the representation
is capable of expressing it.

Control, from the same dump: `registry__f`'s `int i` parameter genuinely takes
0..5 across its call sites and gets `mask = 0xf..f00000007` — low 3 bits unknown.
Correct, and confirms the mask convention.

The jump functions are also correct, so the wrong mask is not bad input:

    registry_register/288    -> registry__row/298 : param 4: CONST: 0  [irange] int [0,0]
    registry__drop_and_add/302 -> registry__row/298 : param 4: PASS THROUGH: 6, Unknown VR

A `CONST 0` met with an unknown must yield unknown. The value lattice got that
right (VARIABLE); the bits lattice did not.

### Correction to this document's earlier framing

Above, this was described as "IPA-CP folded the literal 0 from one call site into
the callee". The dump shows that is not what happened — the constant lattice
stayed VARIABLE. The defect is in **IPA bit-CP's known-bits mask**, which drops
the unknown-bit mask for a non-negative `int` parameter and leaves every bit
known-zero. Same wrong instruction, different mechanism; the distinction matters
for an upstream report and for anyone reading this later.

### Consequence

`-fno-ipa-bit-cp` is the correct response, and it is not papering over UB. Only
`-fno-ipa-bit-cp` / `-fno-ipa-cp` change the outcome; `-fno-ipa-vrp`,
`-fno-tree-vrp`, `-fno-ipa-sra`, `-fno-wrapv`, `-fno-inline` and
`-ftrivial-auto-var-init` all leave the fold in place. Gating on gcc >= 16 is
reasonable. aether#2131 should land on its own merits and is orthogonal.

### Direct test against aether#2131 (2026-09-21, aetherc 0.701.0)

The three grounds above were established on aetherc 0.699.0, which predates
aether#2131. Retested with the real fix rather than a proxy for it.

aetherc **0.701.0** contains #2131 (`617a24e6`, merged as `98a4c6af`) and the
change is visibly present in the emitted C:

    0.699.0:  int at = 0;  int nl;      int line_end;      int max;
    0.701.0:  int at = 0;  int nl = 0;  int line_end = 0;  int max = 0;

Bare uninitialized scalar declarations across the whole hub TU fall from **436
to 144** — and all 144 remaining are **struct field declarations**
(`typedef struct LocalTime { int year; int month; ... }`), not function locals.
**Zero uninitialized function locals remain in the translation unit.** #2131 is
complete for its purpose on this input.

The fold survives it, in the asm and at runtime:

    aetherc 0.701.0 + gcc 16.2.1 -O2                      -> FOLDED to 0    "inuse":0
    aetherc 0.701.0 + gcc 16.2.1 -O2 -fno-ipa-bit-cp      -> real arg       "inuse":3
    aetherc 0.701.0 + gcc 16.2.1 -O2 -ftrivial-auto-var-init=zero -> FOLDED to 0
    aetherc 0.699.0 + gcc 16.2.1 -O2                      -> FOLDED to 0    (unchanged)

Runtime legs are a hand-link of `hub_701.c` against 0.701.0's `libaether`, POST a
node with `maxSessions:7, inuse:3`, then GET `/se/grid/status`. Chain functions
under 0.701.0 still carry zero bare uninitialized scalars, as under 0.699.0.

So the test Nic proposed — *"if the fold survives with every local defined, it's
a real gcc 16 bug and `-fno-ipa-bit-cp` is the right response"* — has been run
against his own fix, and the fold survives. #2131 remains a good change; it is
simply not this bug.

Not yet covered: aether `8f1c041b` and `127a348d` (further hoisted-local fixes)
land after 0.701.0 and are not in this test. Worth re-running on 0.702.0.

Artifacts on the failing box (gcc 16.2.1, CachyOS), regenerable with the three
commands at the top of this document: `hub_main.c` (1.77 MB emitted),
`hub_main.i` (2.53 MB preprocessed, self-contained), `cp.dump` (10.9 MB
`-fdump-ipa-cp-details`).
