/* selenium.h — the C client for the shared pure-Aether WebDriver engine.
 *
 * The thinnest possible ergonomic layer over the flat C ABI
 * (aether_sel_embed_*, from selenium_core/embed.ae): it owns the
 * caller-owned-string discipline (every ABI char* is copied into a
 * sel_str you free with sel_free, or consumed internally) and marshals
 * the common W3C commands, but carries NO protocol logic and NO JSON
 * dependency — element/command results that are structured come back as
 * JSON text for the caller to parse with whatever JSON library they like.
 *
 * This header is ALSO the substrate the C++ client (cpp/) wraps in RAII.
 *
 * Portability: C99, no dependencies beyond the engine .so. Link with
 * -lselenium_core (+ an rpath to its directory). Thread-safety matches the
 * engine: each sel_driver handle is independent; do not share one across
 * threads without external synchronisation.
 */
#ifndef SELENIUM_C_H
#define SELENIUM_C_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A heap string owned by the caller. `ptr` is NUL-terminated (never NULL for
 * a successful call; "" on an empty result). Free EVERY sel_str with
 * sel_free — do not free() it directly (it came from the engine allocator). */
typedef struct {
    char *ptr;
    size_t len;
} sel_str;

/* Opaque handles. */
typedef struct sel_driver sel_driver;    /* a W3C session */
typedef struct sel_element sel_element;  /* an element reference within a session */
typedef struct sel_process sel_process;  /* a launched driver process */

/* The W3C element/shadow reference keys, exposed for callers parsing JSON. */
#define SEL_W3C_ELEMENT_KEY "element-6066-11e4-a52e-4f735466cecf"
#define SEL_W3C_SHADOW_KEY  "shadow-6066-11e4-a52e-4f735466cecf"

/* ---- result / error ---- */
/* Most calls return an int result code: 0 on success, a W3C error code
 * (>0), or -1 on transport failure. After any failure, sel_last_error(d)
 * gives a human-readable message and sel_last_error_code(d) the code. */

/* Free a sel_str returned by this API. NULL-safe. */
void sel_free(sel_str s);

/* ---- session lifecycle ---- */
/* Open a session handle bound to a running driver/Grid base URL (e.g.
 * "http://127.0.0.1:9515"). No network I/O until the browser factory /
 * sel_execute runs newSession. NULL on allocation failure. */
sel_driver *sel_open(const char *base_url);
/* Close the session and release the handle (does NOT send "quit" — call the
 * "quit" command first for a clean browser shutdown). NULL-safe. */
void sel_close(sel_driver *d);

/* TLS trust config — call before the first request (before a browser factory). */
void sel_set_ca(sel_driver *d, const char *ca_path);
void sel_set_insecure(sel_driver *d, int on);

/* The current W3C session id ("" until a session is created). */
sel_str sel_session_id(sel_driver *d);
/* The last error message / code after a failed call. */
sel_str sel_last_error(sel_driver *d);
int sel_last_error_code(sel_driver *d);

/* ---- browser factories ----
 * Create a session on `d` for the given browser. Pass extra capabilities as
 * a JSON object string (or NULL for none); the factory sets browserName and
 * requests a BiDi channel. Returns 0 on success (else W3C code / -1). The
 * headless_* variants add the standard headless launch args.
 * browserName: chrome / firefox / MicrosoftEdge / safari. */
int sel_chrome(sel_driver *d, const char *options_json);
int sel_headless_chrome(sel_driver *d);
int sel_firefox(sel_driver *d, const char *options_json);
int sel_headless_firefox(sel_driver *d);
int sel_edge(sel_driver *d, const char *options_json);
int sel_headless_edge(sel_driver *d);
int sel_safari(sel_driver *d, const char *options_json);

/* ---- raw commands ---- */
/* Issue any W3C command by name with a JSON params string (or NULL).
 * Returns 0 / W3C code / -1. Drain the value with sel_last_value. */
int sel_execute(sel_driver *d, const char *command, const char *params_json);
/* The decoded `value` of the last command as JSON text ("" if empty/null). */
sel_str sel_last_value(sel_driver *d);

/* ---- navigation (convenience) ---- */
int sel_get(sel_driver *d, const char *url);        /* navigate */
sel_str sel_title(sel_driver *d);                   /* "" on error (check sel_last_error_code) */
sel_str sel_current_url(sel_driver *d);
sel_str sel_page_source(sel_driver *d);
int sel_back(sel_driver *d);
int sel_forward(sel_driver *d);
int sel_refresh(sel_driver *d);

/* ---- find ---- */
/* Find one element by strategy ("css selector"/"id"/"xpath"/...). Returns a
 * sel_element (free with sel_element_free), or NULL on no-such-element/error
 * (check sel_last_error_code). */
sel_element *sel_find_element(sel_driver *d, const char *strategy, const char *value);
/* Free an element handle. NULL-safe. Does NOT affect the DOM. */
void sel_element_free(sel_element *e);
/* The W3C element reference id (for JSON / actions origins). */
sel_str sel_element_id(sel_element *e);

/* ---- element commands (convenience) ---- */
int sel_click(sel_element *e);
int sel_clear(sel_element *e);
int sel_send_keys(sel_element *e, const char *text);
sel_str sel_text(sel_element *e);                   /* getElementText */
sel_str sel_tag_name(sel_element *e);
sel_str sel_get_attribute(sel_element *e, const char *name);  /* atom-backed */
sel_str sel_aria_role(sel_element *e);
sel_str sel_accessible_name(sel_element *e);
int sel_is_displayed(sel_element *e);               /* 1/0, or -1 on error */
int sel_is_enabled(sel_element *e);
int sel_is_selected(sel_element *e);
/* A descendant of this element (findChildElement). NULL if none/error. */
sel_element *sel_find_child(sel_element *e, const char *strategy, const char *value);
/* This element's shadow root as an element handle whose finds are
 * shadow-scoped. NULL (with code 19) if the element hosts no shadow root. */
sel_element *sel_shadow_root(sel_element *e);

/* ---- scripts ---- */
/* Execute JS; `args_json` is a JSON array string (or NULL for []). The result
 * value is available via sel_last_value. Returns 0 / W3C code / -1. */
int sel_execute_script(sel_driver *d, const char *script, const char *args_json);

/* ---- driver-process orchestration (the ported Selenium Manager) ---- */
/* Resolve (downloading if needed) the driver binary path for a browser
 * ("chrome"/"firefox"/"edge"); "" on failure. `hint` may be NULL. */
sel_str sel_resolve_driver(const char *browser, const char *hint);
/* Launch a driver binary; NULL on failure. */
sel_process *sel_launch_driver(const char *driver_path, int timeout_ms);
/* Resolve + launch a driver for `browser` (download if needed); NULL on fail. */
sel_process *sel_ensure_driver(const char *browser, const char *hint, int timeout_ms);
/* The running driver's base URL (pass to sel_open). */
sel_str sel_process_url(sel_process *p);
int sel_process_pid(sel_process *p);
/* Kill + reap the driver process and free the handle. NULL-safe. */
void sel_process_stop(sel_process *p);

/* ---- pure engine helpers (no session needed) ---- */
/* The "METHOD PATH" route for a command name, "" if unknown. */
sel_str sel_route(const char *command);
/* The stable integer code for a W3C error string (0 = success). */
int sel_error_code(const char *w3c_error);
/* The W3C {"using","value"} locator JSON for a (strategy,value) pair. */
sel_str sel_locator(const char *strategy, const char *value);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* SELENIUM_C_H */
