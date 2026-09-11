/* selenium.c — the C client implementation over the aether_sel_embed_* ABI.
 * See c/include/selenium.h. No JSON dependency: the small JSON fragments this
 * layer needs (capability objects, {"url":...}, element-scoped params) are
 * assembled with a tiny local string builder; structured RESULTS are handed
 * back to the caller as JSON text. */
#include "selenium.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ---- the flat C ABI (from selenium_core/embed.ae) ---- */
extern void *aether_sel_embed_open(const char *base_url);
extern void  aether_sel_embed_close(void *h);
extern int   aether_sel_embed_execute(void *h, const char *name, const char *params_json);
extern char *aether_sel_embed_last_value(void *h);
extern int   aether_sel_embed_last_error_code(void *h);
extern char *aether_sel_embed_last_error(void *h);
extern char *aether_sel_embed_session_id(void *h);
extern char *aether_sel_embed_by_locator(const char *strategy, const char *value);
extern char *aether_sel_embed_route(const char *name);
extern int   aether_sel_embed_error_code(const char *w3c_error);
extern char *aether_sel_embed_free_string(char *s);
extern void  aether_sel_embed_set_ca(void *h, const char *ca_path);
extern void  aether_sel_embed_set_insecure(void *h, int on);
extern int   aether_sel_embed_get_attribute(void *h, const char *elem_id, const char *name);
extern int   aether_sel_embed_is_displayed(void *h, const char *elem_id);
extern char *aether_sel_embed_resolve_driver(const char *browser, const char *hint);
extern void *aether_sel_embed_launch_driver(const char *driver_path, int timeout_ms);
extern void *aether_sel_embed_ensure_driver(const char *browser, const char *hint, int timeout_ms);
extern char *aether_sel_embed_driver_url(void *dh);
extern int   aether_sel_embed_driver_pid(void *dh);
extern void  aether_sel_embed_stop_driver(void *dh);

/* ---- handles ---- */
struct sel_driver  { void *h; };
struct sel_element { sel_driver *d; char *id; int shadow; };
struct sel_process { void *dh; };

/* ---- string helpers ---- */

static sel_str empty_str(void) { sel_str s; s.ptr = NULL; s.len = 0; return s; }

/* Copy an ABI-returned string into a caller-owned sel_str and free the
 * original. NULL -> "". The returned ptr is malloc'd here, freed by sel_free. */
static sel_str take(char *p) {
    sel_str s;
    if (p == NULL) {
        s.ptr = (char *)malloc(1);
        if (s.ptr) s.ptr[0] = '\0';
        s.len = 0;
        return s;
    }
    size_t n = strlen(p);
    s.ptr = (char *)malloc(n + 1);
    if (s.ptr) { memcpy(s.ptr, p, n + 1); s.len = n; }
    else { s.len = 0; }
    aether_sel_embed_free_string(p);
    return s;
}

void sel_free(sel_str s) { free(s.ptr); }

/* A minimal growable buffer for assembling small JSON fragments. */
typedef struct { char *b; size_t len, cap; } buf;
static void buf_init(buf *x) { x->b = NULL; x->len = 0; x->cap = 0; }
static void buf_add(buf *x, const char *s) {
    size_t n = strlen(s);
    if (x->len + n + 1 > x->cap) {
        size_t nc = x->cap ? x->cap * 2 : 64;
        while (nc < x->len + n + 1) nc *= 2;
        x->b = (char *)realloc(x->b, nc);
        x->cap = nc;
    }
    memcpy(x->b + x->len, s, n + 1);
    x->len += n;
}
/* Append a JSON-escaped string literal (quotes included). Handles the escapes
 * a WebDriver value/URL realistically needs; sufficient for this thin layer. */
static void buf_add_json_str(buf *x, const char *s) {
    buf_add(x, "\"");
    char tmp[8];
    for (const char *p = s; *p; p++) {
        unsigned char c = (unsigned char)*p;
        switch (c) {
            case '"':  buf_add(x, "\\\""); break;
            case '\\': buf_add(x, "\\\\"); break;
            case '\n': buf_add(x, "\\n");  break;
            case '\r': buf_add(x, "\\r");  break;
            case '\t': buf_add(x, "\\t");  break;
            default:
                if (c < 0x20) { snprintf(tmp, sizeof tmp, "\\u%04x", c); buf_add(x, tmp); }
                else { tmp[0] = (char)c; tmp[1] = '\0'; buf_add(x, tmp); }
        }
    }
    buf_add(x, "\"");
}
static void buf_free(buf *x) { free(x->b); }

/* ---- session lifecycle ---- */

sel_driver *sel_open(const char *base_url) {
    void *h = aether_sel_embed_open(base_url);
    if (h == NULL) return NULL;
    sel_driver *d = (sel_driver *)malloc(sizeof *d);
    if (d == NULL) { aether_sel_embed_close(h); return NULL; }
    d->h = h;
    return d;
}
void sel_close(sel_driver *d) {
    if (d == NULL) return;
    if (d->h) aether_sel_embed_close(d->h);
    free(d);
}
void sel_set_ca(sel_driver *d, const char *ca_path) { if (d) aether_sel_embed_set_ca(d->h, ca_path); }
void sel_set_insecure(sel_driver *d, int on)        { if (d) aether_sel_embed_set_insecure(d->h, on); }

sel_str sel_session_id(sel_driver *d) { return d ? take(aether_sel_embed_session_id(d->h)) : empty_str(); }
sel_str sel_last_error(sel_driver *d) { return d ? take(aether_sel_embed_last_error(d->h)) : empty_str(); }
int sel_last_error_code(sel_driver *d) { return d ? aether_sel_embed_last_error_code(d->h) : -1; }

/* ---- raw commands ---- */

int sel_execute(sel_driver *d, const char *command, const char *params_json) {
    if (d == NULL) return -1;
    return aether_sel_embed_execute(d->h, command, params_json ? params_json : "{}");
}
sel_str sel_last_value(sel_driver *d) { return d ? take(aether_sel_embed_last_value(d->h)) : empty_str(); }

/* Build {"capabilities":{"alwaysMatch":{ browserName, webSocketUrl:true,
 * <options> }}} and run newSession. options_json (if non-NULL) is a JSON object
 * whose members are spliced in (must be a bare object like {"k":v,...}). */
static int new_session(sel_driver *d, const char *browser_name, const char *options_json) {
    buf x; buf_init(&x);
    buf_add(&x, "{\"capabilities\":{\"alwaysMatch\":{\"browserName\":");
    buf_add_json_str(&x, browser_name);
    buf_add(&x, ",\"webSocketUrl\":true");
    if (options_json && options_json[0]) {
        /* splice the caller object's members: strip the outer braces. */
        const char *o = options_json;
        while (*o && *o != '{') o++;
        if (*o == '{') {
            const char *end = o + strlen(o);
            while (end > o && *(end - 1) != '}') end--;
            if (end > o + 1) {
                buf_add(&x, ",");
                /* append o+1 .. end-1 (contents between the braces) */
                size_t inner = (size_t)((end - 1) - (o + 1));
                char *frag = (char *)malloc(inner + 1);
                if (frag) { memcpy(frag, o + 1, inner); frag[inner] = '\0';
                            buf_add(&x, frag); free(frag); }
            }
        }
    }
    buf_add(&x, "}}}");
    int rc = aether_sel_embed_execute(d->h, "newSession", x.b ? x.b : "{}");
    buf_free(&x);
    return rc;
}

int sel_chrome(sel_driver *d, const char *options_json)  { return d ? new_session(d, "chrome", options_json) : -1; }
int sel_firefox(sel_driver *d, const char *options_json) { return d ? new_session(d, "firefox", options_json) : -1; }
int sel_edge(sel_driver *d, const char *options_json)    { return d ? new_session(d, "MicrosoftEdge", options_json) : -1; }
int sel_safari(sel_driver *d, const char *options_json)  { return d ? new_session(d, "safari", options_json) : -1; }

int sel_headless_chrome(sel_driver *d) {
    return sel_chrome(d, "{\"goog:chromeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]}}");
}
int sel_headless_firefox(sel_driver *d) {
    return sel_firefox(d, "{\"moz:firefoxOptions\":{\"args\":[\"-headless\"]}}");
}
int sel_headless_edge(sel_driver *d) {
    return sel_edge(d, "{\"ms:edgeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]}}");
}

/* ---- navigation ---- */

int sel_get(sel_driver *d, const char *url) {
    if (d == NULL) return -1;
    buf x; buf_init(&x);
    buf_add(&x, "{\"url\":"); buf_add_json_str(&x, url); buf_add(&x, "}");
    int rc = aether_sel_embed_execute(d->h, "get", x.b);
    buf_free(&x);
    return rc;
}
/* Run a no-arg command and return its string value ("" on error). */
static sel_str simple_str(sel_driver *d, const char *cmd) {
    if (d == NULL) return empty_str();
    int rc = aether_sel_embed_execute(d->h, cmd, "{}");
    if (rc != 0) return empty_str();
    return take(aether_sel_embed_last_value(d->h));
}
/* getTitle etc. return a JSON string value ("\"x\"") — unwrap one JSON string. */
static sel_str unwrap_json_str(sel_str v) {
    if (v.len >= 2 && v.ptr[0] == '"' && v.ptr[v.len - 1] == '"') {
        /* naive unescape sufficient for titles/urls: strip quotes, unescape \" \\ */
        char *out = (char *)malloc(v.len);
        size_t j = 0;
        for (size_t i = 1; i + 1 < v.len; i++) {
            if (v.ptr[i] == '\\' && i + 2 < v.len) {
                char n = v.ptr[i + 1];
                if (n == '"' || n == '\\' || n == '/') { out[j++] = n; i++; continue; }
                if (n == 'n') { out[j++] = '\n'; i++; continue; }
                if (n == 't') { out[j++] = '\t'; i++; continue; }
                if (n == 'r') { out[j++] = '\r'; i++; continue; }
            }
            out[j++] = v.ptr[i];
        }
        out[j] = '\0';
        sel_free(v);
        sel_str s; s.ptr = out; s.len = j; return s;
    }
    return v;
}
sel_str sel_title(sel_driver *d)       { return unwrap_json_str(simple_str(d, "getTitle")); }
sel_str sel_current_url(sel_driver *d) { return unwrap_json_str(simple_str(d, "getCurrentUrl")); }
sel_str sel_page_source(sel_driver *d) { return unwrap_json_str(simple_str(d, "getPageSource")); }
int sel_back(sel_driver *d)    { return sel_execute(d, "goBack", "{}"); }
int sel_forward(sel_driver *d) { return sel_execute(d, "goForward", "{}"); }
int sel_refresh(sel_driver *d) { return sel_execute(d, "refresh", "{}"); }

/* ---- elements ---- */

/* Extract the string value of `key` from a flat JSON object (thin scanner,
 * sufficient for {"<key>":"<id>"} element/shadow payloads). NULL if absent. */
static char *json_str_field(const char *json, const char *key) {
    if (json == NULL) return NULL;
    buf pat; buf_init(&pat);
    buf_add(&pat, "\""); buf_add(&pat, key); buf_add(&pat, "\"");
    const char *at = strstr(json, pat.b);
    buf_free(&pat);
    if (at == NULL) return NULL;
    at += strlen(key) + 2;
    while (*at == ' ' || *at == ':') at++;
    if (*at != '"') return NULL;
    at++;
    const char *end = at;
    while (*end && *end != '"') { if (*end == '\\') end++; end++; }
    size_t n = (size_t)(end - at);
    char *out = (char *)malloc(n + 1);
    memcpy(out, at, n); out[n] = '\0';
    return out;
}

static sel_element *make_element(sel_driver *d, char *id, int shadow) {
    if (id == NULL) return NULL;
    sel_element *e = (sel_element *)malloc(sizeof *e);
    if (e == NULL) { free(id); return NULL; }
    e->d = d; e->id = id; e->shadow = shadow;
    return e;
}

/* find via a command that takes a locator (+ optional id param for scoped). */
static sel_element *find_one(sel_driver *d, const char *command, const char *strategy,
                             const char *value, const char *scope_id) {
    if (d == NULL) return NULL;
    sel_str loc = take(aether_sel_embed_by_locator(strategy, value)); /* {"using":..,"value":..} */
    buf x; buf_init(&x);
    /* splice locator members + optional id */
    buf_add(&x, "{");
    if (loc.len >= 2) {
        size_t inner = loc.len - 2;
        char *frag = (char *)malloc(inner + 1);
        if (frag) { memcpy(frag, loc.ptr + 1, inner); frag[inner] = '\0'; buf_add(&x, frag); free(frag); }
    }
    if (scope_id) { buf_add(&x, ",\"id\":"); buf_add_json_str(&x, scope_id); }
    buf_add(&x, "}");
    sel_free(loc);
    int rc = aether_sel_embed_execute(d->h, command, x.b);
    buf_free(&x);
    if (rc != 0) return NULL;
    sel_str v = take(aether_sel_embed_last_value(d->h));
    char *id = json_str_field(v.ptr, SEL_W3C_ELEMENT_KEY);
    sel_free(v);
    return make_element(d, id, 0);
}

sel_element *sel_find_element(sel_driver *d, const char *strategy, const char *value) {
    return find_one(d, "findElement", strategy, value, NULL);
}
sel_element *sel_find_child(sel_element *e, const char *strategy, const char *value) {
    if (e == NULL) return NULL;
    const char *cmd = e->shadow ? "findElementFromShadowRoot" : "findChildElement";
    return find_one(e->d, cmd, strategy, value, e->id);
}
void sel_element_free(sel_element *e) { if (e) { free(e->id); free(e); } }
sel_str sel_element_id(sel_element *e) {
    if (e == NULL) return empty_str();
    size_t n = strlen(e->id);
    sel_str s; s.ptr = (char *)malloc(n + 1); memcpy(s.ptr, e->id, n + 1); s.len = n; return s;
}

/* element-scoped command with just the id param. */
static int el_cmd(sel_element *e, const char *command) {
    if (e == NULL) return -1;
    buf x; buf_init(&x);
    buf_add(&x, "{\"id\":"); buf_add_json_str(&x, e->id); buf_add(&x, "}");
    int rc = aether_sel_embed_execute(e->d->h, command, x.b);
    buf_free(&x);
    return rc;
}
static sel_str el_str(sel_element *e, const char *command) {
    if (el_cmd(e, command) != 0) return empty_str();
    return unwrap_json_str(take(aether_sel_embed_last_value(e->d->h)));
}

int sel_click(sel_element *e) { return el_cmd(e, "clickElement"); }
int sel_clear(sel_element *e) { return el_cmd(e, "clearElement"); }
int sel_send_keys(sel_element *e, const char *text) {
    if (e == NULL) return -1;
    buf x; buf_init(&x);
    buf_add(&x, "{\"id\":"); buf_add_json_str(&x, e->id);
    buf_add(&x, ",\"text\":"); buf_add_json_str(&x, text);
    buf_add(&x, ",\"value\":["); buf_add_json_str(&x, text); buf_add(&x, "]}");
    int rc = aether_sel_embed_execute(e->d->h, "sendKeysToElement", x.b);
    buf_free(&x);
    return rc;
}
sel_str sel_text(sel_element *e)     { return el_str(e, "getElementText"); }
sel_str sel_tag_name(sel_element *e) { return el_str(e, "getElementTagName"); }
sel_str sel_aria_role(sel_element *e) { return el_str(e, "getAriaRole"); }
sel_str sel_accessible_name(sel_element *e) { return el_str(e, "getAccessibleName"); }

sel_str sel_get_attribute(sel_element *e, const char *name) {
    if (e == NULL) return empty_str();
    int rc = aether_sel_embed_get_attribute(e->d->h, e->id, name);
    if (rc != 0) return empty_str();
    return unwrap_json_str(take(aether_sel_embed_last_value(e->d->h)));
}
int sel_is_displayed(sel_element *e) {
    if (e == NULL) return -1;
    int rc = aether_sel_embed_is_displayed(e->d->h, e->id);
    if (rc != 0) return -1;
    sel_str v = take(aether_sel_embed_last_value(e->d->h));
    int r = (v.ptr && strcmp(v.ptr, "true") == 0) ? 1 : 0;
    sel_free(v);
    return r;
}
static int el_bool(sel_element *e, const char *command) {
    if (el_cmd(e, command) != 0) return -1;
    sel_str v = take(aether_sel_embed_last_value(e->d->h));
    int r = (v.ptr && strcmp(v.ptr, "true") == 0) ? 1 : 0;
    sel_free(v);
    return r;
}
int sel_is_enabled(sel_element *e)  { return el_bool(e, "isElementEnabled"); }
int sel_is_selected(sel_element *e) { return el_bool(e, "isElementSelected"); }

sel_element *sel_shadow_root(sel_element *e) {
    if (e == NULL) return NULL;
    if (el_cmd(e, "getShadowRoot") != 0) return NULL;
    sel_str v = take(aether_sel_embed_last_value(e->d->h));
    char *id = json_str_field(v.ptr, SEL_W3C_SHADOW_KEY);
    sel_free(v);
    return make_element(e->d, id, 1); /* shadow=1 → child finds use shadow route */
}

/* ---- scripts ---- */
int sel_execute_script(sel_driver *d, const char *script, const char *args_json) {
    if (d == NULL) return -1;
    buf x; buf_init(&x);
    buf_add(&x, "{\"script\":"); buf_add_json_str(&x, script);
    buf_add(&x, ",\"args\":"); buf_add(&x, (args_json && args_json[0]) ? args_json : "[]");
    buf_add(&x, "}");
    int rc = aether_sel_embed_execute(d->h, "executeScript", x.b);
    buf_free(&x);
    return rc;
}

/* ---- driver orchestration ---- */
sel_str sel_resolve_driver(const char *browser, const char *hint) {
    return take(aether_sel_embed_resolve_driver(browser, hint ? hint : ""));
}
sel_process *sel_launch_driver(const char *driver_path, int timeout_ms) {
    void *dh = aether_sel_embed_launch_driver(driver_path, timeout_ms);
    if (dh == NULL) return NULL;
    sel_process *p = (sel_process *)malloc(sizeof *p);
    if (p == NULL) { aether_sel_embed_stop_driver(dh); return NULL; }
    p->dh = dh;
    return p;
}
sel_process *sel_ensure_driver(const char *browser, const char *hint, int timeout_ms) {
    void *dh = aether_sel_embed_ensure_driver(browser, hint ? hint : "", timeout_ms);
    if (dh == NULL) return NULL;
    sel_process *p = (sel_process *)malloc(sizeof *p);
    if (p == NULL) { aether_sel_embed_stop_driver(dh); return NULL; }
    p->dh = dh;
    return p;
}
sel_str sel_process_url(sel_process *p) { return p ? take(aether_sel_embed_driver_url(p->dh)) : empty_str(); }
int sel_process_pid(sel_process *p)     { return p ? aether_sel_embed_driver_pid(p->dh) : -1; }
void sel_process_stop(sel_process *p) {
    if (p == NULL) return;
    if (p->dh) aether_sel_embed_stop_driver(p->dh);
    free(p);
}

/* ---- pure helpers ---- */
sel_str sel_route(const char *command) { return take(aether_sel_embed_route(command)); }
int sel_error_code(const char *w3c_error) { return aether_sel_embed_error_code(w3c_error); }
sel_str sel_locator(const char *strategy, const char *value) {
    return take(aether_sel_embed_by_locator(strategy, value));
}
