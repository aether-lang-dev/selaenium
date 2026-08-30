# Atoms — the executeScript-backed commands

A few WebDriver commands have **no direct W3C HTTP endpoint**: `isDisplayed`,
`getAttribute` (the classic property-or-attribute form), and `getText` (the
visible-text form). Classic Selenium implements these as compiled JavaScript
"atoms" (`bot.dom.isShown`, `bot.dom.getProperty`, …) that are injected into the
page via `executeScript`.

In this reboot the atom source and the executeScript orchestration live **once**
in the engine (`selenium_core/atoms.ae` + `selenium_core.execute_atom`), exposed
over the flat C ABI, so every binding gets identical semantics instead of each
re-implementing the JS. This mirrors the whole project's stance: one engine, thin
bindings.

## How it works

1. `atoms.atom_body(name)` holds the atom's JS function source (a self-contained
   `function(el, …){ … }`).
2. `atoms.atom_script(name)` wraps it as `return (<body>).apply(null, arguments);`.
3. `atoms.atom_args(elem_id, extra_json)` builds the executeScript `args` array —
   the target element as a W3C element reference first, then any extra args. The
   remote end rehydrates the reference into the live DOM node the atom receives as
   `arguments[0]`.
4. `selenium_core.execute_atom(sp, name, elem_id, extra_json)` assembles the
   `{script, args}` params and runs them through the existing `executeScript`
   path, so the result drains via the normal `last_value` accessor and errors map
   the normal way.

## The ABI

    int aether_sel_embed_execute_atom(void* h, const char* atom, const char* elem_id, const char* extra_json);
    int aether_sel_embed_is_displayed(void* h, const char* elem_id);          // last_value: JSON boolean
    int aether_sel_embed_get_attribute(void* h, const char* elem_id, const char* name);  // last_value: JSON string|null
    char* aether_sel_embed_atom_str_arg(const char* s);   // ["<s>"], for an atom's extra_json

`execute_atom` is the general seam; `is_displayed`/`get_attribute` are the two
convenience verbs. `extra_json` is a JSON array of extra args (`["href"]`), or
`""`/`"[]"` for none.

## The atoms

- **isDisplayed** — a compact `bot.dom.isShown`: detached nodes, `display:none` /
  `visibility:hidden|collapse` / `hidden` / `opacity:0` up the ancestor chain,
  `<input type=hidden>`, and zero-size-without-overflow all read as not shown.
- **getAttribute** — the property-or-attribute algorithm: boolean attributes
  return `"true"`/`null`, a set of names read the live property (`value`,
  `checked`, `selected`, `disabled`, `class`→`className`, `for`→`htmlFor`, …),
  everything else falls through to `getAttribute`. This differs from W3C
  `getDomAttribute`, which returns only the literal attribute.
- **getText** — visible text with whitespace collapsed + trimmed.

## Tests

- `selenium_core/tests/atoms_probe.ae` — pure unit test of the params assembly
  (no browser), in presubmit.
- The atoms run live in the per-binding suites (e.g. the native Aether client's
  `is_displayed` on a visible vs `display:none` element, and `get_attribute`
  resolving an `href`).

## Adding an atom

Add its JS body to `atoms.ae` (`_ATOM_<NAME>` + a case in `atom_body`), and
either call it via `execute_atom` from a binding or add a convenience ABI verb.
`findElementsRelative` (relative locators) is the natural next atom.
