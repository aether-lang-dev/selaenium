/**
 * Consumer-install proof (D): a third party drives the engine via ONLY the
 * packaged binding + its bundled native/.so, with SELENIUM_CORE_LIB unset.
 *
 * Mode (argv[1]):
 *   ffi  — no-browser: link + a couple of pure engine facts through the ABI.
 *   live — resolve+launch chromedriver via the engine, drive a real session;
 *          self-skips (exit 0) when chromedriver is unavailable.
 *
 * Built by d/.example.ae from a clean stage: it compiles this file with the
 * packaged binding source (../d-pkg/src/selenium/package.d) and links the
 * packaged .so (../d-pkg/native/libselenium_core.so).
 */
import std.stdio : writeln;
import std.json;
import std.string : toLower;
import std.conv : to;
import selenium;

int main(string[] argv) {
    string mode = argv.length > 1 ? argv[1] : "ffi";

    if (mode == "ffi") {
        // Prove the link + the ABI round-trip with pure facts.
        if (route("get") != "POST /session/:sessionId/url") {
            writeln("FAIL: route(get) unexpected"); return 1;
        }
        if (errorCode("no such element") != 17) {
            writeln("FAIL: errorCode unexpected"); return 1;
        }
        auto loc = parseJSON(locator("css selector", "div.foo"));
        if (loc["using"].str != "css selector") {
            writeln("FAIL: locator unexpected"); return 1;
        }
        writeln("ffi OK — consumer linked the bundled engine .so");
        return 0;
    }

    if (mode == "live") {
        string driver = resolveDriver("chrome");
        if (driver.length == 0) {
            writeln("SKIPPED: chromedriver could not be resolved");
            return 0;
        }
        auto proc = launchDriver(driver);
        if (proc is null) {
            writeln("SKIPPED: chromedriver did not launch");
            return 0;
        }
        scope(exit) proc.stop();

        auto d = headlessChrome(proc.url());
        scope(exit) d.quit();

        d.get("data:text/html,<title>Hi</title><h1 id=h>Hello</h1>");
        if (d.title() != "Hi") { writeln("FAIL: title"); return 1; }
        if (d.findElement(By.id("h")).text() != "Hello") { writeln("FAIL: text"); return 1; }
        if (d.executeScript("return 6*7;").integer != 42) { writeln("FAIL: script"); return 1; }
        writeln("live OK — consumer drove a real Chrome session via the bundled .so");
        return 0;
    }

    writeln("unknown mode: ", mode);
    return 1;
}
