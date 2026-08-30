/* lua/src/selenium_core.c — the Lua 5.4 C extension over the Selenium core's
 * C ABI (core/embed.ae, aether_sel_embed_* from libselenium_core.so).
 *
 * This file is the ONLY place in the Lua binding that knows about the C ABI.
 * Everything above it (src/selenium_core.lua) is idiomatic Lua. No protocol
 * logic lives here — the engine is core/selenium_core.ae, shared by every
 * language binding.
 *
 * Lua has no FFI in its standard distribution (LuaJIT's ffi is not Lua 5.4), so
 * unlike the ctypes/Fiddle/dart:ffi bindings this is a real C extension. It
 * dlopen's the engine (rather than linking it), so the same SELENIUM_CORE_LIB
 * resolution order every other binding uses applies and one .so serves them all.
 *
 * Build: cc -O2 -fPIC -shared -I/usr/include/lua5.4 src/selenium_core.c \
 *          -o selenium_core_native.so -ldl
 *
 * Ownership: every char* the ABI returns is caller-owned and must go back to
 * aether_sel_embed_free_string. push_owned() is the only place a returned
 * string becomes a Lua string, and it always frees.
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

/* ---- the ABI, dlsym'd once ---- */
typedef void* (*fn_open)(const char*);
typedef void  (*fn_close)(void*);
typedef int   (*fn_execute)(void*, const char*, const char*);
typedef char* (*fn_hstr)(void*);       /* handle -> owned string */
typedef int   (*fn_hint)(void*);       /* handle -> int */
typedef char* (*fn_by)(const char*, const char*);
typedef char* (*fn_str)(const char*);  /* cstr -> owned string */
typedef int   (*fn_strint)(const char*);
typedef void  (*fn_free)(char*);

/* ---- WebDriver-BiDi ABI (over the session's negotiated webSocketUrl) ---- */
typedef void* (*fn_bidi_open)(const char*);              /* ws_url -> handle */
typedef void  (*fn_bidi_close)(void*);
typedef int   (*fn_bidi_send)(void*, int, const char*, const char*);
typedef int   (*fn_bidi_pump)(void*, int);
typedef int   (*fn_bidi_fd)(void*);
typedef char* (*fn_bidi_poll_reply)(void*, int);         /* -> owned string */
typedef char* (*fn_bidi_poll_event)(void*);              /* -> owned string */
typedef int   (*fn_bidi_lost_events)(void*);
typedef void  (*fn_bidi_cancel)(void*, int);
typedef char* (*fn_bidi_sub)(void*, int, const char*, int);   /* -> owned string */
typedef char* (*fn_bidi_wait)(void*, const char*, int);       /* -> owned string */

static struct {
    void* handle;
    char  path[4096];
    fn_open    open;
    fn_close   close;
    fn_execute execute;
    fn_hstr    last_value;
    fn_hint    last_status;
    fn_hint    last_error_code;
    fn_hstr    last_error;
    fn_hstr    session_id;
    fn_by      by_locator;
    fn_str     route;
    fn_strint  error_code;
    fn_free    free_string;
    /* ---- WebDriver-BiDi ---- */
    fn_bidi_open        bidi_open;
    fn_bidi_close       bidi_close;
    fn_bidi_send        bidi_send;
    fn_bidi_pump        bidi_pump;
    fn_bidi_fd          bidi_fd;
    fn_bidi_poll_reply  bidi_poll_reply;
    fn_bidi_poll_event  bidi_poll_event;
    fn_bidi_lost_events bidi_lost_events;
    fn_bidi_cancel      bidi_cancel;
    fn_bidi_sub         bidi_subscribe;
    fn_bidi_sub         bidi_unsubscribe;
    fn_bidi_wait        bidi_wait_event;
} ENGINE;

static int load_symbols(lua_State* L, void* lib, const char* path) {
#define SYM(field, name)                                                     \
    do {                                                                     \
        *(void**)(&ENGINE.field) = dlsym(lib, name);                         \
        if (!ENGINE.field) {                                                 \
            dlclose(lib);                                                    \
            memset(&ENGINE, 0, sizeof(ENGINE));                              \
            return luaL_error(L, "selenium_core: engine at '%s' is missing " \
                                 "symbol %s", path, name);                   \
        }                                                                    \
    } while (0)

    SYM(open,            "aether_sel_embed_open");
    SYM(close,           "aether_sel_embed_close");
    SYM(execute,         "aether_sel_embed_execute");
    SYM(last_value,      "aether_sel_embed_last_value");
    SYM(last_status,     "aether_sel_embed_last_status");
    SYM(last_error_code, "aether_sel_embed_last_error_code");
    SYM(last_error,      "aether_sel_embed_last_error");
    SYM(session_id,      "aether_sel_embed_session_id");
    SYM(by_locator,      "aether_sel_embed_by_locator");
    SYM(route,           "aether_sel_embed_route");
    SYM(error_code,      "aether_sel_embed_error_code");
    SYM(free_string,     "aether_sel_embed_free_string");

    SYM(bidi_open,        "aether_sel_embed_bidi_open");
    SYM(bidi_close,       "aether_sel_embed_bidi_close");
    SYM(bidi_send,        "aether_sel_embed_bidi_send");
    SYM(bidi_pump,        "aether_sel_embed_bidi_pump");
    SYM(bidi_fd,          "aether_sel_embed_bidi_fd");
    SYM(bidi_poll_reply,  "aether_sel_embed_bidi_poll_reply");
    SYM(bidi_poll_event,  "aether_sel_embed_bidi_poll_event");
    SYM(bidi_lost_events, "aether_sel_embed_bidi_lost_events");
    SYM(bidi_cancel,      "aether_sel_embed_bidi_cancel");
    SYM(bidi_subscribe,   "aether_sel_embed_bidi_subscribe");
    SYM(bidi_unsubscribe, "aether_sel_embed_bidi_unsubscribe");
    SYM(bidi_wait_event,  "aether_sel_embed_bidi_wait_event");
#undef SYM

    ENGINE.handle = lib;
    snprintf(ENGINE.path, sizeof(ENGINE.path), "%s", path);
    return 0;
}

static int engine_load(lua_State* L, const char* explicit_path) {
    if (ENGINE.handle && !explicit_path) return 0;

    const char* candidates[8];
    int n = 0;
    if (explicit_path && *explicit_path) {
        candidates[n++] = explicit_path;
    } else {
        const char* env = getenv("SELENIUM_CORE_LIB");
        if (env && *env) candidates[n++] = env;
        candidates[n++] = "native/libselenium_core.so";
        candidates[n++] = "../core/native/libselenium_core.so";
        candidates[n++] = "libselenium_core.so";
    }

    const char* last_err = "(none)";
    for (int i = 0; i < n; i++) {
        void* lib = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
        if (lib) return load_symbols(L, lib, candidates[i]);
        const char* e = dlerror();
        if (e) last_err = e;
    }
    return luaL_error(L, "selenium_core: could not load libselenium_core.so. "
        "Set SELENIUM_CORE_LIB to its absolute path. Last dlerror: %s", last_err);
}

/* ---- helpers ---- */

/* Push an ABI-returned owned string as a Lua string, then free it. */
static void push_owned(lua_State* L, char* s) {
    if (!s) { lua_pushliteral(L, ""); return; }
    lua_pushstring(L, s);
    ENGINE.free_string(s);
}

/* A session handle is a light userdata (the void* directly). */
static void* check_handle(lua_State* L, int idx) {
    luaL_checktype(L, idx, LUA_TLIGHTUSERDATA);
    return lua_touserdata(L, idx);
}

/* ---- Lua-callable functions ---- */

static int l_open(lua_State* L) {
    engine_load(L, NULL);
    const char* url = luaL_checkstring(L, 1);
    void* h = ENGINE.open(url);
    if (!h) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, h);
    return 1;
}

static int l_close(lua_State* L) {
    void* h = check_handle(L, 1);
    ENGINE.close(h);
    return 0;
}

static int l_execute(lua_State* L) {
    void* h = check_handle(L, 1);
    const char* name = luaL_checkstring(L, 2);
    const char* params = luaL_checkstring(L, 3);
    lua_pushinteger(L, ENGINE.execute(h, name, params));
    return 1;
}

static int l_last_value(lua_State* L) {
    push_owned(L, ENGINE.last_value(check_handle(L, 1)));
    return 1;
}

static int l_last_status(lua_State* L) {
    lua_pushinteger(L, ENGINE.last_status(check_handle(L, 1)));
    return 1;
}

static int l_last_error_code(lua_State* L) {
    lua_pushinteger(L, ENGINE.last_error_code(check_handle(L, 1)));
    return 1;
}

static int l_last_error(lua_State* L) {
    push_owned(L, ENGINE.last_error(check_handle(L, 1)));
    return 1;
}

static int l_session_id(lua_State* L) {
    push_owned(L, ENGINE.session_id(check_handle(L, 1)));
    return 1;
}

static int l_by_locator(lua_State* L) {
    engine_load(L, NULL);
    const char* strategy = luaL_checkstring(L, 1);
    const char* value = luaL_checkstring(L, 2);
    push_owned(L, ENGINE.by_locator(strategy, value));
    return 1;
}

static int l_route(lua_State* L) {
    engine_load(L, NULL);
    push_owned(L, ENGINE.route(luaL_checkstring(L, 1)));
    return 1;
}

static int l_error_code(lua_State* L) {
    engine_load(L, NULL);
    lua_pushinteger(L, ENGINE.error_code(luaL_checkstring(L, 1)));
    return 1;
}

static int l_configure(lua_State* L) {
    /* Pin an explicit .so path (loads it now). */
    const char* path = luaL_checkstring(L, 1);
    engine_load(L, path);
    return 0;
}

/* ---- WebDriver-BiDi ---- */
/* A BiDi channel handle is a light userdata (the void* directly), independent
 * of the W3C session handle. */

static int l_bidi_open(lua_State* L) {
    const char* ws_url = luaL_checkstring(L, 1);
    void* h = ENGINE.bidi_open(ws_url);
    if (!h) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, h);
    return 1;
}

static int l_bidi_close(lua_State* L) {
    ENGINE.bidi_close(check_handle(L, 1));
    return 0;
}

static int l_bidi_send(lua_State* L) {
    void* h = check_handle(L, 1);
    int id = (int)luaL_checkinteger(L, 2);
    const char* method = luaL_checkstring(L, 3);
    const char* params = luaL_checkstring(L, 4);
    lua_pushinteger(L, ENGINE.bidi_send(h, id, method, params));
    return 1;
}

static int l_bidi_pump(lua_State* L) {
    void* h = check_handle(L, 1);
    int timeout_ms = (int)luaL_checkinteger(L, 2);
    lua_pushinteger(L, ENGINE.bidi_pump(h, timeout_ms));
    return 1;
}

static int l_bidi_fd(lua_State* L) {
    lua_pushinteger(L, ENGINE.bidi_fd(check_handle(L, 1)));
    return 1;
}

static int l_bidi_poll_reply(lua_State* L) {
    void* h = check_handle(L, 1);
    int id = (int)luaL_checkinteger(L, 2);
    push_owned(L, ENGINE.bidi_poll_reply(h, id));
    return 1;
}

static int l_bidi_poll_event(lua_State* L) {
    push_owned(L, ENGINE.bidi_poll_event(check_handle(L, 1)));
    return 1;
}

static int l_bidi_lost_events(lua_State* L) {
    lua_pushinteger(L, ENGINE.bidi_lost_events(check_handle(L, 1)));
    return 1;
}

static int l_bidi_cancel(lua_State* L) {
    void* h = check_handle(L, 1);
    int id = (int)luaL_checkinteger(L, 2);
    ENGINE.bidi_cancel(h, id);
    return 0;
}

static int l_bidi_subscribe(lua_State* L) {
    void* h = check_handle(L, 1);
    int id = (int)luaL_checkinteger(L, 2);
    const char* events = luaL_checkstring(L, 3);
    int timeout_ms = (int)luaL_checkinteger(L, 4);
    push_owned(L, ENGINE.bidi_subscribe(h, id, events, timeout_ms));
    return 1;
}

static int l_bidi_unsubscribe(lua_State* L) {
    void* h = check_handle(L, 1);
    int id = (int)luaL_checkinteger(L, 2);
    const char* events = luaL_checkstring(L, 3);
    int timeout_ms = (int)luaL_checkinteger(L, 4);
    push_owned(L, ENGINE.bidi_unsubscribe(h, id, events, timeout_ms));
    return 1;
}

static int l_bidi_wait_event(lua_State* L) {
    void* h = check_handle(L, 1);
    const char* method = luaL_checkstring(L, 2);
    int timeout_ms = (int)luaL_checkinteger(L, 3);
    push_owned(L, ENGINE.bidi_wait_event(h, method, timeout_ms));
    return 1;
}

static const luaL_Reg MODULE[] = {
    {"open",            l_open},
    {"close",           l_close},
    {"execute",         l_execute},
    {"last_value",      l_last_value},
    {"last_status",     l_last_status},
    {"last_error_code", l_last_error_code},
    {"last_error",      l_last_error},
    {"session_id",      l_session_id},
    {"by_locator",      l_by_locator},
    {"route",           l_route},
    {"error_code",      l_error_code},
    {"configure",       l_configure},
    {"bidi_open",         l_bidi_open},
    {"bidi_close",        l_bidi_close},
    {"bidi_send",         l_bidi_send},
    {"bidi_pump",         l_bidi_pump},
    {"bidi_fd",           l_bidi_fd},
    {"bidi_poll_reply",   l_bidi_poll_reply},
    {"bidi_poll_event",   l_bidi_poll_event},
    {"bidi_lost_events",  l_bidi_lost_events},
    {"bidi_cancel",       l_bidi_cancel},
    {"bidi_subscribe",    l_bidi_subscribe},
    {"bidi_unsubscribe",  l_bidi_unsubscribe},
    {"bidi_wait_event",   l_bidi_wait_event},
    {NULL, NULL},
};

int luaopen_selenium_core_native(lua_State* L) {
    luaL_newlib(L, MODULE);
    return 1;
}
