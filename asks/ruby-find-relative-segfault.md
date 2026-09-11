# Ruby `find_relative` — flaky seed-dependent segfault (follow-up)

Found 2026-09-11 during the shadow-DOM parity sweep (unrelated to it — the
shadow work touches no relative-locator or FFI-marshalling code).

## Symptom
`ruby/spec/live_test.rb` intermittently **segfaults** in the native
`find_relative` FFI path:
- `ruby/lib/selenium/webdriver.rb:582-583` `find_relative` →
  `Native.call(:find_relative, @handle, base_css, JSON.generate(filters))`
- ABI decl `ruby/lib/selenium/native.rb:83`
  `aether_sel_embed_find_relative(void*, const char*, const char*) -> int`

Seed-dependent: reproduced on a **pristine tree** (shadow changes stashed) at
minitest `--seed 3`; passes at seeds 1 / 2 / 42072. So it is pre-existing and
order/seed sensitive, not caused by the shadow additions.

Environment: rbenv Ruby 3.3.12 (Fiddle), engine `.so` built by
`aeb selenium_core/.build.ae`, real headless Chrome 138 on this Linux box.

## Why it matters
A crash (not a Ruby exception) means memory unsafety at the FFI boundary or in
the engine's `find_relative` (findElementsRelative atom) path — Fiddle marshals
`base_css` + the `JSON.generate(filters)` string into `const char*`. Candidate
causes to investigate:
- a borrowed-vs-owned string lifetime bug across the Fiddle call (cf. the
  engine's own "own every stored getenv string" scars), or
- the relative-locator atom returning a shape the Ruby side then mis-drains
  (`last_value` / element-array unwrap) under specific interleavings.

## Cross-binding check — DONE: it is Ruby-Fiddle-specific, NOT engine-level
Stress-tested the engine's `find_relative` via the **D binding** (link-time FFI,
same `aether_sel_embed_find_relative` ABI): 150 calls in a tight loop with varied
below/near filters + `findRelativeCount`, against live headless Chrome —
**rock solid, zero crashes, consistent results**. So the engine's
`find_relative` path is sound and there is NO all-binding blast radius. The fault
is in **Ruby's Fiddle marshalling / result-drain of this specific call**, not the
engine.

## Likely cause + fix candidate (Ruby side)
`webdriver.rb`:
```
def find_relative(base_css, *filters)
  rc = Native.call(:find_relative, @handle, base_css, JSON.generate(filters))
  result = atom_result(rc) || []
  ...
```
The 2nd/3rd VOIDP args are Ruby Strings Fiddle auto-converts to pointers; the
inline `JSON.generate(filters)` temporary can be GC'd between the argument
conversion and the C read under specific allocation/GC interleavings (hence the
seed dependence). `Native.call` just does `functions.fetch(name).call(*args)` —
no pinning. FIX CANDIDATES to try: (a) bind the JSON to a local before the call
(`json = JSON.generate(filters); Native.call(..., base_css, json)`) so it stays
referenced across the call; (b) if that doesn't hold it, explicitly build a
`Fiddle::Pointer` from the frozen string bytes and keep it alive for the call
duration. Confirm by re-running `ruby -Ilib spec/live_test.rb --seed 3` (the
seed that reproduced) many times after the change. Note the same Fiddle
String→VOIDP pattern is used by `execute` (which passes inline `JSON.generate`
too and does NOT crash), so also compare the two call sites — the differentiator
may instead be in `atom_result`'s drain for the relative-locator result shape.

## Repro
```
cd ruby
export PATH="$HOME/.rbenv/shims:$PATH"
# build engine .so first: aeb selenium_core/.build.ae ; export SELENIUM_CORE_LIB=<repo>/selenium_core/native/libselenium_core.so
ruby -Ilib spec/live_test.rb --seed 3   # segfaults; --seed 1 passes
```
