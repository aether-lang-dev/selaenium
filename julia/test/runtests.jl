# Julia binding test entry point (`julia --project -e 'using Pkg; Pkg.test()'`,
# or `julia --project test/runtests.jl`).
#
# The engine-fetcher tests are pure/offline (a live download is gated on
# SELENIUM_FETCH_LIVE=1) and always run. The FFI tests need the built engine
# (SELENIUM_CORE_LIB pointing at a libselenium_core.<ext>), so they run only when
# that env is set — otherwise they're skipped, keeping the default suite green on
# a box with no engine.
using Test

@testset "Selenium.jl" begin
    include("engine_fetcher_test.jl")

    # ABI-surface guard: pure reflection over the public method table, no engine
    # .so required, so it always runs.
    include("surface_test.jl")

    if haskey(ENV, "SELENIUM_CORE_LIB") && !isempty(ENV["SELENIUM_CORE_LIB"])
        include("ffi_test.jl")
    else
        @info "SELENIUM_CORE_LIB not set — skipping FFI tests (build/fetch the engine to run them)"
    end
end
