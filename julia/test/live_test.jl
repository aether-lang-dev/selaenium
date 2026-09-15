# live_test.jl — LIVE browser facts for the Julia binding.
#
# ffi_test.jl proves the shadow finders and the firefox factory EXIST; that stays
# green even when the code behind them is broken. This drives real browsers
# through the engine so the shadow-DOM path and firefox() are actually executed.
#
# Both legs self-orchestrate via the engine's driver ABI (resolve_driver +
# ensure_driver, docs/Driver-Orchestration-ABI.md) — no driver on PATH, no Grid —
# and use `data:` pages, so no content server is needed.
using Test
include("../src/Selenium.jl")
using .Selenium

# Empty resolve means the engine genuinely could not provide the driver; that is
# the only reason either leg is allowed not to run.
function driver_for(browser::AbstractString)
    isempty(resolve_driver(browser)) && return nothing
    ensure_driver(browser, "", 20_000)
end

@testset "live chrome shadow DOM" begin
    proc = driver_for("chrome")
    if proc === nothing
        @warn "SKIPPED: engine cannot resolve a chromedriver"
    else
        d = headless_chrome(driver_url(proc))
        try
            @test !isempty(sessionid(d))
            get_url(d, "data:text/html,<!doctype html><title>JuliaLive</title>" *
                       "<h1 id=\"hdr\">plain</h1><div id=\"host\"></div>")
            @test title(d) == "JuliaLive"

            # Host an open shadow root, then reach an element INSIDE it: the
            # getShadowRoot -> findElementFromShadowRoot round trip, for real.
            execute_script(d, "var h=document.getElementById('host');" *
                              "var r=h.attachShadow({mode:'open'});" *
                              "r.innerHTML='<p id=\"sinner\">julia-shadow</p>';")

            sr = shadow_root(find_element(d, By.id("host")))
            @test text(find_element(sr, By.css_selector("#sinner"))) == "julia-shadow"
            @test length(find_elements(sr, By.css_selector("p"))) == 1

            # A non-host element has no shadow root: W3C code 19.
            @test_throws WebDriverError shadow_root(find_element(d, By.id("hdr")))
        finally
            quit(d)
            stop_driver(proc)
        end
    end
end

@testset "live firefox" begin
    proc = driver_for("firefox")
    if proc === nothing
        @warn "SKIPPED: engine cannot resolve a geckodriver"
    else
        d = headless_firefox(driver_url(proc))
        try
            @test !isempty(sessionid(d))
            get_url(d, "data:text/html,<!doctype html><title>Aether Firefox</title>" *
                       "<h1 id=\"hdr\">Hello FF</h1>")
            @test title(d) == "Aether Firefox"
            @test text(find_element(d, By.id("hdr"))) == "Hello FF"
        finally
            quit(d)
            stop_driver(proc)
        end
    end
end
