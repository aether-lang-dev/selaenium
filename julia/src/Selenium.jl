# SeleniumCore.jl — the Julia binding over the shared Aether engine.
#
# Julia's built-in `ccall` invokes the engine's flat C ABI (aether_sel_embed_*)
# DIRECTLY — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is located via SELENIUM_CORE_LIB (an
# absolute path env), so ccall's library handle is that path. This module is the
# idiomatic Julia surface: a `By` set of constants, caller-owned-string handling,
# a typed error, and a `WebDriver` with the W3C operations.
module SeleniumCore

export By, WebDriver, route, errorcode, locator, execute, quit, sessionid

# The engine .so path — SELENIUM_CORE_LIB, or "libselenium_core" on the load path.
const LIB = get(ENV, "SELENIUM_CORE_LIB", "libselenium_core")

# By strategies (the same string values the engine's by_locator expects).
module By
    const ID = "id"
    const NAME = "name"
    const CSS = "css selector"
    const CLASS_NAME = "className"
    const TAG_NAME = "tag name"
    const LINK_TEXT = "link text"
    const PARTIAL_LINK_TEXT = "partial link text"
    const XPATH = "xpath"
end

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

quit(d::WebDriver) = (try execute(d, "quit", "{}") catch end; nothing)

sessionid(d::WebDriver)::String =
    take(ccall((:aether_sel_embed_session_id, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))

close!(d::WebDriver) = ccall((:aether_sel_embed_close, LIB), Cvoid, (Ptr{Cvoid},), d.handle)

end # module
