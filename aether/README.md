# `aether/` — the Aether-language client binding

Reserved for the **Aether-language** WebDriver client: the idiomatic Aether
surface over the shared engine, sitting alongside the other language bindings
(`../python/`, `../go/`, `../ruby/`, …).

Every binding — including this one — carries **no protocol logic**. The command
catalog, the W3C command→(method, path) route table, path templating,
By/capabilities normalization, the W3C error decode, and the HTTP round-trip all
live once in [`../selenium_core/`](../selenium_core/) and are reached over the
`aether_sel_embed_*` C ABI (`../selenium_core/embed.ae`). A binding opens a
session, issues commands by name with JSON params, reads back the result or a
typed error, and closes.

Unlike the FFI bindings, the Aether client can call the engine module directly
(no C ABI needed) — `import selenium_core` and drive it in-process. Scaffolding
lives here as the Aether surface lands.

See the [top-level README](../README.md) for the whole one-engine-many-bindings
picture and the full binding matrix.
