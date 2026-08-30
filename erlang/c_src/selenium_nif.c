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
};

ERL_NIF_INIT(selenium_nif, nif_funcs, NULL, NULL, NULL, NULL)
