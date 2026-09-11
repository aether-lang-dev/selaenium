/**
 * No-browser FFI test: proves the D binding links libselenium_core and marshals
 * correctly, exercising the pure engine helpers + the transport error path, plus
 * the convenience tier (Keys, Select, Actions, waits, frames) that needs no
 * browser. Built by d/.tests.ae with the .so on the link path + rpath.
 *
 * Run standalone: dmd -Isrc -L-L<native> -L-lselenium_core -run tests/ffi_test.d
 */
import std.json;
import std.stdio : writeln;
import std.string : indexOf;
import selenium;

private int failures = 0;

private void check(bool cond, string msg) {
    if (cond) {
        writeln("  ok   ", msg);
    } else {
        writeln("  FAIL ", msg);
        failures++;
    }
}

void main() {
    // --- pure engine helpers ---
    check(route("get") == "POST /session/:sessionId/url", "route(get)");
    check(route("nope") == "", "route(unknown) is empty");

    check(errorCode("no such element") == 17, "errorCode(no such element)==17");
    check(errorCode("") == 0, "errorCode(empty)==0");

    // --- By factory ---
    auto css = By.cssSelector("div.foo");
    check(css.strategy == "css selector", "By.cssSelector strategy");
    check(css.value == "div.foo", "By.cssSelector value");
    check(By.className("x").strategy == "class name", "By.className strategy");
    check(By.xpath("//a").strategy == "xpath", "By.xpath strategy");

    // --- locator JSON ---
    auto locJson = parseJSON(locator("css selector", "div.foo"));
    check(locJson["using"].str == "css selector", "locator using");
    check(locJson["value"].str == "div.foo", "locator value");
    check(locator("id", "main").indexOf("*[id=") >= 0, "locator id rewrite to CSS");

    // --- transport failure path (no server on :1) ---
    bool threw = false;
    try {
        auto d = chrome("http://127.0.0.1:1");
        d.quit();
    } catch (WebDriverException e) {
        threw = e.code == -1 && e.kind == ErrorKind.transport;
    }
    check(threw, "chrome() to dead port raises transport error (code -1)");

    // --- Keys: PUA code points + aliases ---
    check(Keys.enter[0] != 0, "Keys.enter is a PUA char");
    check(Keys.arrowLeft == Keys.left, "Keys.arrowLeft aliases left");
    check(Keys.command == Keys.meta, "Keys.command aliases meta");
    check(BackSpace == Keys.backspace, "BackSpace aliases backspace");
    // chord: modifier + keys + trailing NULL
    check(chord(Keys.control, "a") == Keys.control ~ "a" ~ Keys.nul, "chord builds hold+NULL");

    // --- Select: pure option matching ---
    OptionData[] opts = [
        OptionData("us", "United States"),
        OptionData("es", "Spain"),
        OptionData("fr", "France")];
    check(firstMatchIndex(opts, SelectBy.value, "es") == 1, "match by value");
    check(firstMatchIndex(opts, SelectBy.value, "nope") == -1, "no match by value");
    check(firstMatchIndex(opts, SelectBy.text, "France") == 2, "match by text");
    check(firstMatchIndex(opts, SelectBy.text, "Nowhere") == -1, "no match by text");
    check(firstMatchIndex(opts, SelectBy.index, "0") == 0, "match by index 0");
    check(firstMatchIndex(opts, SelectBy.index, "3") == -1, "index out of range");
    check(firstMatchIndex(opts, SelectBy.index, "x") == -1, "index non-numeric");

    // --- frames ---
    check(frameIndex(2).kind == FrameKind.index, "frameIndex kind");
    check(frameIndex(2).index == 2, "frameIndex value");
    check(defaultFrame().kind == FrameKind.deflt, "defaultFrame kind");

    // --- Actions: W3C sequence building (no browser) ---
    {
        // click: move + down + up on a single pointer device
        auto a = new Actions(null);
        auto el = elementStub("E1");
        auto built = a.click(el).build();
        check(built.type == JSONType.array && built.array.length == 1, "click builds 1 device");
        auto dev = built[0];
        check(dev["type"].str == "pointer", "device is pointer");
        check(dev["id"].str == "mouse", "device id mouse");
        auto seq = dev["actions"].array;
        check(seq[0]["type"].str == "pointerMove", "seq[0] pointerMove");
        check(seq[0]["origin"][w3cElementKey].str == "E1", "move origin is element");
        check(seq[1]["type"].str == "pointerDown" && seq[1]["button"].integer == 0, "seq[1] down btn0");
        check(seq[2]["type"].str == "pointerUp", "seq[2] up");
    }
    {
        // context click uses button 2
        auto built = new Actions(null).contextClick(elementStub("E2")).build();
        check(built[0]["actions"].array[1]["button"].integer == 2, "contextClick button 2");
    }
    {
        // double click: move + two down/up pairs = 5 actions
        auto built = new Actions(null).doubleClick(elementStub("E3")).build();
        check(built[0]["actions"].array.length == 5, "doubleClick emits 5 actions");
    }
    {
        // key gestures build a keyboard device
        auto built = new Actions(null).keyDown(Keys.shift).sendKeys("a").keyUp(Keys.shift).build();
        check(built.array.length == 1, "key-only chain = 1 device");
        auto dev = built[0];
        check(dev["type"].str == "key" && dev["id"].str == "keyboard", "keyboard device");
        auto seq = dev["actions"].array;
        check(seq[0]["type"].str == "keyDown", "keyDown first");
    }
    {
        // dragAndDrop: move,down,move,up on the pointer device
        auto built = new Actions(null).dragAndDrop(elementStub("S"), elementStub("T")).build();
        auto seq = built[0]["actions"].array;
        check(seq[0]["type"].str == "pointerMove", "drag move");
        check(seq[1]["type"].str == "pointerDown", "drag down");
        check(seq[2]["type"].str == "pointerMove" && seq[2]["origin"][w3cElementKey].str == "T", "drag to target");
        check(seq[3]["type"].str == "pointerUp", "drag up");
    }
    {
        // empty chain builds nothing
        check(new Actions(null).build().array.length == 0, "empty chain -> 0 devices");
    }

    writeln(failures == 0 ? "ALL PASSED" : "FAILURES");
    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}

/// A WebElement carrying just an id, for building Actions sequences without a
/// live session (the Actions builder only reads `.id`).
private WebElement elementStub(string id) {
    return WebElement.fromId(id);
}
