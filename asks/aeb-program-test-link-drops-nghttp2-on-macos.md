# aeb drops `-lnghttp2` from aether.program_test's manual link, so it fails on macOS

**Upstream:** filed in aeb as `asks/aeb-program-test-link-drops-nghttp2-on-macos.md`
(aeb 303b92b, 2026-10-10), found during the aether 0.801.0 + aeb v0.326 move. OPEN.

## Symptom

`aeb aether/.tests.ae` on macOS arm64 (released ae 0.801.0, released aeb v0.326)
compiles, then fails at the link:

```
Undefined symbols for architecture arm64:
  "_nghttp2_session_callbacks_del", referenced from:
      _aether_h2_session_new in libaether.a[32](aether_h2.o)
  ... (18 nghttp2_* symbols, all from aether_h2.o)
ld: symbol(s) not found for architecture arm64
tests:aether: gcc link failed (see target/tests/aether/_gcc_stderr.log)
```

The same node links and passes (1/1) on Linux (ae-x64, Ubuntu 22.04 x86_64,
same released pair).

## Cause

The generated C names the library itself, on its first line:

```
// aether-link: -lpcre2-8 -lssl -lcrypto -lnghttp2
```

aeb's manual gcc link (the `aether_link_cmd` path that program_test uses) reads
that header with `bldr._aether_link_libs`, but `_link_token_is_toolchain_managed`
(lib/bldr/module.ae) drops `-lnghttp2` along with `-lssl -lcrypto -lpcre2-8 -lz`,
on the grounds that `_resolve_sysdeps()` (lib/aether/module.ae) supplies them.
`_resolve_sysdeps()` only asks pkg-config for `zlib`, `openssl` and
`libpcre2-8`. So nghttp2 is filtered out as "toolchain-managed" and then never
added back. On macOS the release libaether.a carries aether_h2.o (18 undefined
`nghttp2_*` references, the same in 0.778, 0.791 and 0.801) and std.http pulls
it in.

`ae cflags --libs` on this box does list it:
`... -L/opt/homebrew/opt/libnghttp2/lib -lnghttp2 ...`.

## Not a 0.801 regression

The filter and the three-entry sysdeps list are the same in aeb v0.325 and
v0.326 (and on aeb main as of 2026-10-10), and 0.778's libaether.a has the same
nghttp2 references, so this predates the move.

## Suggested fix

Add `libnghttp2` to `_resolve_sysdeps()`'s module list (a missing .pc already
contributes nothing, so a toolchain built without nghttp2 is unaffected), or
take the set from `ae cflags --libs`, as the orchestrator link already does.
