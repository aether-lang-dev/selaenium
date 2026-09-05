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

/* ---- TLS trust config (call before the first execute) ---- */
void  aether_sel_embed_set_ca(void *h, const char *ca_path);
void  aether_sel_embed_set_insecure(void *h, int on);

/* ---- atom-backed element commands (no direct W3C route) ----
 * Return 0 / W3C error code / -1; drain the result via last_value. */
int   aether_sel_embed_execute_atom(void *h, const char *atom_name, const char *elem_id, const char *extra_json);
int   aether_sel_embed_is_displayed(void *h, const char *elem_id);
int   aether_sel_embed_get_attribute(void *h, const char *elem_id, const char *name);
char *aether_sel_embed_atom_str_arg(const char *s);

/* ---- relative locators (findElementsRelative atom) ---- */
int   aether_sel_embed_find_relative(void *h, const char *base_sel, const char *filters_json);

/* ---- driver-process orchestration ---- */
char *aether_sel_embed_resolve_driver(const char *browser, const char *hint);
void *aether_sel_embed_launch_driver(const char *driver_path, int timeout_ms);
char *aether_sel_embed_browser_binary(const char *browser, const char *hint);
void *aether_sel_embed_ensure_driver(const char *browser, const char *hint, int timeout_ms);
char *aether_sel_embed_driver_url(void *dh);
int   aether_sel_embed_driver_pid(void *dh);
void  aether_sel_embed_stop_driver(void *dh);

/* ---- WebDriver-BiDi (central demux, non-blocking poll) ----
 * Channel handle is independent of the W3C session handle. Strings caller-owned. */
void *aether_sel_embed_bidi_open(const char *ws_url);
void  aether_sel_embed_bidi_close(void *h);
int   aether_sel_embed_bidi_send(void *h, int id, const char *method, const char *params_json);
int   aether_sel_embed_bidi_pump(void *h, int timeout_ms);
int   aether_sel_embed_bidi_fd(void *h);
char *aether_sel_embed_bidi_poll_reply(void *h, int id);
char *aether_sel_embed_bidi_poll_event(void *h);
int   aether_sel_embed_bidi_lost_events(void *h);
void  aether_sel_embed_bidi_cancel(void *h, int id);
char *aether_sel_embed_bidi_subscribe(void *h, int id, const char *events_csv, int timeout_ms);
char *aether_sel_embed_bidi_unsubscribe(void *h, int id, const char *events_csv, int timeout_ms);
char *aether_sel_embed_bidi_wait_event(void *h, const char *method, int timeout_ms);
char *aether_sel_embed_bidi_get_tree(void *h, int id, int timeout_ms);
char *aether_sel_embed_bidi_script_evaluate(void *h, int id, const char *expression, const char *context_id, int timeout_ms);
char *aether_sel_embed_bidi_navigate(void *h, int id, const char *context_id, const char *url, int timeout_ms);

/* ---- BiDi network interception ---- */
char *aether_sel_embed_bidi_network_add_intercept(void *h, int id, const char *phases_csv, const char *url_pattern, int timeout_ms);
char *aether_sel_embed_bidi_network_remove_intercept(void *h, int id, const char *intercept_id, int timeout_ms);
char *aether_sel_embed_bidi_network_continue_request(void *h, int id, const char *request_id, int timeout_ms);
char *aether_sel_embed_bidi_network_fail_request(void *h, int id, const char *request_id, int timeout_ms);
char *aether_sel_embed_bidi_network_provide_response(void *h, int id, const char *request_id, int status, const char *content_type, const char *body, int timeout_ms);
char *aether_sel_embed_bidi_network_continue_with_auth(void *h, int id, const char *request_id, const char *username, const char *password, int timeout_ms);
char *aether_sel_embed_bidi_network_set_cache_behavior(void *h, int id, const char *behavior, int timeout_ms);

#endif /* SELENIUM_CORE_H */
