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

## Cross-binding check needed
`find_relative` exists in several bindings (the D binding's `findRelative`,
nim `findRelative`, etc.). Determine whether the fault is in the **engine**
`find_relative` ABI (would affect ALL bindings — high blast radius) or only in
Ruby's Fiddle marshalling. Repro first in a pure C-ABI smoke against the same
seed/interleaving before blaming a binding.

## Repro
```
cd ruby
export PATH="$HOME/.rbenv/shims:$PATH"
# build engine .so first: aeb selenium_core/.build.ae ; export SELENIUM_CORE_LIB=<repo>/selenium_core/native/libselenium_core.so
ruby -Ilib spec/live_test.rb --seed 3   # segfaults; --seed 1 passes
```
