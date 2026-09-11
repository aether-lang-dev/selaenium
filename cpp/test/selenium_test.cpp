// selenium_test.cpp — the C++ client's FFI + live test. Header-only C++ over the
// C client; compiled with the one C TU (c/src/selenium.c) and linked against
// libselenium_core.so. No-browser facts always run; live legs self-skip when a
// driver can't be resolved. Exit 0 = pass.
#include "selenium.hpp"

#include <iostream>
#include <string>

using namespace selenium;

static int failures = 0;
static void check(bool cond, const std::string &msg) {
    if (cond) std::cout << "  ok   " << msg << "\n";
    else { std::cout << "  FAIL " << msg << "\n"; failures++; }
}

int main() {
    // ---- pure helpers ----
    check(route("get") == "POST /session/:sessionId/url", "route(get)");
    check(errorCode("no such element") == 17, "errorCode==17");
    check(locator("id", "main").find("*[id=") != std::string::npos, "locator id rewrite");

    // ---- By factory ----
    check(By::css("a").strategy == "css selector", "By::css strategy");
    check(By::xpath("//a").strategy == "xpath", "By::xpath strategy");

    // ---- transport failure -> exception ----
    bool threw = false;
    try {
        WebDriver::headlessChrome("http://127.0.0.1:1");
    } catch (const WebDriverError &e) {
        threw = (e.code == -1);
    }
    check(threw, "headlessChrome to dead port throws (code -1)");

    // ---- live headless Chrome via engine-managed driver ----
    std::string cdrv = resolveDriver("chrome");
    if (cdrv.empty()) {
        std::cout << "  skip live chrome — no chromedriver\n";
    } else {
        try {
            DriverProcess proc = DriverProcess::launch(cdrv);
            WebDriver d = WebDriver::headlessChrome(proc.url());
            check(!d.sessionId().empty(), "chrome session established");

            d.get("data:text/html,<title>Cpp</title><h1 id=h>Hello Cpp</h1>"
                  "<div id=shost></div>"
                  "<script>var r=document.getElementById('shost').attachShadow({mode:'open'});"
                  "r.innerHTML='<p id=sinner>shadowtext</p>';</script>");
            check(d.title() == "Cpp", "title == Cpp");

            WebElement h = d.findElement(By::id("h"));
            check(h.text() == "Hello Cpp", "element text");
            check(h.ariaRole() == "heading", "aria role heading");

            check(d.executeScript("return 6*7;") == "42", "executeScript 6*7 == 42");

            // shadow root
            WebElement host = d.findElement(By::id("shost"));
            ShadowRoot sr = host.shadowRoot();
            WebElement inner = sr.findElement(By::css("#sinner"));
            check(inner.text() == "shadowtext", "shadow content == shadowtext");

            // NoSuchElement -> exception
            bool nse = false;
            try { d.findElement(By::id("nope")); }
            catch (const WebDriverError &e) { nse = (e.code == 17); }
            check(nse, "findElement(missing) throws (17)");
        } catch (const WebDriverError &e) {
            check(false, std::string("live chrome threw: ") + e.what());
        }
    }

    // ---- live headless Firefox ----
    std::string fdrv = resolveDriver("firefox");
    if (fdrv.empty()) {
        std::cout << "  skip live firefox — no geckodriver\n";
    } else {
        try {
            DriverProcess fp = DriverProcess::launch(fdrv);
            WebDriver fd = WebDriver::headlessFirefox(fp.url());
            fd.get("data:text/html,<title>FF</title><h1 id=h>Hello FF</h1>");
            check(fd.title() == "FF", "firefox title == FF");
            check(fd.findElement(By::id("h")).text() == "Hello FF", "firefox element text");
        } catch (const WebDriverError &e) {
            check(false, std::string("live firefox threw: ") + e.what());
        }
    }

    std::cout << (failures == 0 ? "ALL PASSED\n" : "FAILURES\n");
    return failures == 0 ? 0 : 1;
}
