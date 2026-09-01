/*
 * selenium_nif.c — Erlang NIF over the Aether Selenium core's C ABI
 * (the aether_sel_embed_* symbols from core/embed.ae, linked from
 * libselenium_core.so).
 *
 * This is the thin FFI seam for the WHOLE BEAM family: the Elixir and Gleam
 * bindings load this SAME compiled module over the BEAM (no second NIF, no
 * copied C source), exactly as the JVM family layers over the one Java jar.
 * All protocol logic lives in the Aether engine, not here.
 *
 * The opaque session handle is a 64-bit integer (uintptr_t); 0 from `open`
 * means failure. String results come back as binaries; execute returns an int
 * (0 ok, W3C error code, or -1 transport). Every char* the ABI returns is
 * caller-owned and NUL-terminated; we copy it into an Erlang binary, then free
 * it via aether_sel_embed_free_string.
 */
#include <erl_nif.h>
#include <stdint.h>
#include <string.h>

#define UNUSED(x) ((void)(x))

/* ---- the engine's C ABI (libselenium_core.so) ---- */
extern void *aether_sel_embed_open(const char *base_url);
extern void  aether_sel_embed_close(void *h);
extern int   aether_sel_embed_execute(void *h, const char *name, const char *params_json);
extern char *aether_sel_embed_last_value(void *h);
extern int   aether_sel_embed_last_status(void *h);
extern int   aether_sel_embed_last_error_code(void *h);
extern char *aether_sel_embed_last_error(void *h);
extern char *aether_sel_embed_session_id(void *h);
extern char *aether_sel_embed_by_locator(const char *strategy, const char *value);
extern char *aether_sel_embed_route(const char *name);
extern char *aether_sel_embed_build_request(const char *name, const char *session_id, const char *params_json);
extern int   aether_sel_embed_error_code(const char *w3c_error);
extern void  aether_sel_embed_free_string(char *s);

/* ---- TLS config (per session handle; set before newSession) ---- */
extern void  aether_sel_embed_set_ca(void *h, const char *ca_path);
extern void  aether_sel_embed_set_insecure(void *h, int on);

/* ---- driver orchestration (opaque driver handle, independent of session) ---- */
extern char *aether_sel_embed_resolve_driver(const char *browser, const char *hint);
extern void *aether_sel_embed_launch_driver(const char *driver_path, int timeout_ms);
extern void *aether_sel_embed_ensure_driver(const char *browser, const char *hint, int timeout_ms);
extern char *aether_sel_embed_driver_url(void *dh);
extern int   aether_sel_embed_driver_pid(void *dh);
extern void  aether_sel_embed_stop_driver(void *dh);

/* ---- atom-backed commands (isDisplayed / getAttribute / relative locators) ----
 * Shared JS atoms run in-page by the engine. The int-returning verbs leave their
 * result in last_value (drained the normal way, exactly like execute); 0 ok, a
 * W3C error code, or -1 transport. atom_str_arg builds the quoted JSON string a
 * caller passes as an atom's extra_json argument; it returns a caller-owned
 * char* (freed via aether_sel_embed_free_string like every other string). */
extern int   aether_sel_embed_execute_atom(void *h, const char *atom, const char *elem_id, const char *extra_json);
extern int   aether_sel_embed_is_displayed(void *h, const char *elem_id);
extern int   aether_sel_embed_get_attribute(void *h, const char *elem_id, const char *name);
extern char *aether_sel_embed_atom_str_arg(const char *s);
extern int   aether_sel_embed_find_relative(void *h, const char *base_css, const char *filters_json);

/* ---- WebDriver-BiDi (over the session's webSocketUrl) ----
 * An opaque BiDi channel handle, independent of the W3C session handle. NULL
 * from bidi_open means failure. Every char* returned is caller-owned (freed
 * via aether_sel_embed_free_string, exactly like last_value/last_error). */
extern void *aether_sel_embed_bidi_open(const char *ws_url);
extern void  aether_sel_embed_bidi_close(void *h);
extern int   aether_sel_embed_bidi_send(void *h, int id, const char *method, const char *params_json);
extern int   aether_sel_embed_bidi_pump(void *h, int timeout_ms);
extern int   aether_sel_embed_bidi_fd(void *h);
extern char *aether_sel_embed_bidi_poll_reply(void *h, int id);
extern char *aether_sel_embed_bidi_poll_event(void *h);
extern int   aether_sel_embed_bidi_lost_events(void *h);
extern void  aether_sel_embed_bidi_cancel(void *h, int id);
extern char *aether_sel_embed_bidi_subscribe(void *h, int id, const char *events_csv, int timeout_ms);
extern char *aether_sel_embed_bidi_unsubscribe(void *h, int id, const char *events_csv, int timeout_ms);
extern char *aether_sel_embed_bidi_wait_event(void *h, const char *method, int timeout_ms);
extern char *aether_sel_embed_bidi_get_tree(void *h, int id, int timeout_ms);
extern char *aether_sel_embed_bidi_script_evaluate(void *h, int id, const char *expr, const char *ctx, int timeout_ms);
extern char *aether_sel_embed_bidi_navigate(void *h, int id, const char *ctx, const char *url, int timeout_ms);
extern char *aether_sel_embed_bidi_network_add_intercept(void *h, int id, const char *phases, const char *pattern, int timeout_ms);
extern char *aether_sel_embed_bidi_network_remove_intercept(void *h, int id, const char *icid, int timeout_ms);
extern char *aether_sel_embed_bidi_network_continue_request(void *h, int id, const char *rid, int timeout_ms);
extern char *aether_sel_embed_bidi_network_fail_request(void *h, int id, const char *rid, int timeout_ms);
extern char *aether_sel_embed_bidi_network_provide_response(void *h, int id, const char *rid, int status, const char *ct, const char *body, int timeout_ms);
extern char *aether_sel_embed_bidi_network_continue_with_auth(void *h, int id, const char *rid, const char *user, const char *pass, int timeout_ms);
extern char *aether_sel_embed_bidi_network_set_cache_behavior(void *h, int id, const char *behavior, int timeout_ms);

/* ---- helpers ---- */

/* Erlang binary/iolist term -> malloc'd NUL-terminated C string (enif_alloc). */
static char *term_to_cstr(ErlNifEnv *env, ERL_NIF_TERM term)
{
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, term, &bin)) {
        if (!enif_inspect_iolist_as_binary(env, term, &bin)) {
            return NULL;
        }
    }
    char *out = enif_alloc(bin.size + 1);
    if (!out) return NULL;
    memcpy(out, bin.data, bin.size);
    out[bin.size] = '\0';
    return out;
}

/* NUL-terminated C string -> Erlang binary; frees the source via the engine's
 * allocator. NULL yields an empty binary. */
static ERL_NIF_TERM take_cstr(ErlNifEnv *env, char *s)
{
    if (s == NULL) {
        ERL_NIF_TERM empty;
        enif_make_new_binary(env, 0, &empty);
        return empty;
    }
    size_t len = strlen(s);
    ERL_NIF_TERM bin;
    unsigned char *buf = enif_make_new_binary(env, len, &bin);
    memcpy(buf, s, len);
    aether_sel_embed_free_string(s);
    return bin;
}

static int get_handle(ErlNifEnv *env, ERL_NIF_TERM term, void **out)
{
    ErlNifUInt64 v;
    if (!enif_get_uint64(env, term, &v)) return 0;
    *out = (void *)(uintptr_t)v;
    return 1;
}

static ERL_NIF_TERM make_handle(ErlNifEnv *env, void *p)
{
    return enif_make_uint64(env, (ErlNifUInt64)(uintptr_t)p);
}

/* ---- lifecycle ---- */

static ERL_NIF_TERM nif_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *url = term_to_cstr(env, argv[0]);
    if (!url) return enif_make_badarg(env);
    void *h = aether_sel_embed_open(url);
    enif_free(url);
    return make_handle(env, h);
}

static ERL_NIF_TERM nif_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    aether_sel_embed_close(h);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_execute(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *name = term_to_cstr(env, argv[1]);
    char *params = term_to_cstr(env, argv[2]);
    if (!name || !params) {
        if (name) enif_free(name);
        if (params) enif_free(params);
        return enif_make_badarg(env);
    }
    int rc = aether_sel_embed_execute(h, name, params);
    enif_free(name);
    enif_free(params);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM nif_last_value(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_last_value(h));
}

static ERL_NIF_TERM nif_last_status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_last_status(h));
}

static ERL_NIF_TERM nif_last_error_code(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_last_error_code(h));
}

static ERL_NIF_TERM nif_last_error(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_last_error(h));
}

static ERL_NIF_TERM nif_session_id(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_session_id(h));
}

/* ---- pure helpers ---- */

static ERL_NIF_TERM nif_by_locator(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *strategy = term_to_cstr(env, argv[0]);
    char *value = term_to_cstr(env, argv[1]);
    if (!strategy || !value) {
        if (strategy) enif_free(strategy);
        if (value) enif_free(value);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_by_locator(strategy, value));
    enif_free(strategy);
    enif_free(value);
    return r;
}

/* ---- TLS config + driver orchestration ---- */

static ERL_NIF_TERM nif_set_ca(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *ca = term_to_cstr(env, argv[1]);
    if (!ca) return enif_make_badarg(env);
    aether_sel_embed_set_ca(h, ca);
    enif_free(ca);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_set_insecure(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int on;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &on)) return enif_make_badarg(env);
    aether_sel_embed_set_insecure(h, on);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_resolve_driver(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *browser = term_to_cstr(env, argv[0]);
    char *hint = term_to_cstr(env, argv[1]);
    if (!browser || !hint) {
        if (browser) enif_free(browser);
        if (hint) enif_free(hint);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_resolve_driver(browser, hint));
    enif_free(browser);
    enif_free(hint);
    return r;
}

static ERL_NIF_TERM nif_launch_driver(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *path = term_to_cstr(env, argv[0]);
    int timeout_ms;
    if (!path) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &timeout_ms)) { enif_free(path); return enif_make_badarg(env); }
    void *dh = aether_sel_embed_launch_driver(path, timeout_ms);
    enif_free(path);
    return make_handle(env, dh);
}

static ERL_NIF_TERM nif_ensure_driver(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *browser = term_to_cstr(env, argv[0]);
    char *hint = term_to_cstr(env, argv[1]);
    int timeout_ms;
    if (!browser || !hint) {
        if (browser) enif_free(browser);
        if (hint) enif_free(hint);
        return enif_make_badarg(env);
    }
    if (!enif_get_int(env, argv[2], &timeout_ms)) {
        enif_free(browser); enif_free(hint);
        return enif_make_badarg(env);
    }
    void *dh = aether_sel_embed_ensure_driver(browser, hint, timeout_ms);
    enif_free(browser);
    enif_free(hint);
    return make_handle(env, dh);
}

static ERL_NIF_TERM nif_driver_url(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *dh;
    if (!get_handle(env, argv[0], &dh)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_driver_url(dh));
}

static ERL_NIF_TERM nif_driver_pid(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *dh;
    if (!get_handle(env, argv[0], &dh)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_driver_pid(dh));
}

static ERL_NIF_TERM nif_stop_driver(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *dh;
    if (!get_handle(env, argv[0], &dh)) return enif_make_badarg(env);
    aether_sel_embed_stop_driver(dh);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_route(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *name = term_to_cstr(env, argv[0]);
    if (!name) return enif_make_badarg(env);
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_route(name));
    enif_free(name);
    return r;
}

static ERL_NIF_TERM nif_error_code(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *e = term_to_cstr(env, argv[0]);
    if (!e) return enif_make_badarg(env);
    int r = aether_sel_embed_error_code(e);
    enif_free(e);
    return enif_make_int(env, r);
}

/* ---- WebDriver-BiDi ----
 * The BiDi channel handle is a 64-bit integer, wrapped exactly like the session
 * handle (make_handle/get_handle). Command ids are supplied by the caller. */

static ERL_NIF_TERM nif_bidi_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *ws_url = term_to_cstr(env, argv[0]);
    if (!ws_url) return enif_make_badarg(env);
    void *h = aether_sel_embed_bidi_open(ws_url);
    enif_free(ws_url);
    return make_handle(env, h);
}

static ERL_NIF_TERM nif_bidi_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    aether_sel_embed_bidi_close(h);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_bidi_send(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *method = term_to_cstr(env, argv[2]);
    char *params = term_to_cstr(env, argv[3]);
    if (!method || !params) {
        if (method) enif_free(method);
        if (params) enif_free(params);
        return enif_make_badarg(env);
    }
    int rc = aether_sel_embed_bidi_send(h, id, method, params);
    enif_free(method);
    enif_free(params);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM nif_bidi_pump(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &timeout_ms)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_bidi_pump(h, timeout_ms));
}

static ERL_NIF_TERM nif_bidi_fd(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_bidi_fd(h));
}

static ERL_NIF_TERM nif_bidi_poll_reply(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_bidi_poll_reply(h, id));
}

static ERL_NIF_TERM nif_bidi_poll_event(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_bidi_poll_event(h));
}

static ERL_NIF_TERM nif_bidi_lost_events(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    return enif_make_int(env, aether_sel_embed_bidi_lost_events(h));
}

static ERL_NIF_TERM nif_bidi_cancel(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    aether_sel_embed_bidi_cancel(h, id);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_bidi_subscribe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *events = term_to_cstr(env, argv[2]);
    if (!events) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &timeout_ms)) {
        enif_free(events);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_subscribe(h, id, events, timeout_ms));
    enif_free(events);
    return r;
}

static ERL_NIF_TERM nif_bidi_unsubscribe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *events = term_to_cstr(env, argv[2]);
    if (!events) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &timeout_ms)) {
        enif_free(events);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_unsubscribe(h, id, events, timeout_ms));
    enif_free(events);
    return r;
}

static ERL_NIF_TERM nif_bidi_wait_event(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *method = term_to_cstr(env, argv[1]);
    if (!method) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[2], &timeout_ms)) {
        enif_free(method);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_wait_event(h, method, timeout_ms));
    enif_free(method);
    return r;
}

static ERL_NIF_TERM nif_bidi_get_tree(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[2], &timeout_ms)) return enif_make_badarg(env);
    return take_cstr(env, aether_sel_embed_bidi_get_tree(h, id, timeout_ms));
}

static ERL_NIF_TERM nif_bidi_script_evaluate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *expr = term_to_cstr(env, argv[2]);
    if (!expr) return enif_make_badarg(env);
    char *ctx = term_to_cstr(env, argv[3]);
    if (!ctx) { enif_free(expr); return enif_make_badarg(env); }
    if (!enif_get_int(env, argv[4], &timeout_ms)) {
        enif_free(expr); enif_free(ctx);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_script_evaluate(h, id, expr, ctx, timeout_ms));
    enif_free(expr);
    enif_free(ctx);
    return r;
}

static ERL_NIF_TERM nif_bidi_navigate(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *ctx = term_to_cstr(env, argv[2]);
    if (!ctx) return enif_make_badarg(env);
    char *url = term_to_cstr(env, argv[3]);
    if (!url) { enif_free(ctx); return enif_make_badarg(env); }
    if (!enif_get_int(env, argv[4], &timeout_ms)) {
        enif_free(ctx); enif_free(url);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_navigate(h, id, ctx, url, timeout_ms));
    enif_free(ctx);
    enif_free(url);
    return r;
}

static ERL_NIF_TERM nif_bidi_network_add_intercept(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *phases = term_to_cstr(env, argv[2]);
    if (!phases) return enif_make_badarg(env);
    char *pattern = term_to_cstr(env, argv[3]);
    if (!pattern) { enif_free(phases); return enif_make_badarg(env); }
    if (!enif_get_int(env, argv[4], &timeout_ms)) {
        enif_free(phases); enif_free(pattern);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_network_add_intercept(h, id, phases, pattern, timeout_ms));
    enif_free(phases);
    enif_free(pattern);
    return r;
}

/* remove_intercept / continue_request / fail_request all share the
   (handle, id, string, timeout) shape. */
static ERL_NIF_TERM nif_bidi_net_str(ErlNifEnv *env, const ERL_NIF_TERM argv[],
                                     char *(*fn)(void *, int, const char *, int))
{
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *s = term_to_cstr(env, argv[2]);
    if (!s) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &timeout_ms)) { enif_free(s); return enif_make_badarg(env); }
    ERL_NIF_TERM r = take_cstr(env, fn(h, id, s, timeout_ms));
    enif_free(s);
    return r;
}
static ERL_NIF_TERM nif_bidi_network_remove_intercept(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{ UNUSED(argc); return nif_bidi_net_str(env, argv, aether_sel_embed_bidi_network_remove_intercept); }
static ERL_NIF_TERM nif_bidi_network_continue_request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{ UNUSED(argc); return nif_bidi_net_str(env, argv, aether_sel_embed_bidi_network_continue_request); }
static ERL_NIF_TERM nif_bidi_network_fail_request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{ UNUSED(argc); return nif_bidi_net_str(env, argv, aether_sel_embed_bidi_network_fail_request); }

static ERL_NIF_TERM nif_bidi_network_provide_response(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, status, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *rid = term_to_cstr(env, argv[2]);
    if (!rid) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &status)) { enif_free(rid); return enif_make_badarg(env); }
    char *ct = term_to_cstr(env, argv[4]);
    if (!ct) { enif_free(rid); return enif_make_badarg(env); }
    char *body = term_to_cstr(env, argv[5]);
    if (!body) { enif_free(rid); enif_free(ct); return enif_make_badarg(env); }
    if (!enif_get_int(env, argv[6], &timeout_ms)) {
        enif_free(rid); enif_free(ct); enif_free(body);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_network_provide_response(h, id, rid, status, ct, body, timeout_ms));
    enif_free(rid);
    enif_free(ct);
    enif_free(body);
    return r;
}

static ERL_NIF_TERM nif_bidi_network_continue_with_auth(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    int id, timeout_ms;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &id)) return enif_make_badarg(env);
    char *rid = term_to_cstr(env, argv[2]);
    if (!rid) return enif_make_badarg(env);
    char *user = term_to_cstr(env, argv[3]);
    if (!user) { enif_free(rid); return enif_make_badarg(env); }
    char *pass = term_to_cstr(env, argv[4]);
    if (!pass) { enif_free(rid); enif_free(user); return enif_make_badarg(env); }
    if (!enif_get_int(env, argv[5], &timeout_ms)) {
        enif_free(rid); enif_free(user); enif_free(pass);
        return enif_make_badarg(env);
    }
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_bidi_network_continue_with_auth(h, id, rid, user, pass, timeout_ms));
    enif_free(rid);
    enif_free(user);
    enif_free(pass);
    return r;
}

static ERL_NIF_TERM nif_bidi_network_set_cache_behavior(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{ UNUSED(argc); return nif_bidi_net_str(env, argv, aether_sel_embed_bidi_network_set_cache_behavior); }

/* ---- atom-backed commands ----
 * The int-returning verbs leave the result in last_value; the caller reads it
 * with last_value/1 (via selenium.erl's atom_result), just like execute. */

static ERL_NIF_TERM nif_execute_atom(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *atom = term_to_cstr(env, argv[1]);
    char *elem_id = term_to_cstr(env, argv[2]);
    char *extra = term_to_cstr(env, argv[3]);
    if (!atom || !elem_id || !extra) {
        if (atom) enif_free(atom);
        if (elem_id) enif_free(elem_id);
        if (extra) enif_free(extra);
        return enif_make_badarg(env);
    }
    int rc = aether_sel_embed_execute_atom(h, atom, elem_id, extra);
    enif_free(atom);
    enif_free(elem_id);
    enif_free(extra);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM nif_is_displayed(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *elem_id = term_to_cstr(env, argv[1]);
    if (!elem_id) return enif_make_badarg(env);
    int rc = aether_sel_embed_is_displayed(h, elem_id);
    enif_free(elem_id);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM nif_get_attribute(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *elem_id = term_to_cstr(env, argv[1]);
    char *name = term_to_cstr(env, argv[2]);
    if (!elem_id || !name) {
        if (elem_id) enif_free(elem_id);
        if (name) enif_free(name);
        return enif_make_badarg(env);
    }
    int rc = aether_sel_embed_get_attribute(h, elem_id, name);
    enif_free(elem_id);
    enif_free(name);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM nif_atom_str_arg(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    char *s = term_to_cstr(env, argv[0]);
    if (!s) return enif_make_badarg(env);
    ERL_NIF_TERM r = take_cstr(env, aether_sel_embed_atom_str_arg(s));
    enif_free(s);
    return r;
}

static ERL_NIF_TERM nif_find_relative(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    UNUSED(argc);
    void *h;
    if (!get_handle(env, argv[0], &h)) return enif_make_badarg(env);
    char *base_css = term_to_cstr(env, argv[1]);
    char *filters = term_to_cstr(env, argv[2]);
    if (!base_css || !filters) {
        if (base_css) enif_free(base_css);
        if (filters) enif_free(filters);
        return enif_make_badarg(env);
    }
    int rc = aether_sel_embed_find_relative(h, base_css, filters);
    enif_free(base_css);
    enif_free(filters);
    return enif_make_int(env, rc);
}

static ErlNifFunc nif_funcs[] = {
    {"open",            1, nif_open,            0},
    {"close",           1, nif_close,           0},
    {"execute",         3, nif_execute,         0},
    {"last_value",      1, nif_last_value,      0},
    {"last_status",     1, nif_last_status,     0},
    {"last_error_code", 1, nif_last_error_code, 0},
    {"last_error",      1, nif_last_error,      0},
    {"session_id",      1, nif_session_id,      0},
    {"by_locator",      2, nif_by_locator,      0},
    {"set_ca",          2, nif_set_ca,          0},
    {"set_insecure",    2, nif_set_insecure,    0},
    {"resolve_driver",  2, nif_resolve_driver,  0},
    {"launch_driver",   2, nif_launch_driver,   0},
    {"ensure_driver",   3, nif_ensure_driver,   0},
    {"driver_url",      1, nif_driver_url,      0},
    {"driver_pid",      1, nif_driver_pid,      0},
    {"stop_driver",     1, nif_stop_driver,     0},
    {"route",           1, nif_route,           0},
    {"error_code",      1, nif_error_code,      0},
    {"bidi_open",        1, nif_bidi_open,        0},
    {"bidi_close",       1, nif_bidi_close,       0},
    {"bidi_send",        4, nif_bidi_send,        0},
    {"bidi_pump",        2, nif_bidi_pump,        0},
    {"bidi_fd",          1, nif_bidi_fd,          0},
    {"bidi_poll_reply",  2, nif_bidi_poll_reply,  0},
    {"bidi_poll_event",  1, nif_bidi_poll_event,  0},
    {"bidi_lost_events", 1, nif_bidi_lost_events, 0},
    {"bidi_cancel",      2, nif_bidi_cancel,      0},
    {"bidi_subscribe",   4, nif_bidi_subscribe,   0},
    {"bidi_unsubscribe", 4, nif_bidi_unsubscribe, 0},
    {"bidi_wait_event",  3, nif_bidi_wait_event,  0},
    {"bidi_get_tree",    3, nif_bidi_get_tree,    0},
    {"bidi_script_evaluate", 5, nif_bidi_script_evaluate, 0},
    {"bidi_navigate",    5, nif_bidi_navigate,    0},
    {"bidi_network_add_intercept",    5, nif_bidi_network_add_intercept,    0},
    {"bidi_network_remove_intercept", 4, nif_bidi_network_remove_intercept, 0},
    {"bidi_network_continue_request", 4, nif_bidi_network_continue_request, 0},
    {"bidi_network_fail_request",     4, nif_bidi_network_fail_request,     0},
    {"bidi_network_provide_response", 7, nif_bidi_network_provide_response, 0},
    {"bidi_network_continue_with_auth", 6, nif_bidi_network_continue_with_auth, 0},
    {"bidi_network_set_cache_behavior", 4, nif_bidi_network_set_cache_behavior, 0},
    {"execute_atom",   4, nif_execute_atom,   0},
    {"is_displayed",   2, nif_is_displayed,   0},
    {"get_attribute",  3, nif_get_attribute,  0},
    {"atom_str_arg",   1, nif_atom_str_arg,   0},
    {"find_relative",  3, nif_find_relative,  0},
};

ERL_NIF_INIT(selenium_nif, nif_funcs, NULL, NULL, NULL, NULL)
