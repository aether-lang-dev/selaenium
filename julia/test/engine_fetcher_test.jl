# engine_fetcher_test.jl — the `fetch_engine!` machinery that lets a Julia dev get
# the prebuilt pure-Aether engine from GitHub releases with no Aether toolchain.
# The pure logic (asset naming, cache path, platform mapping, the version pin,
# loader precedence) needs no network. One live download test is gated on
# SELENIUM_FETCH_LIVE=1 so the default suite stays offline/deterministic.
using Test
using SHA: sha256
include("../src/Selenium.jl")
using .Selenium

const F = Selenium.EngineFetcher

@testset "EngineFetcher — offline logic" begin
    @testset "ENGINE_VERSION is a release tag, re-exported" begin
        @test occursin(r"^v\d+\.\d+\.\d+$", F.ENGINE_VERSION)
        @test Selenium.ENGINE_VERSION == F.ENGINE_VERSION
    end

    @testset "asset name matches the release artifact scheme" begin
        # libselenium_core-<tag>-<os>-<arch>.<ext> — exactly what release/build.sh emits.
        @test occursin(
            r"^libselenium_core-v\d+\.\d+\.\d+-(linux|macos|windows)-(x86_64|arm64)\.(so|dylib|dll)$",
            F.asset_name())
        # tag override flows into the asset name.
        @test occursin("v0.7.0", F.asset_name("v0.7.0"))
    end

    @testset "cached path is under the cache dir, keyed by tag" begin
        path = F.cached_path()
        @test startswith(path, F.cache_dir())
        @test occursin(F.ENGINE_VERSION, path)              # keyed by the engine tag
        @test basename(path) == F.library_filename()        # bare filename the loader looks for
        # A different tag lands in a different, tag-keyed dir (survives upgrades).
        @test F.cached_path("v0.7.0") != path
        @test occursin("v0.7.0", F.cached_path("v0.7.0"))
    end

    @testset "cache_dir honors XDG_CACHE_HOME" begin
        old = get(ENV, "XDG_CACHE_HOME", nothing)
        try
            ENV["XDG_CACHE_HOME"] = "/tmp/xdg-probe"
            @test F.cache_dir() == joinpath("/tmp/xdg-probe", "selaenium")
        finally
            old === nothing ? delete!(ENV, "XDG_CACHE_HOME") : (ENV["XDG_CACHE_HOME"] = old)
        end
    end

    @testset "platform mapping is total for this host" begin
        @test F.os_tag() in ("linux", "macos", "windows")
        @test F.arch_tag() in ("x86_64", "arm64")
        @test F.ext() in ("so", "dylib", "dll")
    end

    @testset "loader resolution checks the fetch cache" begin
        # With no env override and a present cached file, _resolve_lib must return
        # exactly the fetcher's cache path — so a fetched engine loads with no config.
        old = get(ENV, "SELENIUM_CORE_LIB", nothing)
        mktempdir() do dir
            xdgold = get(ENV, "XDG_CACHE_HOME", nothing)
            try
                delete!(ENV, "SELENIUM_CORE_LIB")
                ENV["XDG_CACHE_HOME"] = dir
                cached = F.cached_path()
                mkpath(dirname(cached))
                write(cached, "not a real engine, just presence")
                @test Selenium._resolve_lib() == cached
                # An explicit SELENIUM_CORE_LIB still wins over the cache.
                ENV["SELENIUM_CORE_LIB"] = "/some/explicit/libselenium_core.so"
                @test Selenium._resolve_lib() == "/some/explicit/libselenium_core.so"
            finally
                old === nothing ? delete!(ENV, "SELENIUM_CORE_LIB") : (ENV["SELENIUM_CORE_LIB"] = old)
                xdgold === nothing ? delete!(ENV, "XDG_CACHE_HOME") : (ENV["XDG_CACHE_HOME"] = xdgold)
            end
        end
    end

    @testset "checksum_ok verifies file bytes against the sidecar hex" begin
        mktempdir() do dir
            f = joinpath(dir, "blob")
            write(f, "abc")
            want = bytes2hex(sha256("abc"))
            @test F.checksum_ok(f, want)
            @test !F.checksum_ok(f, "deadbeef")
            @test !F.checksum_ok(f, nothing)
            @test !F.checksum_ok(joinpath(dir, "missing"), want)
        end
    end
end

@testset "EngineFetcher — live download (gated)" begin
    if get(ENV, "SELENIUM_FETCH_LIVE", "") != "1"
        @test_skip "set SELENIUM_FETCH_LIVE=1 to hit the network"
    else
        mktempdir() do dir
            old = get(ENV, "XDG_CACHE_HOME", nothing)
            try
                ENV["XDG_CACHE_HOME"] = dir
                path = Selenium.fetch_engine!(force = true)
                @test isfile(path)
                @test filesize(path) > 0
                want = F.expected_sha()
                if want !== nothing
                    @test bytes2hex(sha256(read(path))) == want
                end
                # Idempotent: a second fetch returns the cached path (no error).
                @test Selenium.fetch_engine!() == path
            finally
                old === nothing ? delete!(ENV, "XDG_CACHE_HOME") : (ENV["XDG_CACHE_HOME"] = old)
            end
        end
    end
end
