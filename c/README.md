# selenium (C)

Selenium WebDriver for C — the thinnest ergonomic layer over the shared
pure-Aether WebDriver engine (`libselenium_core`). A small `sel_*` API declared
in [`include/selenium.h`](include/selenium.h), implemented in
[`src/selenium.c`](src/selenium.c) over the engine's flat `aether_sel_embed_*` C
ABI.

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` (N independent sessions per process). It is **not** an
installation, a service, or a framework: no installer, no daemon, no config, no
special directories. The C client carries no protocol logic — the W3C command
map, routing, `By` normalization, error decode and the HTTP round trip all live
in that one library. C99, and no dependency beyond the engine `.so` (no JSON
library — structured results come back as JSON text for you to parse with
whatever library you like).

Like the other link-time bindings (rust/…), C **links the engine at build
time**: you compile your program against the header and link the engine `.so`,
so the `.so` must be present when you build — it is not fetched at run time.
Linking with `-Wl,-rpath` to the engine's directory bakes the path in, so the
built binary finds it later with no `LD_LIBRARY_PATH`.

## Using it (C app developer)

There is no package registry for C here — you consume the client by compiling
against `include/selenium.h` and linking the engine `.so`. The one C
translation unit `src/selenium.c` compiles to an object you link in (published
in the monorepo as the `c_objects` artifact, so a dependent links it without
recompiling).

```c
#include "selenium.h"
#include <stdio.h>

int main(void) {
    /* Resolve + launch a driver (downloads it if needed), then open on its URL. */
    sel_process *proc = sel_ensure_driver("chrome", NULL, 20000);
    sel_str url = sel_process_url(proc);
    sel_driver *d = sel_open(url.ptr);
    sel_free(url);

    sel_headless_chrome(d);
    sel_get(d, "https://example.com");

    sel_str title = sel_title(d);
    printf("%s\n", title.ptr);
    sel_free(title);

    sel_element *e = sel_find_element(d, "css selector", "h1");
    sel_str text = sel_text(e);
    printf("%s\n", text.ptr);
    sel_free(text);
    sel_element_free(e);

    sel_execute(d, "quit", "{}");   /* clean browser shutdown */
    sel_close(d);                   /* release the handle */
    sel_process_stop(proc);         /* kill + reap the driver */
    return 0;
}
```

Every `sel_str` you receive is caller-owned — free it with `sel_free` (not
`free()`); free every `sel_element` with `sel_element_free`. Most calls return
`0` on success, a W3C error code (`> 0`), or `-1` on transport failure;
`sel_last_error(d)` and `sel_last_error_code(d)` explain the last failure.

## Getting the engine + building (no Aether toolchain)

There is no runtime fetch — you compile against the header and link the engine
`.so` at build time. Fetch the prebuilt engine for this platform once, then
build with plain `gcc` — the compiler takes the engine path straight on the
command line, so no special env var is needed:

```sh
# once: populate the shared per-user cache from this project's GitHub releases
scripts/fetch-engine.sh

# then, from the repo root, build + run the C test against the fetched engine:
LIB=$(scripts/fetch-engine.sh --path); LIBDIR=$(dirname "$LIB")
gcc -Ic/include -c c/src/selenium.c -o selenium.o
gcc -Ic/include c/test/selenium_test.c selenium.o "$LIB" -Wl,-rpath,"$LIBDIR" -o selenium_test
./selenium_test
```

`$LIB` is an absolute path (so `SELENIUM_CORE_LIB=$(scripts/fetch-engine.sh
--path)` is the same value — either works). To build your own program instead
of the test, link `c/src/selenium.c` (or the shipped `c_objects`) + `"$LIB"` the
same way and add `-Ic/include`. `scripts/fetch-engine.sh` downloads from THIS
project's GitHub releases, verifies the `.sha256`, and caches under
`$XDG_CACHE_HOME/selaenium/<tag>/`; `TAG=vX.Y.Z` pins a release, `FORCE=1`
re-fetches.

With the Aether toolchain present, `aeb c/.tests.ae` builds the engine and runs
the FFI + live test instead; if you ran `scripts/fetch-engine.sh` first, that
build links the fetched `.so`. The `aeb`/`ae` toolchain is covered in the
top-level README — the `gcc` path above needs none of it.

The engine resolution order (mirroring `rust/build.rs`) is: `SELENIUM_CORE_LIB`
→ the bundled `c/native/libselenium_core.<ext>` slot (a published package ships
the `.so` there) → the shared fetch cache → the aeb-built engine artifact. See
[`AGENTS.md`](AGENTS.md) for the full resolution order and the engine version
pin, and [`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md)
for the prebuilt-engine flow.

## API surface (verified against `include/selenium.h`)

- Session: `sel_open`, `sel_close`, `sel_session_id`, `sel_set_ca`,
  `sel_set_insecure`, `sel_last_error`, `sel_last_error_code`.
- Browser factories: `sel_chrome`, `sel_headless_chrome`, `sel_firefox`,
  `sel_headless_firefox`, `sel_edge`, `sel_headless_edge`, `sel_safari`.
- Navigation: `sel_get`, `sel_title`, `sel_current_url`, `sel_page_source`,
  `sel_back`, `sel_forward`, `sel_refresh`.
- Find + elements: `sel_find_element`, `sel_find_child`, `sel_shadow_root`,
  `sel_element_id`, `sel_click`, `sel_clear`, `sel_send_keys`, `sel_text`,
  `sel_tag_name`, `sel_get_attribute`, `sel_aria_role`, `sel_accessible_name`,
  `sel_is_displayed`, `sel_is_enabled`, `sel_is_selected`.
- Raw commands + scripts: `sel_execute`, `sel_last_value`, `sel_execute_script`.
- Driver orchestration (the ported Selenium Manager): `sel_resolve_driver`,
  `sel_launch_driver`, `sel_ensure_driver`, `sel_process_url`,
  `sel_process_pid`, `sel_process_stop`.
- Pure engine helpers (no session): `sel_route`, `sel_error_code`,
  `sel_locator`.

## Layout

```
include/selenium.h    the public sel_* API (session, factories, find, scripts, driver orchestration)
src/selenium.c        the client: sel_* wrappers over the engine's aether_sel_embed_* C ABI
test/selenium_test.c  FFI + live test (no-browser facts always run; live Chrome/Firefox legs self-skip)
.objects.ae           aeb node → compiles src/selenium.c to the reusable `c_objects` object
.build.ae             aeb node → resolves + links the engine .so, bakes the rpath, builds the test
.tests.ae             aeb node → builds the engine and runs the FFI + live test
```
