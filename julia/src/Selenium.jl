# Selenium.jl — the Julia binding over the shared Aether engine.
#
# Julia's built-in `ccall` invokes the engine's flat C ABI (aether_sel_embed_*)
# DIRECTLY — no glue, no second copy of the marshalling rules to drift from
# selenium_core/embed.ae. The engine .so is located via SELENIUM_CORE_LIB (an
# absolute path env), so ccall's library handle is that path. This module is the
# idiomatic Julia surface: a `By` factory (Selenium 4.x shape), caller-owned-
# string handling, a typed error, and a `WebDriver` with the W3C operations.
#
# The full-feature surface mirrors the reference Rust client (rust/src/*.rs):
# navigation, elements (a `WebElement` handle), windows, frames, alerts, cookies,
# timeouts, screenshots/print, script, a `Select` dropdown helper, an `Actions`
# builder, explicit `Wait`s, the `Keys` constants, driver orchestration
# (resolve/launch/ensure + local_chrome), and WebDriver-BiDi. Every W3C command
# is issued by name with JSON params through the one `execute` seam, so there is
# no second copy of the protocol here.
module Selenium

export By, Locator, WebDriver, WebElement, Keys, Select, Actions, Wait,
    BiDi, BidiEvent, TlsConfig, WebDriverError,
    route, errorcode, locator, execute,
    # navigation
    get_url, current_url, title, page_source, back, forward, refresh,
    # elements
    findelement, find_element, find_elements, active_element, exists,
    find_relative, find_relative_count,
    # element ops
    click, clear, send_keys, text, tag_name, is_displayed, is_enabled,
    is_selected, get_attribute, get_dom_attribute, get_property, rect,
    css_value, value_of_css_property, submit, element_screenshot_base64,
    # script
    execute_script, execute_async_script,
    # windows
    window_handles, current_window_handle, switch_to_window, set_window_rect,
    get_window_rect, maximize_window, minimize_window, fullscreen_window,
    new_window, close_window,
    # frames
    switch_to_frame, switch_to_parent_frame, switch_to_default_content,
    # alerts
    accept_alert, dismiss_alert, alert_text, send_alert_text, alert_present,
    # cookies
    add_cookie, get_cookies, get_cookie, delete_cookie, delete_all_cookies,
    # actions / timeouts / screenshots
    perform_actions, clear_actions, set_timeouts, set_page_load_timeout,
    set_script_timeout, implicitly_wait, screenshot_base64, print_pdf,
    # select
    options, all_selected_options, first_selected_option, select_by_index,
    select_by_value, select_by_visible_text, deselect_all, is_multiple,
    # actions builder
    move_to_element, context_click, double_click, click_and_hold, release,
    drag_and_drop, key_down, key_up, pause, perform, build,
    # waits
    wait, until, until_not, poll_every, wait_for_element, wait_for_visible,
    wait_for_clickable, wait_until_gone, wait_for_title_is,
    wait_for_title_contains, wait_for_url_is, wait_for_url_contains,
    # keys
    chord,
    # lifecycle / driver mgmt
    quit, sessionid, chrome, chrome_tls, headless_chrome, local_chrome,
    resolve_driver, launch_driver, ensure_driver,
    # bidi
    bidi, bidi_available, subscribe, unsubscribe, next_event, command,
    get_tree, top_context, evaluate, evaluate_value, navigate,
    add_intercept, remove_intercept, continue_request, fail_request,
    provide_response, continue_with_auth, set_cache_behavior, event_request_id,
    lost_events

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

# ---- Keys — W3C Unicode private-use key code points (W3C §17.4.2) ----
# Mirrors mainstream Selenium's `Keys`. Each constant is a one-character String
# (a single scalar in U+E000..=U+E03D). Append one to a string, or use
# `Keys.chord` to build a modifier chord.
module Keys
    const NULL = ""
    const CANCEL = ""
    const HELP = ""
    const BACKSPACE = ""
    const BACK_SPACE = BACKSPACE
    const TAB = ""
    const CLEAR = ""
    const RETURN = ""
    const ENTER = ""
    const SHIFT = ""
    const LEFT_SHIFT = SHIFT
    const CONTROL = ""
    const LEFT_CONTROL = CONTROL
    const ALT = ""
    const LEFT_ALT = ALT
    const PAUSE = ""
    const ESCAPE = ""
    const SPACE = ""
    const PAGE_UP = ""
    const PAGE_DOWN = ""
    const END = ""
    const HOME = ""
    const LEFT = ""
    const ARROW_LEFT = LEFT
    const UP = ""
    const ARROW_UP = UP
    const RIGHT = ""
    const ARROW_RIGHT = RIGHT
    const DOWN = ""
    const ARROW_DOWN = DOWN
    const INSERT = ""
    const DELETE = ""
    const SEMICOLON = ""
    const EQUALS = ""

    const NUMPAD0 = ""
    const NUMPAD1 = ""
    const NUMPAD2 = ""
    const NUMPAD3 = ""
    const NUMPAD4 = ""
    const NUMPAD5 = ""
    const NUMPAD6 = ""
    const NUMPAD7 = ""
    const NUMPAD8 = ""
    const NUMPAD9 = ""
    const MULTIPLY = ""
    const ADD = ""
    const SEPARATOR = ""
    const SUBTRACT = ""
    const DECIMAL = ""
    const DIVIDE = ""

    const F1 = ""
    const F2 = ""
    const F3 = ""
    const F4 = ""
    const F5 = ""
    const F6 = ""
    const F7 = ""
    const F8 = ""
    const F9 = ""
    const F10 = ""
    const F11 = ""
    const F12 = ""

    const META = ""
    const COMMAND = ""

    # A modifier chord: `modifier` held while `text` is typed, then closed by the
    # terminating NULL the protocol uses to release held modifiers — e.g.
    # `Keys.chord(Keys.CONTROL, "a")` for select-all. The classic `Keys.chord`.
    chord(modifier::AbstractString, text::AbstractString) = modifier * text * NULL
end

struct WebDriverError <: Exception
    message::String
    code::Cint
end

# ---- minimal JSON encode (dependency-free) --------------------------------
# The binding stays free of a JSON package (matching the original design). We
# encode only the value shapes the protocol needs: nothing/String/Bool/Real and
# Vector/Dict of those. `RawJson` wraps an already-encoded JSON fragment (e.g.
# the {"using","value"} locator the engine returns) so it passes through
# untouched.
struct RawJson
    json::String
end

function _escape(s::AbstractString)
    io = IOBuffer()
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c < '\x20'
            print(io, "\\u", lpad(string(UInt16(c); base = 16), 4, '0'))
        else
            print(io, c)
        end
    end
    String(take!(io))
end

_encode(::Nothing) = "null"
_encode(x::RawJson) = x.json
_encode(x::Bool) = x ? "true" : "false"
_encode(x::Integer) = string(x)
_encode(x::Real) = (isinteger(x) ? string(Int(x)) : string(x))
_encode(x::AbstractString) = "\"" * _escape(x) * "\""
_encode(x::AbstractVector) = "[" * join((_encode(v) for v in x), ",") * "]"
function _encode(x::AbstractDict)
    parts = String[]
    for (k, v) in x
        push!(parts, "\"" * _escape(string(k)) * "\":" * _encode(v))
    end
    return "{" * join(parts, ",") * "}"
end

# ---- minimal JSON value reads (textual, dependency-free) ------------------
# For the common scalar reads (a JSON string result, a boolean) we extract
# textually — enough for get_url/title/text/... where the engine strips the W3C
# {"value":...} envelope and the value is a bare JSON scalar. Callers needing
# rich structure receive the raw JSON string (e.g. get_cookies, rect).

# Unwrap a bare JSON string result ("\"foo\"" -> "foo"); non-string results pass
# through as-is (so numbers/objects are still readable by the caller).
function _as_string(v::AbstractString)::String
    s = strip(v)
    if length(s) >= 2 && startswith(s, "\"") && endswith(s, "\"")
        inner = s[2:prevind(s, lastindex(s))]
        return _unescape(inner)
    end
    return String(s)
end

function _unescape(s::AbstractString)::String
    io = IOBuffer()
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if c == '\\' && i < lastindex(s)
            j = nextind(s, i)
            e = s[j]
            if e == 'n'
                print(io, '\n')
            elseif e == 't'
                print(io, '\t')
            elseif e == 'r'
                print(io, '\r')
            elseif e == '"'
                print(io, '"')
            elseif e == '\\'
                print(io, '\\')
            elseif e == '/'
                print(io, '/')
            else
                print(io, e)
            end
            i = nextind(s, j)
        else
            print(io, c)
            i = nextind(s, i)
        end
    end
    return String(take!(io))
end

_as_bool(v::AbstractString)::Bool = occursin("true", v)

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

# ---- TLS config ----

# TLS trust configuration for a session, applied on the handle before
# newSession. Defaults to the platform trust store with verification on.
struct TlsConfig
    ca_path::Union{String,Nothing}
    insecure::Bool
end
TlsConfig(; ca_path::Union{String,Nothing} = nothing, insecure::Bool = false) =
    TlsConfig(ca_path, insecure)

# ---- session ----

mutable struct WebDriver
    handle::Ptr{Cvoid}
    ws_url::String
    bidi::Any        # a BiDi (opened lazily) or nothing
    driver::Any      # a DriverProcess owned by this session, or nothing
end

# Open a session bound to a remote-end URL. No I/O until execute("newSession").
function WebDriver(commandexecutor::AbstractString)
    h = ccall((:aether_sel_embed_open, LIB), Ptr{Cvoid}, (Cstring,), commandexecutor)
    WebDriver(h, "", nothing, nothing)
end

# Run a command by name with JSON params; return the result value (raw JSON),
# throwing a typed WebDriverError on a protocol/transport error. `params` may be
# a pre-encoded JSON string or any encodable value (Dict/Vector/scalar/RawJson).
function execute(d::WebDriver, name::AbstractString, params = "{}")::String
    pj = params isa AbstractString ? String(params) : _encode(params)
    rc = ccall((:aether_sel_embed_execute, LIB), Cint, (Ptr{Cvoid}, Cstring, Cstring), d.handle, name, pj)
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

# Pull every element-reference id out of a findElements value JSON array.
function _extract_element_ids(v::AbstractString)::Vector{String}
    ids = String[]
    needle = "\"" * W3C_ELEMENT_KEY * "\":\""
    rest = v
    while true
        r = findfirst(needle, rest)
        r === nothing && break
        rest = rest[(last(r) + 1):end]
        stop = findfirst('"', rest)
        stop === nothing && break
        push!(ids, rest[1:(prevind(rest, stop))])
        rest = rest[(nextind(rest, stop)):end]
    end
    return ids
end

# ---- WebElement — a remote element handle ---------------------------------

struct WebElement
    driver::WebDriver
    id::String
end

# Element-scoped command: inject this element's id as the `:id` path param.
function _exec(e::WebElement, command::AbstractString, params::AbstractDict = Dict{String,Any}())::String
    p = Dict{String,Any}(params)
    p["id"] = e.id
    return execute(e.driver, command, p)
end

# The W3C element-reference object for this element (for actions/frame ids).
_ref(e::WebElement) = RawJson(_encode(Dict(W3C_ELEMENT_KEY => e.id)))

# Find one element by a `By` locator (Selenium 4.x one-arg find). Returns the
# opaque W3C element id string; throws WebDriverError(17) when the response
# carries no element reference. Retained under its original name `findelement`.
function findelement(d::WebDriver, loc::Locator)::String
    params = locator(loc.strategy, loc.value)
    v = execute(d, "findElement", params)
    eid = _extract_element_id(v)
    eid === nothing && throw(WebDriverError("element reference key missing", Cint(17)))
    return eid
end

# `find_element` returns a WebElement handle (mainstream shape).
function find_element(d::WebDriver, loc::Locator)::WebElement
    WebElement(d, findelement(d, loc))
end

function find_elements(d::WebDriver, loc::Locator)::Vector{WebElement}
    v = execute(d, "findElements", locator(loc.strategy, loc.value))
    return [WebElement(d, id) for id in _extract_element_ids(v)]
end

# The active (focused) element (getActiveElement).
function active_element(d::WebDriver)::WebElement
    v = execute(d, "getActiveElement", "{}")
    eid = _extract_element_id(v)
    eid === nothing && throw(WebDriverError("element reference key missing", Cint(17)))
    return WebElement(d, eid)
end

# True if at least one element matching `loc` is present right now (no wait). A
# clean not-found resolves to false; a transport error still throws.
function exists(d::WebDriver, loc::Locator)::Bool
    try
        find_element(d, loc)
        return true
    catch e
        e isa WebDriverError && e.code == 17 && return false
        rethrow()
    end
end

# child find (element-scoped). The engine's by_locator already yields the correct
# {"using":..,"value":..} object; splice the element id into it directly (string
# merge) so no re-parse of the value (which may carry escapes) is needed.
function _child_find_params(e::WebElement, loc::Locator)::String
    j = strip(locator(loc.strategy, loc.value))   # "{...}"
    inner = j[nextind(j, firstindex(j)):prevind(j, lastindex(j))]  # drop the braces
    return "{\"id\":\"" * e.id * "\"," * inner * "}"
end

function find_element(e::WebElement, loc::Locator)::WebElement
    v = execute(e.driver, "findChildElement", _child_find_params(e, loc))
    eid = _extract_element_id(v)
    eid === nothing && throw(WebDriverError("element reference key missing", Cint(17)))
    return WebElement(e.driver, eid)
end

function find_elements(e::WebElement, loc::Locator)::Vector{WebElement}
    v = execute(e.driver, "findChildElements", _child_find_params(e, loc))
    return [WebElement(e.driver, id) for id in _extract_element_ids(v)]
end

# ---- relative locators ----

# Elements matching `base_css` filtered by spatial relation, nearest first. Each
# filter is a Dict `Dict("kind"=>"above"|"below"|"left"|"right"|"near",
# "sel"=>"<css>")` (near also accepts "dist"). Returns the matching elements.
function find_relative(d::WebDriver, base_css::AbstractString, filters::AbstractVector)::Vector{WebElement}
    fj = _encode(collect(filters))
    rc = ccall((:aether_sel_embed_find_relative, LIB), Cint,
        (Ptr{Cvoid}, Cstring, Cstring), d.handle, base_css, fj)
    v = _atom_result(d, rc)
    return [WebElement(d, id) for id in _extract_element_ids(v)]
end

function find_relative_count(d::WebDriver, base_css::AbstractString, filters::AbstractVector)::Int
    return length(find_relative(d, base_css, filters))
end

# Drain last_value after an atom call, mapping rc != 0 to a typed error exactly
# as execute does.
function _atom_result(d::WebDriver, rc::Cint)::String
    if rc != 0
        msg = take(ccall((:aether_sel_embed_last_error, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))
        code = ccall((:aether_sel_embed_last_error_code, LIB), Cint, (Ptr{Cvoid},), d.handle)
        throw(WebDriverError(msg, (rc == -1 && code == 0) ? Cint(-1) : code))
    end
    return take(ccall((:aether_sel_embed_last_value, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))
end

# ---- navigation ----
# `get_url` (not `get`, which is Base.get) navigates the browser to `url`.
function get_url(d::WebDriver, url::AbstractString)
    execute(d, "get", Dict("url" => url))
    nothing
end
current_url(d::WebDriver)::String = _as_string(execute(d, "getCurrentUrl", "{}"))
title(d::WebDriver)::String = _as_string(execute(d, "getTitle", "{}"))
page_source(d::WebDriver)::String = _as_string(execute(d, "getPageSource", "{}"))
back(d::WebDriver) = (execute(d, "goBack", "{}"); nothing)
forward(d::WebDriver) = (execute(d, "goForward", "{}"); nothing)
refresh(d::WebDriver) = (execute(d, "refresh", "{}"); nothing)

# ---- script ----
execute_script(d::WebDriver, script::AbstractString, args::AbstractVector = Any[])::String =
    execute(d, "executeScript", Dict("script" => script, "args" => collect(args)))
execute_async_script(d::WebDriver, script::AbstractString, args::AbstractVector = Any[])::String =
    execute(d, "executeAsyncScript", Dict("script" => script, "args" => collect(args)))

# ---- element ops ----
click(e::WebElement) = (_exec(e, "clickElement"); nothing)
clear(e::WebElement) = (_exec(e, "clearElement"); nothing)
function send_keys(e::WebElement, text::AbstractString)
    chars = [string(c) for c in text]
    _exec(e, "sendKeysToElement", Dict{String,Any}("text" => text, "value" => chars))
    nothing
end
text(e::WebElement)::String = _as_string(_exec(e, "getElementText"))
tag_name(e::WebElement)::String = _as_string(_exec(e, "getElementTagName"))

# isDisplayed atom (the visibility algorithm, run in-page by the engine).
function is_displayed(e::WebElement)::Bool
    rc = ccall((:aether_sel_embed_is_displayed, LIB), Cint,
        (Ptr{Cvoid}, Cstring), e.driver.handle, e.id)
    return _as_bool(_atom_result(e.driver, rc))
end

# classic getAttribute(name) via the shared engine atom; nothing when absent.
function get_attribute(e::WebElement, name::AbstractString)::Union{String,Nothing}
    rc = ccall((:aether_sel_embed_get_attribute, LIB), Cint,
        (Ptr{Cvoid}, Cstring, Cstring), e.driver.handle, e.id, name)
    v = _atom_result(e.driver, rc)
    (isempty(v) || strip(v) == "null") && return nothing
    return _as_string(v)
end

get_dom_attribute(e::WebElement, name::AbstractString)::String =
    _exec(e, "getDomAttribute", Dict("name" => name))
get_property(e::WebElement, name::AbstractString)::String =
    _exec(e, "getElementProperty", Dict("name" => name))
is_enabled(e::WebElement)::Bool = _as_bool(_exec(e, "isElementEnabled"))
is_selected(e::WebElement)::Bool = _as_bool(_exec(e, "isElementSelected"))
rect(e::WebElement)::String = _exec(e, "getElementRect")

# computed CSS property value (getElementValueOfCssProperty).
css_value(e::WebElement, prop::AbstractString)::String =
    _as_string(_exec(e, "getElementValueOfCssProperty", Dict("name" => prop)))
# classic-Selenium-named alias.
value_of_css_property(e::WebElement, prop::AbstractString)::String = css_value(e, prop)

# a PNG screenshot of just this element (base64).
element_screenshot_base64(e::WebElement)::String =
    _as_string(_exec(e, "takeElementScreenshot"))

# Submit the enclosing <form>. W3C removed the dedicated submit endpoint, so —
# like the reference binding — walk up to the form and requestSubmit()/submit()
# via an injected script.
const _SUBMIT_SCRIPT = "var e=arguments[0];var f=e.form||e.closest('form');" *
    "if(!f){throw new Error('Element is not within a form');}" *
    "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"
function submit(e::WebElement)
    execute_script(e.driver, _SUBMIT_SCRIPT, [_ref(e)])
    nothing
end

# ---- windows ----
window_handles(d::WebDriver)::Vector{String} = _extract_string_array(execute(d, "getWindowHandles", "{}"))
current_window_handle(d::WebDriver)::String = _as_string(execute(d, "getCurrentWindowHandle", "{}"))
switch_to_window(d::WebDriver, handle::AbstractString) = (execute(d, "switchToWindow", Dict("handle" => handle)); nothing)
set_window_rect(d::WebDriver, rect::AbstractDict)::String = execute(d, "setWindowRect", rect)
get_window_rect(d::WebDriver)::String = execute(d, "getWindowRect", "{}")
maximize_window(d::WebDriver)::String = execute(d, "maximizeWindow", "{}")
minimize_window(d::WebDriver)::String = execute(d, "minimizeWindow", "{}")
fullscreen_window(d::WebDriver)::String = execute(d, "fullscreenWindow", "{}")

# newWindow: "tab" or "window" hint; returns the new window handle.
function new_window(d::WebDriver, type_hint::AbstractString = "tab")::String
    v = execute(d, "newWindow", Dict("type" => type_hint))
    m = match(r"\"handle\":\"([^\"]*)\"", v)
    return m === nothing ? "" : m.captures[1]
end

# close the current window/tab; returns the remaining handles.
close_window(d::WebDriver)::Vector{String} = _extract_string_array(execute(d, "close", "{}"))

# Extract a JSON array of strings textually.
function _extract_string_array(v::AbstractString)::Vector{String}
    out = String[]
    for m in eachmatch(r"\"((?:[^\"\\]|\\.)*)\"", v)
        push!(out, _unescape(m.captures[1]))
    end
    return out
end

# ---- frames ----
# switch_to_frame accepts an Integer index, a WebElement, or nothing (top).
function switch_to_frame(d::WebDriver, frame::Integer)
    execute(d, "switchToFrame", Dict("id" => Int(frame)))
    nothing
end
function switch_to_frame(d::WebDriver, frame::WebElement)
    execute(d, "switchToFrame", Dict("id" => _ref(frame)))
    nothing
end
function switch_to_frame(d::WebDriver, ::Nothing)
    execute(d, "switchToFrame", Dict("id" => nothing))
    nothing
end
switch_to_parent_frame(d::WebDriver) = (execute(d, "switchToFrameParent", "{}"); nothing)
switch_to_default_content(d::WebDriver) = switch_to_frame(d, nothing)

# ---- alerts ----
accept_alert(d::WebDriver) = (execute(d, "acceptAlert", "{}"); nothing)
dismiss_alert(d::WebDriver) = (execute(d, "dismissAlert", "{}"); nothing)
alert_text(d::WebDriver)::String = _as_string(execute(d, "getAlertText", "{}"))
send_alert_text(d::WebDriver, text::AbstractString) = (execute(d, "setAlertValue", Dict("text" => text)); nothing)
# True if a dialog is present (probing via getAlertText); 15 = no such alert.
function alert_present(d::WebDriver)::Bool
    try
        execute(d, "getAlertText", "{}")
        return true
    catch e
        e isa WebDriverError && e.code == 15 && return false
        rethrow()
    end
end

# ---- cookies ----
add_cookie(d::WebDriver, cookie::AbstractDict) = (execute(d, "addCookie", Dict("cookie" => cookie)); nothing)
get_cookies(d::WebDriver)::String = execute(d, "getCookies", "{}")
get_cookie(d::WebDriver, name::AbstractString)::String = execute(d, "getCookie", Dict("name" => name))
delete_cookie(d::WebDriver, name::AbstractString) = (execute(d, "deleteCookie", Dict("name" => name)); nothing)
delete_all_cookies(d::WebDriver) = (execute(d, "deleteAllCookies", "{}"); nothing)

# ---- actions / timeouts / screenshots ----
perform_actions(d::WebDriver, actions::AbstractVector) = (execute(d, "actions", Dict("actions" => collect(actions))); nothing)
clear_actions(d::WebDriver) = (execute(d, "clearActions", "{}"); nothing)
set_timeouts(d::WebDriver, timeouts::AbstractDict) = (execute(d, "setTimeout", timeouts); nothing)
set_page_load_timeout(d::WebDriver, ms::Integer) = (execute(d, "setTimeout", Dict("pageLoad" => Int(ms))); nothing)
set_script_timeout(d::WebDriver, ms::Integer) = (execute(d, "setTimeout", Dict("script" => Int(ms))); nothing)
implicitly_wait(d::WebDriver, ms::Integer) = (execute(d, "setTimeout", Dict("implicit" => Int(ms))); nothing)
screenshot_base64(d::WebDriver)::String = _as_string(execute(d, "screenshot", "{}"))

# printPage -> PDF (base64). `options` is the W3C print-options object or nothing.
function print_pdf(d::WebDriver, options::Union{AbstractDict,Nothing} = nothing)::String
    params = options === nothing ? Dict{String,Any}() : options
    return _as_string(execute(d, "printPage", params))
end

# ---- Select — <select> dropdown helper ------------------------------------
struct Select
    element::WebElement
    is_multiple::Bool
    function Select(element::WebElement)
        tg = lowercase(tag_name(element))
        tg == "select" || throw(WebDriverError("Select only works on <select> elements, not <$tg>", Cint(0)))
        multi = get_attribute(element, "multiple")
        multiple = multi !== nothing && !isempty(multi) && multi != "false"
        new(element, multiple)
    end
end

is_multiple(s::Select)::Bool = s.is_multiple
options(s::Select)::Vector{WebElement} = find_elements(s.element, By.tag_name("option"))
all_selected_options(s::Select)::Vector{WebElement} = [o for o in options(s) if is_selected(o)]
function first_selected_option(s::Select)::WebElement
    for o in options(s)
        is_selected(o) && return o
    end
    throw(WebDriverError("no option is selected", Cint(17)))
end

# Click an option to select it, but only if not already selected (a second
# click would toggle a multi-select off). Mirrors the reference `_select`.
function _select_option(o::WebElement)
    is_selected(o) || click(o)
    nothing
end

function select_by_visible_text(s::Select, txt::AbstractString)
    for o in options(s)
        if text(o) == txt
            return _select_option(o)
        end
    end
    throw(WebDriverError("no option with visible text $(repr(txt))", Cint(17)))
end
function select_by_value(s::Select, value::AbstractString)
    for o in options(s)
        va = get_attribute(o, "value")
        if va !== nothing && va == value
            return _select_option(o)
        end
    end
    throw(WebDriverError("no option with value $(repr(value))", Cint(17)))
end
function select_by_index(s::Select, index::Integer)
    opts = options(s)
    (index < 0 || index >= length(opts)) && throw(WebDriverError("no option at index $index", Cint(17)))
    _select_option(opts[index + 1])  # 0-based to match mainstream
end
function deselect_all(s::Select)
    s.is_multiple || throw(WebDriverError("deselect_all only makes sense on a multi-select", Cint(0)))
    for o in options(s)
        is_selected(o) && click(o)
    end
    nothing
end

# ---- Actions — fluent W3C action builder ----------------------------------
# Queue pointer/key gestures, then perform(). Each device sub-array is emitted
# only when it holds a real (non-pause) action, matching the reference.
mutable struct Actions
    driver::WebDriver
    pointer::Vector{Any}
    key::Vector{Any}
    Actions(d::WebDriver) = new(d, Any[], Any[])
end

_pause_tick(ms::Integer) = Dict{String,Any}("type" => "pause", "duration" => Int(ms))
_move_to(id::AbstractString) = Dict{String,Any}(
    "type" => "pointerMove", "duration" => 100, "x" => 0, "y" => 0,
    "origin" => Dict(W3C_ELEMENT_KEY => id))
_button_down(b::Integer) = Dict{String,Any}("type" => "pointerDown", "button" => Int(b))
_button_up(b::Integer) = Dict{String,Any}("type" => "pointerUp", "button" => Int(b))
_key_event(kind::AbstractString, ch::AbstractString) = Dict{String,Any}("type" => kind, "value" => ch)
_is_pause(a) = get(a, "type", "") == "pause"

# W3C requires each device's action list to be the same length; pad the shorter
# with zero-duration pauses so ticks stay aligned. Mirrors `_sync_lengths`.
function _sync_lengths!(a::Actions)
    n = max(length(a.pointer), length(a.key))
    while length(a.pointer) < n
        push!(a.pointer, _pause_tick(0))
    end
    while length(a.key) < n
        push!(a.key, _pause_tick(0))
    end
    a
end

function move_to_element(a::Actions, e::WebElement)
    push!(a.pointer, _move_to(e.id)); _sync_lengths!(a); a
end
function click(a::Actions, e::Union{WebElement,Nothing} = nothing)
    e !== nothing && push!(a.pointer, _move_to(e.id))
    push!(a.pointer, _button_down(0)); push!(a.pointer, _button_up(0)); _sync_lengths!(a); a
end
function context_click(a::Actions, e::Union{WebElement,Nothing} = nothing)
    e !== nothing && push!(a.pointer, _move_to(e.id))
    push!(a.pointer, _button_down(2)); push!(a.pointer, _button_up(2)); _sync_lengths!(a); a
end
function double_click(a::Actions, e::Union{WebElement,Nothing} = nothing)
    e !== nothing && push!(a.pointer, _move_to(e.id))
    for _ in 1:2
        push!(a.pointer, _button_down(0)); push!(a.pointer, _button_up(0))
    end
    _sync_lengths!(a); a
end
function click_and_hold(a::Actions, e::Union{WebElement,Nothing} = nothing)
    e !== nothing && push!(a.pointer, _move_to(e.id))
    push!(a.pointer, _button_down(0)); _sync_lengths!(a); a
end
function release(a::Actions, e::Union{WebElement,Nothing} = nothing)
    e !== nothing && push!(a.pointer, _move_to(e.id))
    push!(a.pointer, _button_up(0)); _sync_lengths!(a); a
end
function drag_and_drop(a::Actions, source::WebElement, target::WebElement)
    push!(a.pointer, _move_to(source.id)); push!(a.pointer, _button_down(0))
    push!(a.pointer, _move_to(target.id)); push!(a.pointer, _button_up(0))
    _sync_lengths!(a); a
end
function key_down(a::Actions, key::AbstractString)
    push!(a.key, _key_event("keyDown", key)); _sync_lengths!(a); a
end
function key_up(a::Actions, key::AbstractString)
    push!(a.key, _key_event("keyUp", key)); _sync_lengths!(a); a
end
function send_keys(a::Actions, text::AbstractString)
    for ch in text
        push!(a.key, _key_event("keyDown", string(ch)))
        push!(a.key, _key_event("keyUp", string(ch)))
    end
    _sync_lengths!(a); a
end
function pause(a::Actions, ms::Integer)
    push!(a.pointer, _pause_tick(ms)); _sync_lengths!(a); a
end

# The W3C actions array assembled from the two device lists.
function build(a::Actions)::Vector{Any}
    out = Any[]
    if any(x -> !_is_pause(x), a.pointer)
        push!(out, Dict{String,Any}(
            "type" => "pointer", "id" => "mouse",
            "parameters" => Dict("pointerType" => "mouse"),
            "actions" => a.pointer))
    end
    if any(x -> !_is_pause(x), a.key)
        push!(out, Dict{String,Any}(
            "type" => "key", "id" => "keyboard", "actions" => a.key))
    end
    return out
end

# Post the queued gestures as one `actions` command (no-op if only pauses).
function perform(a::Actions)
    acts = build(a)
    isempty(acts) && return nothing
    perform_actions(a.driver, acts)
    nothing
end

# ---- Wait — explicit waits ------------------------------------------------
const POLL_INTERVAL_S = 0.5

mutable struct Wait
    driver::WebDriver
    timeout_s::Float64
    poll_s::Float64
    Wait(d::WebDriver, timeout_s::Real) = new(d, Float64(timeout_s), POLL_INTERVAL_S)
end

wait(d::WebDriver, timeout_s::Real)::Wait = Wait(d, timeout_s)
function poll_every(w::Wait, interval_s::Real)::Wait
    w.poll_s = interval_s <= 0 ? POLL_INTERVAL_S : Float64(interval_s)
    return w
end

# Poll condition(driver) until it returns true; a NoSuchElement (17) is swallowed
# and retried; any other error propagates; on timeout, WebDriverError(21).
function until(w::Wait, condition)
    deadline = time() + w.timeout_s
    while true
        try
            condition(w.driver) && return nothing
        catch e
            (e isa WebDriverError && e.code == 17) || rethrow()
        end
        time() >= deadline && throw(WebDriverError("waited $(w.timeout_s)s for condition", Cint(21)))
        sleep(w.poll_s)
    end
end

# Poll until condition returns false (or a NoSuchElement, counting as "gone").
function until_not(w::Wait, condition)
    deadline = time() + w.timeout_s
    while true
        try
            condition(w.driver) || return nothing
        catch e
            if e isa WebDriverError && e.code == 17
                return nothing
            end
            rethrow()
        end
        time() >= deadline && throw(WebDriverError("waited $(w.timeout_s)s for condition", Cint(21)))
        sleep(w.poll_s)
    end
end

# find_element that maps a NoSuchElement miss to nothing.
function _try_find(d::WebDriver, loc::Locator)::Union{WebElement,Nothing}
    try
        return find_element(d, loc)
    catch e
        e isa WebDriverError && e.code == 17 && return nothing
        rethrow()
    end
end

# Block until an element matching `loc` is present; return it.
function wait_for_element(d::WebDriver, loc::Locator, timeout_s::Real)::WebElement
    deadline = time() + Float64(timeout_s)
    while true
        el = _try_find(d, loc)
        el !== nothing && return el
        time() >= deadline && throw(WebDriverError("waited $(timeout_s)s for element", Cint(21)))
        sleep(POLL_INTERVAL_S)
    end
end

function wait_for_visible(d::WebDriver, loc::Locator, timeout_s::Real)::WebElement
    deadline = time() + Float64(timeout_s)
    while true
        el = _try_find(d, loc)
        el !== nothing && is_displayed(el) && return el
        time() >= deadline && throw(WebDriverError("waited $(timeout_s)s for visible element", Cint(21)))
        sleep(POLL_INTERVAL_S)
    end
end

function wait_for_clickable(d::WebDriver, loc::Locator, timeout_s::Real)::WebElement
    deadline = time() + Float64(timeout_s)
    while true
        el = _try_find(d, loc)
        el !== nothing && is_displayed(el) && is_enabled(el) && return el
        time() >= deadline && throw(WebDriverError("waited $(timeout_s)s for clickable element", Cint(21)))
        sleep(POLL_INTERVAL_S)
    end
end

wait_until_gone(d::WebDriver, loc::Locator, timeout_s::Real) =
    until_not(wait(d, timeout_s), dd -> _try_find(dd, loc) !== nothing)
wait_for_title_is(d::WebDriver, t::AbstractString, timeout_s::Real) =
    until(wait(d, timeout_s), dd -> title(dd) == t)
wait_for_title_contains(d::WebDriver, substr::AbstractString, timeout_s::Real) =
    until(wait(d, timeout_s), dd -> occursin(substr, title(dd)))
wait_for_url_is(d::WebDriver, u::AbstractString, timeout_s::Real) =
    until(wait(d, timeout_s), dd -> current_url(dd) == u)
wait_for_url_contains(d::WebDriver, substr::AbstractString, timeout_s::Real) =
    until(wait(d, timeout_s), dd -> occursin(substr, current_url(dd)))

# ---- lifecycle ----
quit(d::WebDriver) = (try execute(d, "quit", "{}") catch end; _stop_owned_driver(d); nothing)

sessionid(d::WebDriver)::String =
    take(ccall((:aether_sel_embed_session_id, LIB), Ptr{Cchar}, (Ptr{Cvoid},), d.handle))

close!(d::WebDriver) = ccall((:aether_sel_embed_close, LIB), Cvoid, (Ptr{Cvoid},), d.handle)

# ---- driver orchestration (spawn / adopt a driver process) ----------------
# The engine can resolve, download-or-cache, and launch a browser driver itself,
# so a caller needs neither a driver on PATH nor a running Grid. An opaque driver
# handle, independent of the W3C session handle.
mutable struct DriverProcess
    handle::Ptr{Cvoid}
end

# Resolve the local driver binary path for `browser` without launching it. `hint`
# pins a version/path; "" auto-detects. Returns "" if none resolvable.
resolve_driver(browser::AbstractString, hint::AbstractString = "")::String =
    take(ccall((:aether_sel_embed_resolve_driver, LIB), Ptr{Cchar}, (Cstring, Cstring), browser, hint))

# Launch a driver at an explicit binary path. Returns a DriverProcess, or nothing
# if it did not come up within timeout_ms.
function launch_driver(driver_path::AbstractString, timeout_ms::Integer)::Union{DriverProcess,Nothing}
    h = ccall((:aether_sel_embed_launch_driver, LIB), Ptr{Cvoid}, (Cstring, Cint), driver_path, Cint(timeout_ms))
    h == C_NULL ? nothing : DriverProcess(h)
end

# Resolve AND launch a driver for `browser` in one step.
function ensure_driver(browser::AbstractString, hint::AbstractString, timeout_ms::Integer)::Union{DriverProcess,Nothing}
    h = ccall((:aether_sel_embed_ensure_driver, LIB), Ptr{Cvoid}, (Cstring, Cstring, Cint), browser, hint, Cint(timeout_ms))
    h == C_NULL ? nothing : DriverProcess(h)
end

driver_url(dp::DriverProcess)::String =
    dp.handle == C_NULL ? "" : take(ccall((:aether_sel_embed_driver_url, LIB), Ptr{Cchar}, (Ptr{Cvoid},), dp.handle))
driver_pid(dp::DriverProcess)::Cint =
    dp.handle == C_NULL ? Cint(0) : ccall((:aether_sel_embed_driver_pid, LIB), Cint, (Ptr{Cvoid},), dp.handle)
function stop_driver(dp::DriverProcess)
    if dp.handle != C_NULL
        ccall((:aether_sel_embed_stop_driver, LIB), Cvoid, (Ptr{Cvoid},), dp.handle)
        dp.handle = C_NULL
    end
    nothing
end

function _stop_owned_driver(d::WebDriver)
    d.driver isa DriverProcess && stop_driver(d.driver)
    d.driver = nothing
    nothing
end

# ---- session constructors ----
# Apply TLS trust on the handle before newSession, request a BiDi channel, then
# newSession. Returns the opened WebDriver (its ws_url set from the reply).
function _new_session(commandexecutor::AbstractString, caps::AbstractDict, tls::TlsConfig)::WebDriver
    d = WebDriver(commandexecutor)
    d.handle == C_NULL && throw(WebDriverError("failed to open session handle", Cint(-1)))
    if tls.ca_path !== nothing
        ccall((:aether_sel_embed_set_ca, LIB), Cvoid, (Ptr{Cvoid}, Cstring), d.handle, tls.ca_path)
    end
    tls.insecure && ccall((:aether_sel_embed_set_insecure, LIB), Cvoid, (Ptr{Cvoid}, Cint), d.handle, Cint(1))
    allmatch = Dict{String,Any}(caps)
    allmatch["webSocketUrl"] = true
    result = execute(d, "newSession", Dict("capabilities" => Dict("alwaysMatch" => allmatch)))
    m = match(r"\"webSocketUrl\":\"([^\"]*)\"", result)
    d.ws_url = m === nothing ? "" : m.captures[1]
    return d
end

# Start a Chrome session against a running chromedriver (or Grid). `options` is a
# Dict of extra capabilities merged under browserName: chrome.
chrome(commandexecutor::AbstractString, options::AbstractDict = Dict{String,Any}()) =
    chrome_tls(commandexecutor, options, TlsConfig())

function chrome_tls(commandexecutor::AbstractString, options::AbstractDict, tls::TlsConfig)
    caps = Dict{String,Any}(options)
    caps["browserName"] = "chrome"
    return _new_session(commandexecutor, caps, tls)
end

# Convenience: headless-Chrome launch args baked in.
function headless_chrome(commandexecutor::AbstractString)
    opts = Dict{String,Any}("goog:chromeOptions" =>
        Dict("args" => ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]))
    return chrome(commandexecutor, opts)
end

# A Chrome session that spawns its own chromedriver via the engine — no driver on
# PATH, no Grid. The driver process is owned by the returned WebDriver.
function local_chrome(; options::AbstractDict = Dict{String,Any}(), hint::AbstractString = "",
        timeout_ms::Integer = 15000, tls::TlsConfig = TlsConfig())
    proc = ensure_driver("chrome", hint, timeout_ms)
    proc === nothing && throw(WebDriverError("could not resolve/launch chromedriver", Cint(-1)))
    d = chrome_tls(driver_url(proc), options, tls)
    d.driver = proc
    return d
end

# ---- WebDriver-BiDi -------------------------------------------------------
# The common BiDi event names (W3C spec) — pass to `subscribe` / `next_event`.
module BidiEvent
    const LOG_ENTRY_ADDED = "log.entryAdded"
    const CONTEXT_CREATED = "browsingContext.contextCreated"
    const CONTEXT_DESTROYED = "browsingContext.contextDestroyed"
    const NAVIGATION_STARTED = "browsingContext.navigationStarted"
    const DOM_CONTENT_LOADED = "browsingContext.domContentLoaded"
    const LOAD = "browsingContext.load"
    const DOWNLOAD_WILL_BEGIN = "browsingContext.downloadWillBegin"
    const BEFORE_REQUEST_SENT = "network.beforeRequestSent"
    const AUTH_REQUIRED = "network.authRequired"
    const RESPONSE_STARTED = "network.responseStarted"
    const RESPONSE_COMPLETED = "network.responseCompleted"
    const FETCH_ERROR = "network.fetchError"
    const REALM_CREATED = "script.realmCreated"
    const REALM_DESTROYED = "script.realmDestroyed"
    const MESSAGE = "script.message"
end

# The event-driven BiDi channel for a session (over the demux C ABI). Command ids
# are supplied automatically from a monotonic per-channel counter (from 1).
mutable struct BiDi
    handle::Ptr{Cvoid}
    next_id::Cint
end

_next_id!(b::BiDi) = (id = b.next_id; b.next_id += Cint(1); id)

# True if this session negotiated a webSocketUrl (BiDi usable).
bidi_available(d::WebDriver)::Bool = !isempty(d.ws_url)

# The BiDi surface for this session, opened lazily over the negotiated
# webSocketUrl. Errors if the remote end granted no BiDi URL.
function bidi(d::WebDriver)::BiDi
    if d.bidi isa BiDi
        return d.bidi
    end
    isempty(d.ws_url) && throw(WebDriverError("BiDi not available: the session negotiated no webSocketUrl", Cint(0)))
    h = ccall((:aether_sel_embed_bidi_open, LIB), Ptr{Cvoid}, (Cstring,), d.ws_url)
    h == C_NULL && throw(WebDriverError("BiDi channel failed to open", Cint(-1)))
    b = BiDi(h, Cint(1))
    d.bidi = b
    return b
end

function subscribe(b::BiDi, events::AbstractVector, timeout_ms::Integer = 10000)::String
    id = _next_id!(b)
    csv = join(events, ",")
    take(ccall((:aether_sel_embed_bidi_subscribe, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, id, csv, Cint(timeout_ms)))
end
function unsubscribe(b::BiDi, events::AbstractVector, timeout_ms::Integer = 10000)::String
    id = _next_id!(b)
    csv = join(events, ",")
    take(ccall((:aether_sel_embed_bidi_unsubscribe, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, id, csv, Cint(timeout_ms)))
end

# Block until an event whose `method` matches arrives, or timeout. Returns the
# event JSON, or "" on timeout/close. (Subscribe first.)
function next_event(b::BiDi, method::AbstractString, timeout_ms::Integer)::String
    take(ccall((:aether_sel_embed_bidi_wait_event, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cstring, Cint), b.handle, method, Cint(timeout_ms)))
end

# Issue any BiDi command and return its reply payload JSON. Sends, then pumps
# until this id's reply arrives or the timeout elapses.
function command(b::BiDi, method::AbstractString, params::AbstractDict, timeout_ms::Integer)::String
    cid = _next_id!(b)
    pj = _encode(params)
    if ccall((:aether_sel_embed_bidi_send, LIB), Cint,
            (Ptr{Cvoid}, Cint, Cstring, Cstring), b.handle, cid, method, pj) != 0
        throw(WebDriverError("BiDi send failed: $method", Cint(-1)))
    end
    waited = 0
    step = 50
    while waited < timeout_ms
        reply = take(ccall((:aether_sel_embed_bidi_poll_reply, LIB), Ptr{Cchar}, (Ptr{Cvoid}, Cint), b.handle, cid))
        isempty(reply) || return reply
        ccall((:aether_sel_embed_bidi_pump, LIB), Cint, (Ptr{Cvoid}, Cint), b.handle, Cint(step)) < 0 && break
        waited += step
    end
    throw(WebDriverError("BiDi command timed out: $method", Cint(21)))
end

get_tree(b::BiDi, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_get_tree, LIB), Ptr{Cchar}, (Ptr{Cvoid}, Cint, Cint), b.handle, _next_id!(b), Cint(timeout_ms)))

# The top-level browsing context id, or nothing when the tree is empty.
function top_context(b::BiDi, timeout_ms::Integer)::Union{String,Nothing}
    tree = get_tree(b, timeout_ms)
    m = match(r"\"context\":\"([^\"]*)\"", tree)
    return m === nothing ? nothing : m.captures[1]
end

# script.evaluate an expression in the top-level realm; returns the reply JSON.
function evaluate(b::BiDi, expr::AbstractString, timeout_ms::Integer)::String
    ctx = top_context(b, timeout_ms)
    ctx === nothing && throw(WebDriverError("no browsing context for script.evaluate", Cint(0)))
    take(ccall((:aether_sel_embed_bidi_script_evaluate, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cstring, Cint), b.handle, _next_id!(b), expr, ctx, Cint(timeout_ms)))
end

# script.evaluate, returning just the unwrapped value (or "" if not simple).
function evaluate_value(b::BiDi, expr::AbstractString, timeout_ms::Integer)::String
    reply = evaluate(b, expr, timeout_ms)
    m = match(r"\"result\".*?\"value\":\s*(\"[^\"]*\"|[-\d.]+|true|false|null)", reply)
    return m === nothing ? "" : _as_string(m.captures[1])
end

function navigate(b::BiDi, url::AbstractString, timeout_ms::Integer)::String
    ctx = top_context(b, timeout_ms)
    ctx === nothing && throw(WebDriverError("no browsing context for navigate", Cint(0)))
    take(ccall((:aether_sel_embed_bidi_navigate, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cstring, Cint), b.handle, _next_id!(b), ctx, url, Cint(timeout_ms)))
end

# ---- BiDi network interception ----
function add_intercept(b::BiDi, phases_csv::AbstractString, url_pattern::AbstractString, timeout_ms::Integer)::Union{String,Nothing}
    raw = take(ccall((:aether_sel_embed_bidi_network_add_intercept, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cstring, Cint), b.handle, _next_id!(b), phases_csv, url_pattern, Cint(timeout_ms)))
    m = match(r"\"intercept\":\"([^\"]*)\"", raw)
    return m === nothing ? nothing : m.captures[1]
end
remove_intercept(b::BiDi, intercept_id::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_remove_intercept, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, _next_id!(b), intercept_id, Cint(timeout_ms)))
continue_request(b::BiDi, request_id::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_continue_request, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, _next_id!(b), request_id, Cint(timeout_ms)))
fail_request(b::BiDi, request_id::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_fail_request, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, _next_id!(b), request_id, Cint(timeout_ms)))
provide_response(b::BiDi, request_id::AbstractString, status::Integer, content_type::AbstractString, body::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_provide_response, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint, Cstring, Cstring, Cint),
        b.handle, _next_id!(b), request_id, Cint(status), content_type, body, Cint(timeout_ms)))
continue_with_auth(b::BiDi, request_id::AbstractString, username::AbstractString, password::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_continue_with_auth, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cstring, Cstring, Cint),
        b.handle, _next_id!(b), request_id, username, password, Cint(timeout_ms)))
set_cache_behavior(b::BiDi, behavior::AbstractString, timeout_ms::Integer)::String =
    take(ccall((:aether_sel_embed_bidi_network_set_cache_behavior, LIB), Ptr{Cchar},
        (Ptr{Cvoid}, Cint, Cstring, Cint), b.handle, _next_id!(b), behavior, Cint(timeout_ms)))

# The network.request id out of a network event JSON: params.request.request.
function event_request_id(event::AbstractString)::Union{String,Nothing}
    m = match(r"\"request\":\{[^}]*?\"request\":\"([^\"]*)\"", event)
    return m === nothing ? nothing : m.captures[1]
end

# How many events the bounded queue dropped since the last call (then resets).
lost_events(b::BiDi)::Cint = ccall((:aether_sel_embed_bidi_lost_events, LIB), Cint, (Ptr{Cvoid},), b.handle)

close_bidi(b::BiDi) = (b.handle != C_NULL && ccall((:aether_sel_embed_bidi_close, LIB), Cvoid, (Ptr{Cvoid},), b.handle); nothing)

end # module
