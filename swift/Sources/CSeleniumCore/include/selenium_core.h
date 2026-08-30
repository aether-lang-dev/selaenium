/* selenium_core.h — the flat C ABI of the shared Aether Selenium engine.
 *
 * Declares the aether_sel_embed_* symbols (from selenium_core/embed.ae) so Swift
 * can call them DIRECTLY via a clang module map — no glue .c, no second copy of
 * the marshalling rules. Every string result is caller-owned; free it with
 * aether_sel_embed_free_string. This is the ONE FFI declaration the Swift binding
 * needs; the engine .so is linked/loaded via SELENIUM_CORE_LIB (see the loader). */
#ifndef SELENIUM_CORE_H
#define SELENIUM_CORE_H

void *aether_sel_embed_open(const char *base_url);
void  aether_sel_embed_close(void *h);
int   aether_sel_embed_execute(void *h, const char *name, const char *params_json);
char *aether_sel_embed_last_value(void *h);
int   aether_sel_embed_last_status(void *h);
int   aether_sel_embed_last_error_code(void *h);
char *aether_sel_embed_last_error(void *h);
char *aether_sel_embed_session_id(void *h);
char *aether_sel_embed_by_locator(const char *strategy, const char *value);
char *aether_sel_embed_route(const char *name);
int   aether_sel_embed_error_code(const char *w3c_error);
char *aether_sel_embed_free_string(char *s);

#endif /* SELENIUM_CORE_H */
