# ffi_test.jl — no-browser FFI facts for the Julia binding.
#
# Proves Julia drives the engine's flat C ABI directly (via ccall) and that the
# shared engine helpers marshal correctly. Needs only the .so (SELENIUM_CORE_LIB).
# Uses Julia's Test stdlib.
using Test
include("../src/SeleniumCore.jl")
using .SeleniumCore

@testset "SeleniumCore FFI facts" begin
    @test route("get") == "POST /session/:sessionId/url"
    @test route("nope") == ""
    @test errorcode("no such element") == 17
    @test errorcode("") == 0
    @test locator(By.CSS, "div.foo") == "{\"using\":\"css selector\",\"value\":\"div.foo\"}"
    @test occursin("*[id=", locator(By.ID, "main"))

    threw = false
    d = WebDriver("http://127.0.0.1:1")
    try
        execute(d, "newSession", "{}")
    catch e
        if e isa SeleniumCore.WebDriverError
            threw = e.code == -1
        end
    end
    @test threw
end

println("PASS: Julia FFI tests green")
