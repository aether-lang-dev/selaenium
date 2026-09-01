# Selenium.jl — the Julia binding over the shared Aether engine.
#
# Julia's built-in `ccall` invokes the engine's flat C ABI (aether_sel_embed_*)
# DIRECTLY — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is located via SELENIUM_CORE_LIB (an
# absolute path env), so ccall's library handle is that path. This module is the
# idiomatic Julia surface: a `By` factory (Selenium 4.x shape), caller-owned-
# string handling, a typed error, and a `WebDriver` with the W3C operations.
module Selenium

export By, Locator, WebDriver, route, errorcode, locator, execute, findelement,
    quit, sessionid

# The engine .so path — SELENIUM_CORE_LIB, or "libselenium_core" on the load path.
const LIB = get(ENV, "SELENIUM_CORE_LIB", "libselenium_core")

# By: a factory returning a `Locator`, mirroring Java's `By.id("x")`. The
# strategy-name constants remain (By.ID etc.) for the legacy two-arg locator
# helper. CLASS_NAME is the W3C "class name" (not "className"). `Locator` lives
# here and is re-exported from the parent module (see `const Locator` below), so
# a caller writes either `Selenium.Locator` or `Selenium.By.Locator`.
module By
    # A locator carrying a (strategy, value) pair — what `By.id("x")` returns and
    # what `findelement` takes (Selenium 4.x one-arg find).
    struct Locator
        strategy::String
        value::String
    end

    const ID = "id"
    const NAME = "name"
    const CSS = "css selector"
    const CLASS_NAME = "class name"
    const TAG_NAME = "tag name"
    const LINK_TEXT = "link text"
    const PARTIAL_LINK_TEXT = "partial link text"
    const XPATH = "xpath"

    id(value::AbstractString) = Locator("id", value)
    name(value::AbstractString) = Locator("name", value)
    css_selector(value::AbstractString) = Locator("css selector", value)
    class_name(value::AbstractString) = Locator("class name", value)
    tag_name(value::AbstractString) = Locator("tag name", value)
    link_text(value::AbstractString) = Locator("link text", value)
    partial_link_text(value::AbstractString) = Locator("partial link text", value)
    xpath(value::AbstractString) = Locator("xpath", value)
end

# Re-export the locator type at the parent level so `Selenium.Locator` works.
const Locator = By.Locator

struct WebDriverError <: Exception
    message::String
    code::Cint
end

# Take ownership of an engine-returned C string: copy to a Julia String, then
# free it via the engine's allocator (never Libc.free).
function take(ptr::Ptr{Cchar})::String
    ptr == C_NULL && return ""
    s = unsafe_string(ptr)
    ccall((:aether_sel_embed_free_string, LIB), Ptr{Cchar}, (Ptr{Cchar},), ptr)
    return s
end

# ---- pure engine helpers (no session) — shared with every binding ----

route(command::AbstractString)::String =
    take(ccall((:aether_sel_embed_route, LIB), Ptr{Cchar}, (Cstring,), command))

errorcode(w3cerror::AbstractString)::Cint =
    ccall((:aether_sel_embed_error_code, LIB), Cint, (Cstring,), w3cerror)

locator(by::AbstractString, value::AbstractString)::String =
    take(ccall((:aether_sel_embed_by_locator, LIB), Ptr{Cchar}, (Cstring, Cstring), by, value))

# ---- session ----

mutable struct WebDriver
    handle::Ptr{Cvoid}
end

# Open a session bound to a remote-end URL. No I/O until execute("newSession").
function WebDriver(commandexecutor::AbstractString)
    h = ccall((:aether_sel_embed_open, LIB), Ptr{Cvoid}, (Cstring,), commandexecutor)
    WebDriver(h)
end

# Run a command by name with JSON params; return the result value (raw JSON),
# throwing a typed WebDriverError on a protocol/transport error.
function execute(d::WebDriver, name::AbstractString, params::AbstractString = "{}")::String
    rc = ccall((:aether_sel_embed_execute, LIB), Cint, (Ptr{Cvoid}, Cstring, Cstring), d.handle, name, params)
    if rc != 0
        msg = take(ccall((:aether_sel_embed_last_error, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))
        code = ccall((:aether_sel_embed_last_error_code, LIB), Cint, (Ptr{Cvoid},), d.handle)
        throw(WebDriverError(msg, (rc == -1 && code == 0) ? Cint(-1) : code))
    end
    return take(ccall((:aether_sel_embed_last_value, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))
end

const W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

# Pull the element-reference id out of a findElement value JSON string, which
# looks like {"element-6066-...":"<id>"}. Textual extraction keeps the binding
# dependency-free (no JSON package) for the common case.
function _extract_element_id(v::AbstractString)::Union{String,Nothing}
    needle = "\"" * W3C_ELEMENT_KEY * "\":\""
    r = findfirst(needle, v)
    r === nothing && return nothing
    rest = v[(last(r) + 1):end]
    stop = findfirst('"', rest)
    stop === nothing && return nothing
    return rest[1:(prevind(rest, stop))]
end

# Find one element by a `By` locator (Selenium 4.x one-arg find):
#   findelement(driver, Selenium.By.id("hdr"))
# Returns the opaque W3C element id string; throws WebDriverError(17) when the
# response carries no element reference.
function findelement(d::WebDriver, loc::Locator)::String
    params = locator(loc.strategy, loc.value)
    v = execute(d, "findElement", params)
    eid = _extract_element_id(v)
    eid === nothing && throw(WebDriverError("element reference key missing", Cint(17)))
    return eid
end

quit(d::WebDriver) = (try execute(d, "quit", "{}") catch end; nothing)

sessionid(d::WebDriver)::String =
    take(ccall((:aether_sel_embed_session_id, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))

close!(d::WebDriver) = ccall((:aether_sel_embed_close, LIB), Cvoid, (Ptr{Cvoid},), d.handle)

end # module
