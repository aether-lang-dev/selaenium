/* selenium_test.c — the C client's FFI + live test. Compiled and linked against
 * libselenium_core.so (rpath ../selenium_core/native). No-browser facts always
 * run; the live legs self-skip when a driver can't be resolved. Exit 0 = pass. */
#include "selenium.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;
static void check(int cond, const char *msg) {
    if (cond) { printf("  ok   %s\n", msg); }
    else { printf("  FAIL %s\n", msg); failures++; }
}

int main(void) {
    /* ---- pure engine helpers (no session) ---- */
    sel_str r = sel_route("get");
    check(strcmp(r.ptr, "POST /session/:sessionId/url") == 0, "route(get)");
    sel_free(r);

    check(sel_error_code("no such element") == 17, "errorCode(no such element)==17");
    check(sel_error_code("") == 0, "errorCode(empty)==0");

    sel_str loc = sel_locator("css selector", "div.foo");
    check(strstr(loc.ptr, "\"using\"") && strstr(loc.ptr, "css selector") && strstr(loc.ptr, "div.foo"),
          "locator css round-trips");
    sel_free(loc);

    sel_str idloc = sel_locator("id", "main");
    check(strstr(idloc.ptr, "*[id=") != NULL, "locator id rewrite to CSS");
    sel_free(idloc);

    /* ---- transport failure path ---- */
    sel_driver *dead = sel_open("http://127.0.0.1:1");
    check(dead != NULL, "sel_open returns a handle");
    int rc = sel_headless_chrome(dead);
    check(rc == -1, "headless_chrome to dead port -> transport failure (-1)");
    sel_close(dead);

    /* ---- live headless Chrome via the engine-managed driver ---- */
    sel_str cdrv = sel_resolve_driver("chrome", NULL);
    if (cdrv.len == 0) {
        printf("  skip live chrome — no chromedriver resolved\n");
    } else {
        sel_process *proc = sel_launch_driver(cdrv.ptr, 20000);
        if (proc == NULL) {
            printf("  skip live chrome — driver did not launch\n");
        } else {
            sel_str url = sel_process_url(proc);
            sel_driver *d = sel_open(url.ptr);
            sel_free(url);
            check(sel_headless_chrome(d) == 0, "live chrome session created");

            sel_get(d, "data:text/html,<title>C</title><h1 id=h>Hello C</h1>"
                       "<button id=b onclick=\"document.getElementById('h').textContent='clicked'\">b</button>"
                       "<div id=shost></div>"
                       "<script>var r=document.getElementById('shost').attachShadow({mode:'open'});"
                       "r.innerHTML='<p id=sinner>shadowtext</p>';</script>");
            sel_str t = sel_title(d);
            check(strcmp(t.ptr, "C") == 0, "title == C");
            sel_free(t);

            sel_element *h = sel_find_element(d, "id", "h");
            check(h != NULL, "findElement(#h)");
            sel_str ht = sel_text(h);
            check(strcmp(ht.ptr, "Hello C") == 0, "element text == Hello C");
            sel_free(ht);
            sel_str role = sel_aria_role(h);
            check(strcmp(role.ptr, "heading") == 0, "aria role == heading");
            sel_free(role);
            sel_element_free(h);

            sel_element *btn = sel_find_element(d, "id", "b");
            check(sel_click(btn) == 0, "click button");
            sel_element_free(btn);
            sel_element *h2 = sel_find_element(d, "id", "h");
            sel_str h2t = sel_text(h2);
            check(strcmp(h2t.ptr, "clicked") == 0, "onclick updated text");
            sel_free(h2t);
            sel_element_free(h2);

            check(sel_execute_script(d, "return 6*7;", NULL) == 0, "executeScript ran");
            sel_str sv = sel_last_value(d);
            check(strcmp(sv.ptr, "42") == 0, "executeScript 6*7 == 42");
            sel_free(sv);

            /* shadow root: find inside it */
            sel_element *host = sel_find_element(d, "id", "shost");
            sel_element *sr = sel_shadow_root(host);
            check(sr != NULL, "getShadowRoot");
            if (sr) {
                sel_element *inner = sel_find_child(sr, "css selector", "#sinner");
                check(inner != NULL, "findElementFromShadowRoot");
                if (inner) {
                    sel_str it = sel_text(inner);
                    check(strcmp(it.ptr, "shadowtext") == 0, "shadow content == shadowtext");
                    sel_free(it);
                    sel_element_free(inner);
                }
                sel_element_free(sr);
            }
            sel_element_free(host);

            sel_execute(d, "quit", "{}");
            sel_close(d);
            sel_process_stop(proc);
        }
    }
    sel_free(cdrv);

    /* ---- live headless Firefox (proves the firefox factory + gecko resolve) ---- */
    sel_str fdrv = sel_resolve_driver("firefox", NULL);
    if (fdrv.len == 0) {
        printf("  skip live firefox — no geckodriver resolved\n");
    } else {
        sel_process *fp = sel_launch_driver(fdrv.ptr, 20000);
        if (fp == NULL) {
            printf("  skip live firefox — driver did not launch\n");
        } else {
            sel_str furl = sel_process_url(fp);
            sel_driver *fd = sel_open(furl.ptr);
            sel_free(furl);
            check(sel_headless_firefox(fd) == 0, "live firefox session created");
            sel_get(fd, "data:text/html,<title>FF</title><h1 id=h>Hello FF</h1>");
            sel_str ft = sel_title(fd);
            check(strcmp(ft.ptr, "FF") == 0, "firefox title == FF");
            sel_free(ft);
            sel_element *fh = sel_find_element(fd, "id", "h");
            sel_str fht = sel_text(fh);
            check(strcmp(fht.ptr, "Hello FF") == 0, "firefox element text");
            sel_free(fht);
            sel_element_free(fh);
            sel_execute(fd, "quit", "{}");
            sel_close(fd);
            sel_process_stop(fp);
        }
    }
    sel_free(fdrv);

    printf(failures == 0 ? "ALL PASSED\n" : "FAILURES\n");
    return failures == 0 ? 0 : 1;
}
