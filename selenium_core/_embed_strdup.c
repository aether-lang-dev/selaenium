/* core/_embed_strdup.c — the embed ABI's caller-owned-string bridge.
 *
 * The Selenium engine is PURE AETHER (core/selenium_core.ae). This is the ONE
 * irreducible scrap of C: sel_embed_dup() hands the FFI host a plain malloc'd,
 * NUL-terminated C string it owns and later frees via sel_embed_free().
 * Aether's stdlib has no "malloc a C string" primitive (std.mem is
 * access-only, no allocation), and the language bindings free returned
 * pointers with C free() — so this can't be Aether.
 *
 * Linked into the .so via `--extra` from core/.build.ae. embed.ae declares
 * these extern. The pure-Aether probes in core_tests/ import selenium_core,
 * never the embed ABI, so they need neither this file nor --extra.
 */
#include <stdlib.h>
#include <string.h>

char* sel_embed_dup(const char* s) {
    if (!s) s = "";
    size_t n = strlen(s) + 1;
    char* d = (char*)malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

void sel_embed_free(char* s) {
    free(s);
}
