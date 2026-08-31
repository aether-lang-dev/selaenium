%% selenium_nif — raw NIF surface over the Aether Selenium core's C ABI.
%%
%% A 1:1 stub module: every function is replaced at load time by the native
%% implementation in c_src/selenium_nif.c (priv/selenium_nif.so), which links
%% libselenium_core.so. Until the NIF loads, each body raises not_loaded.
%%
%% This is the CANONICAL Aether Selenium NIF for the whole BEAM family. It is
%% built ONCE (as the OTP app `selenium_nif`: this module + priv/selenium_nif.so)
%% and the Elixir and Gleam bindings load this SAME compiled module over the BEAM
%% — they do not each compile their own copy of the C source. (Erlang is the
%% BEAM's lingua franca, so it owns the shared binding, exactly as the one Java
%% jar backs the Kotlin/Scala/Clojure/Groovy bindings.)
%%
%% Use `selenium` (selenium.erl) for the idiomatic Erlang API; this is the thin
%% FFI seam. The opaque session handle is a 64-bit integer (uintptr_t); 0 from
%% open means failure. String results are binaries.
-module(selenium_nif).

-on_load(init/0).

-export([
    open/1,
    close/1,
    execute/3,
    last_value/1,
    last_status/1,
    last_error_code/1,
    last_error/1,
    session_id/1,
    by_locator/2,
    route/1,
    error_code/1,
    bidi_open/1,
    bidi_close/1,
    bidi_send/4,
    bidi_pump/2,
    bidi_fd/1,
    bidi_poll_reply/2,
    bidi_poll_event/1,
    bidi_lost_events/1,
    bidi_cancel/2,
    bidi_subscribe/4,
    bidi_unsubscribe/4,
    bidi_wait_event/3,
    execute_atom/4,
    is_displayed/2,
    get_attribute/3,
    atom_str_arg/1,
    find_relative/3
]).

init() ->
    %% Resolve priv/selenium_nif.so three ways, in order: SELENIUM_NIF_DIR
    %% override (a consumer that can't set ERL_LIBS); the OTP app's priv_dir
    %% (the normal path via ERL_LIBS for Erlang/Elixir/Gleam alike); else a
    %% loose ./priv when run straight from a source tree.
    Base =
        case os:getenv("SELENIUM_NIF_DIR") of
            false ->
                case code:priv_dir(selenium_nif) of
                    {error, bad_name} -> filename:join("priv", "selenium_nif");
                    Dir -> filename:join(Dir, "selenium_nif")
                end;
            EnvDir ->
                filename:join(EnvDir, "selenium_nif")
        end,
    erlang:load_nif(Base, 0).

open(_BaseUrl) -> erlang:nif_error(not_loaded).
close(_Handle) -> erlang:nif_error(not_loaded).
execute(_Handle, _Name, _ParamsJson) -> erlang:nif_error(not_loaded).
last_value(_Handle) -> erlang:nif_error(not_loaded).
last_status(_Handle) -> erlang:nif_error(not_loaded).
last_error_code(_Handle) -> erlang:nif_error(not_loaded).
last_error(_Handle) -> erlang:nif_error(not_loaded).
session_id(_Handle) -> erlang:nif_error(not_loaded).
by_locator(_Strategy, _Value) -> erlang:nif_error(not_loaded).
route(_Name) -> erlang:nif_error(not_loaded).
error_code(_W3cError) -> erlang:nif_error(not_loaded).

%% ---- WebDriver-BiDi (over the session's webSocketUrl) ----
bidi_open(_WsUrl) -> erlang:nif_error(not_loaded).
bidi_close(_Handle) -> erlang:nif_error(not_loaded).
bidi_send(_Handle, _Id, _Method, _ParamsJson) -> erlang:nif_error(not_loaded).
bidi_pump(_Handle, _TimeoutMs) -> erlang:nif_error(not_loaded).
bidi_fd(_Handle) -> erlang:nif_error(not_loaded).
bidi_poll_reply(_Handle, _Id) -> erlang:nif_error(not_loaded).
bidi_poll_event(_Handle) -> erlang:nif_error(not_loaded).
bidi_lost_events(_Handle) -> erlang:nif_error(not_loaded).
bidi_cancel(_Handle, _Id) -> erlang:nif_error(not_loaded).
bidi_subscribe(_Handle, _Id, _EventsCsv, _TimeoutMs) -> erlang:nif_error(not_loaded).
bidi_unsubscribe(_Handle, _Id, _EventsCsv, _TimeoutMs) -> erlang:nif_error(not_loaded).
bidi_wait_event(_Handle, _Method, _TimeoutMs) -> erlang:nif_error(not_loaded).

%% ---- atom-backed commands (isDisplayed / getAttribute / relative locators) ----
%% The int-returning verbs leave their JSON result in last_value (drained the
%% normal way, like execute); atom_str_arg returns a quoted JSON string binary.
execute_atom(_Handle, _Atom, _ElemId, _ExtraJson) -> erlang:nif_error(not_loaded).
is_displayed(_Handle, _ElemId) -> erlang:nif_error(not_loaded).
get_attribute(_Handle, _ElemId, _Name) -> erlang:nif_error(not_loaded).
atom_str_arg(_S) -> erlang:nif_error(not_loaded).
find_relative(_Handle, _BaseCss, _FiltersJson) -> erlang:nif_error(not_loaded).
