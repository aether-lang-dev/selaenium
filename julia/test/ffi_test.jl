# ffi_test.jl — no-browser FFI facts + ABI-surface facts for the Julia binding.
#
# Proves Julia drives the engine's flat C ABI directly (via ccall) and that the
# shared engine helpers marshal correctly, plus the browser-free parts of the
# full-feature surface (By/Keys/JSON-encode/Actions/Select shape). Needs only the
# .so (SELENIUM_CORE_LIB). Uses Julia's Test stdlib.
using Test
include("../src/Selenium.jl")
using .Selenium

@testset "Selenium FFI facts" begin
    @test route("get") == "POST /session/:sessionId/url"
    @test route("nope") == ""
    @test errorcode("no such element") == 17
    @test errorcode("") == 0
    @test locator(By.CSS, "div.foo") == "{\"using\":\"css selector\",\"value\":\"div.foo\"}"
    @test occursin("*[id=", locator(By.ID, "main"))

    # By factory (Selenium 4.x shape): returns a Locator carrying strategy+value.
    loc = By.id("hdr")
    @test loc isa Selenium.Locator
    @test loc.strategy == "id"
    @test loc.value == "hdr"
    # class_name maps to the W3C "class name" (not "className").
    @test By.class_name("btn").strategy == "class name"
    @test By.CLASS_NAME == "class name"

    threw = false
    d = WebDriver("http://127.0.0.1:1")
    try
        execute(d, "newSession", "{}")
    catch e
        if e isa Selenium.WebDriverError
            threw = e.code == -1
        end
    end
    @test threw
end

@testset "Keys — W3C PUA code points" begin
    @test codepoint(only(Keys.NULL)) == 0xE000
    @test codepoint(only(Keys.TAB)) == 0xE004
    @test codepoint(only(Keys.ENTER)) == 0xE007
    @test codepoint(only(Keys.ESCAPE)) == 0xE00C
    @test codepoint(only(Keys.F1)) == 0xE031
    @test codepoint(only(Keys.F12)) == 0xE03C
    @test codepoint(only(Keys.META)) == 0xE03D
    # aliases agree with their canonical key.
    @test Keys.BACK_SPACE == Keys.BACKSPACE
    @test Keys.COMMAND == Keys.META
    # a chord holds the modifier then closes with the terminating NULL.
    s = Keys.chord(Keys.CONTROL, "a")
    @test first(s) == only(Keys.CONTROL)
    @test endswith(s, Keys.NULL)
end

@testset "JSON encode (dependency-free)" begin
    enc = Selenium._encode
    @test enc("a\"b") == "\"a\\\"b\""
    @test enc(true) == "true"
    @test enc(42) == "42"
    @test enc(nothing) == "null"
    @test enc(["x", "y"]) == "[\"x\",\"y\"]"
    @test enc(Dict("k" => "v")) == "{\"k\":\"v\"}"
    # RawJson passes through untouched (used for element refs).
    @test enc(Selenium.RawJson("{\"n\":1}")) == "{\"n\":1}"
end

@testset "Actions builder — W3C wire shape (no browser)" begin
    # A click on an element builds a single pointer device with move/down/up.
    d = WebDriver("http://127.0.0.1:1")
    e = Selenium.WebElement(d, "EID")
    a = Actions(d)
    click(a, e)
    built = build(a)
    @test length(built) == 1
    dev = built[1]
    @test dev["type"] == "pointer"
    @test dev["id"] == "mouse"
    acts = dev["actions"]
    @test length(acts) == 3
    @test acts[1]["type"] == "pointerMove"
    @test acts[1]["origin"][Selenium.W3C_ELEMENT_KEY] == "EID"
    @test acts[2]["type"] == "pointerDown"
    @test acts[3]["type"] == "pointerUp"

    # A pause-only sequence emits no device.
    a2 = Actions(d)
    pause(a2, 10)
    @test isempty(build(a2))

    # Mixed devices are length-synced with pauses.
    a3 = Actions(d)
    click(a3, e)         # 3 pointer ticks; key padded to 3
    send_keys(a3, "x")   # +2 key ticks -> 5; pointer padded to 5
    @test length(a3.pointer) == length(a3.key) == 5
    @test length(build(a3)) == 2
end

@testset "context_click / double_click / drag_and_drop shapes" begin
    d = WebDriver("http://127.0.0.1:1")
    e1 = Selenium.WebElement(d, "SRC")
    e2 = Selenium.WebElement(d, "TGT")

    a = double_click(Actions(d), e1)
    acts = build(a)[1]["actions"]
    downs = count(x -> x["type"] == "pointerDown", acts)
    ups = count(x -> x["type"] == "pointerUp", acts)
    @test (downs, ups) == (2, 2)

    a2 = context_click(Actions(d), e1)
    ca = build(a2)[1]["actions"]
    @test ca[2]["button"] == 2

    a3 = drag_and_drop(Actions(d), e1, e2)
    da = build(a3)[1]["actions"]
    @test da[1]["type"] == "pointerMove"
    @test da[1]["origin"][Selenium.W3C_ELEMENT_KEY] == "SRC"
    @test da[2]["type"] == "pointerDown"
    @test da[3]["origin"][Selenium.W3C_ELEMENT_KEY] == "TGT"
    @test da[4]["type"] == "pointerUp"
end

println("PASS: Julia FFI + ABI-surface tests green")
