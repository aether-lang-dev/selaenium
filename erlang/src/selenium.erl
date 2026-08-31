%% selenium — the idiomatic Erlang WebDriver API over the shared Aether core.
%%
%% Carries NO protocol logic: the W3C command map, routing, By normalization,
%% error decode and HTTP round-trip all live in the Aether engine, reached via
%% the `selenium_nif` NIF. This module marshals Erlang maps/lists <-> JSON and
%% presents a small idiomatic surface.
%%
%% A session handle is an opaque integer. Commands return {ok, Value} | {error,
%% {Code, Message}}. Values are decoded JSON: maps (with binary keys), lists,
%% binaries, numbers, booleans, null (the atom `null`).
%%
%% OTP 25 has no `json` module, so a tiny encoder/decoder lives here.
-module(selenium).

-export([
    chrome/1, chrome/2, headless_chrome/1,
    get/2, current_url/1, title/1, page_source/1, back/1, forward/1, refresh/1,
    find_element/3, find_elements/3,
    click/2, send_keys/3, element_text/2, tag_name/2, element_property/3, element_rect/2,
    is_displayed/2, get_attribute/3, dom_attribute/3, find_relative/3,
    execute/3,
    execute_script/2, execute_script/3,
    window_handles/1, current_window_handle/1, set_window_rect/2, get_window_rect/1,
    add_cookie/2, cookies/1, cookie/2, delete_cookie/2, delete_all_cookies/1,
    perform_actions/2, clear_actions/1,
    set_timeouts/2, screenshot/1,
    session_id/1, quit/1,
    route/1, error_code/1, locator/2,
    bidi_available/1, bidi_subscribe/2, bidi_unsubscribe/2,
    bidi_next_event/3, bidi_command/4, bidi_lost_events/1,
    bidi_get_tree/1, bidi_top_context/1, bidi_evaluate/2, bidi_evaluate_value/2, bidi_navigate/2,
    bidi_add_intercept/2, bidi_add_intercept/3, bidi_remove_intercept/2,
    bidi_continue_request/2, bidi_fail_request/2, bidi_event_request_id/1,
    bidi_provide_response/2, bidi_provide_response/5
]).

-define(W3C_KEY, <<"element-6066-11e4-a52e-4f735466cecf">>).

%% Per-session BiDi state lives in a named ETS table keyed by the session
%% handle: {Handle, WsUrl, BidiHandle, NextId}. WsUrl is the negotiated
%% webSocketUrl (<<>> if none). BidiHandle is `undefined` until the WebSocket is
%% opened lazily on first BiDi use — a classic script never opens it. NextId is
%% the monotonic per-channel command-id counter (starts at 1). This mirrors the
%% binding's design: mutable session state lives outside the immutable Erlang
%% terms (here in ETS; the W3C session state itself lives C-side behind Handle).
-define(BIDI_TABLE, selenium_bidi).

%% ---- session lifecycle ----

chrome(CommandExecutor) -> chrome(CommandExecutor, #{}).

chrome(CommandExecutor, Options) when is_map(Options) ->
    Caps = maps:merge(#{<<"browserName">> => <<"chrome">>}, Options),
    new(CommandExecutor, Caps).

headless_chrome(CommandExecutor) ->
    chrome(CommandExecutor, #{
        <<"goog:chromeOptions">> => #{
            <<"args">> => [<<"--headless=new">>, <<"--no-sandbox">>,
                           <<"--disable-gpu">>, <<"--disable-dev-shm-usage">>]
        }
    }).

new(CommandExecutor, Caps) ->
    Handle = selenium_nif:open(to_bin(CommandExecutor)),
    case Handle of
        0 -> {error, {-1, <<"failed to open session handle">>}};
        _ ->
            %% Request a BiDi channel so bidi_* is available on demand; the
            %% WebSocket itself opens lazily (a classic script never opens it).
            BidiCaps = maps:put(<<"webSocketUrl">>, true, Caps),
            Payload = #{<<"capabilities">> => #{<<"alwaysMatch">> => BidiCaps}},
            case execute(Handle, <<"newSession">>, Payload) of
                {ok, Value} ->
                    bidi_register(Handle, ws_url_of(Value)),
                    {ok, Handle};
                Err -> selenium_nif:close(Handle), Err
            end
    end.

%% value.capabilities.webSocketUrl — the BiDi endpoint for this session, or <<>>.
ws_url_of(Value) when is_map(Value) ->
    case maps:get(<<"capabilities">>, Value, undefined) of
        Caps when is_map(Caps) ->
            case maps:get(<<"webSocketUrl">>, Caps, undefined) of
                Url when is_binary(Url) -> Url;
                _ -> <<>>
            end;
        _ -> <<>>
    end;
ws_url_of(_) -> <<>>.

%% ---- the FFI seam ----

execute(Handle, Command, Params) ->
    Rc = selenium_nif:execute(Handle, to_bin(Command), encode(Params)),
    case Rc of
        0 ->
            Raw = selenium_nif:last_value(Handle),
            case Raw of
                <<>> -> {ok, null};
                _ -> {ok, decode(Raw)}
            end;
        _ ->
            Code = selenium_nif:last_error_code(Handle),
            Msg = selenium_nif:last_error(Handle),
            {error, {Code, Msg}}
    end.

%% ---- navigation ----
get(H, Url) -> execute(H, <<"get">>, #{<<"url">> => to_bin(Url)}).
current_url(H) -> execute(H, <<"getCurrentUrl">>, #{}).
title(H) -> execute(H, <<"getTitle">>, #{}).
page_source(H) -> execute(H, <<"getPageSource">>, #{}).
back(H) -> execute(H, <<"goBack">>, #{}).
forward(H) -> execute(H, <<"goForward">>, #{}).
refresh(H) -> execute(H, <<"refresh">>, #{}).

%% ---- elements ---- (return {ok, ElementId} | {error, _})
find_element(H, By, Value) ->
    case execute(H, <<"findElement">>, decode_by(By, Value)) of
        {ok, M} -> {ok, maps:get(?W3C_KEY, M)};
        Err -> Err
    end.

find_elements(H, By, Value) ->
    case execute(H, <<"findElements">>, decode_by(By, Value)) of
        {ok, L} -> {ok, [maps:get(?W3C_KEY, E) || E <- L]};
        Err -> Err
    end.

click(H, ElementId) -> execute(H, <<"clickElement">>, #{<<"id">> => ElementId}).
send_keys(H, ElementId, Text) ->
    execute(H, <<"sendKeysToElement">>,
            #{<<"id">> => ElementId, <<"text">> => to_bin(Text),
              <<"value">> => [<<C/utf8>> || C <- unicode:characters_to_list(to_bin(Text))]}).
element_text(H, ElementId) -> execute(H, <<"getElementText">>, #{<<"id">> => ElementId}).
tag_name(H, ElementId) -> execute(H, <<"getElementTagName">>, #{<<"id">> => ElementId}).
element_property(H, ElementId, Name) ->
    execute(H, <<"getElementProperty">>, #{<<"id">> => ElementId, <<"name">> => to_bin(Name)}).
element_rect(H, ElementId) -> execute(H, <<"getElementRect">>, #{<<"id">> => ElementId}).

%% ---- atom-backed commands (isDisplayed / getAttribute / relative locators) ----
%%
%% Each runs a shared JS atom in-page via the engine (the SAME atoms every other
%% binding uses). The int-returning verbs leave their JSON result in last_value,
%% drained + error-decoded exactly like execute/3 (see atom_result/2).

%% Whether the element is shown (the isDisplayed atom — the real visibility
%% algorithm, not a naive style check). Returns boolean() | {error, {Code, Msg}}.
is_displayed(H, ElementId) ->
    case atom_result(H, selenium_nif:is_displayed(H, to_bin(ElementId))) of
        {ok, V} -> V =:= true;
        Err -> Err
    end.

%% The classic getAttribute(name): property-or-attribute (boolean attrs, live
%% properties like value/checked), via the shared engine atom. Returns
%% binary() | undefined (JSON null) | {error, {Code, Msg}}. Use dom_attribute/3
%% for the raw W3C DOM attribute.
get_attribute(H, ElementId, Name) ->
    case atom_result(H, selenium_nif:get_attribute(H, to_bin(ElementId), to_bin(Name))) of
        {ok, null} -> undefined;
        {ok, V} -> V;
        Err -> Err
    end.

%% The literal DOM attribute (W3C getDomAttribute), no property fallback.
dom_attribute(H, ElementId, Name) ->
    execute(H, <<"getDomAttribute">>, #{<<"id">> => ElementId, <<"name">> => to_bin(Name)}).

%% Relative locators: elements matching BaseCss filtered by spatial relation to
%% anchors, nearest first. Filters is a list of maps
%% #{kind => above|below|left|right|near, sel => <<css>>} (near also accepts
%% dist). Returns {ok, [ElementId]} | {error, {Code, Msg}}.
find_relative(H, BaseCss, Filters) ->
    Rc = selenium_nif:find_relative(H, to_bin(BaseCss), encode(Filters)),
    case atom_result(H, Rc) of
        {ok, null} -> {ok, []};
        {ok, Refs} when is_list(Refs) -> {ok, [maps:get(?W3C_KEY, R) || R <- Refs]};
        Err -> Err
    end.

%% Drain last_value after an atom call, decoding + error-mapping like execute/3.
%% Returns {ok, DecodedValue} | {error, {Code, Message}}.
atom_result(H, Rc) ->
    case Rc of
        0 ->
            case selenium_nif:last_value(H) of
                <<>> -> {ok, null};
                Raw -> {ok, decode(Raw)}
            end;
        _ ->
            Code = selenium_nif:last_error_code(H),
            Msg = selenium_nif:last_error(H),
            {error, {Code, Msg}}
    end.

%% ---- script ----
execute_script(H, Script) -> execute_script(H, Script, []).
execute_script(H, Script, Args) ->
    execute(H, <<"executeScript">>, #{<<"script">> => to_bin(Script), <<"args">> => Args}).

%% ---- windows ----
window_handles(H) -> execute(H, <<"getWindowHandles">>, #{}).
current_window_handle(H) -> execute(H, <<"getCurrentWindowHandle">>, #{}).
set_window_rect(H, Rect) -> execute(H, <<"setWindowRect">>, Rect).
get_window_rect(H) -> execute(H, <<"getWindowRect">>, #{}).

%% ---- cookies ----
add_cookie(H, Cookie) -> execute(H, <<"addCookie">>, #{<<"cookie">> => Cookie}).
cookies(H) -> execute(H, <<"getCookies">>, #{}).
cookie(H, Name) -> execute(H, <<"getCookie">>, #{<<"name">> => to_bin(Name)}).
delete_cookie(H, Name) -> execute(H, <<"deleteCookie">>, #{<<"name">> => to_bin(Name)}).
delete_all_cookies(H) -> execute(H, <<"deleteAllCookies">>, #{}).

%% ---- actions ----
perform_actions(H, Actions) -> execute(H, <<"actions">>, #{<<"actions">> => Actions}).
clear_actions(H) -> execute(H, <<"clearActions">>, #{}).

%% ---- timeouts / screenshots ----
set_timeouts(H, Timeouts) -> execute(H, <<"setTimeout">>, Timeouts).
screenshot(H) -> execute(H, <<"screenshot">>, #{}).

%% ---- lifecycle ----
session_id(H) -> selenium_nif:session_id(H).
quit(H) ->
    bidi_shutdown(H),
    R = execute(H, <<"quit">>, #{}),
    selenium_nif:close(H),
    R.

%% ---- WebDriver-BiDi ----
%%
%% The event-driven surface for a session, multiplexed over one WebSocket by the
%% engine's demux (single reader -> id-keyed replies + bounded event queue), so
%% replies stay correlated while events stream. The channel opens lazily over the
%% negotiated webSocketUrl on first use; command ids are supplied automatically.
%% See selenium_bidi.hrl for the common event-name macros.

%% True if this session negotiated a webSocketUrl (BiDi usable).
bidi_available(H) ->
    case bidi_lookup(H) of
        {ok, WsUrl, _, _} -> WsUrl =/= <<>>;
        error -> false
    end.

%% session.subscribe to one or more event names (a list of binaries); wait for
%% the ack. Returns {ok, AckMap} | {error, {Code, Message}}. Matching events then
%% arrive on the queue (drain via bidi_next_event/3).
bidi_subscribe(H, Events) ->
    with_bidi(H, fun(BH) ->
        Id = bidi_next_id(H),
        Raw = selenium_nif:bidi_subscribe(BH, Id, join_events(Events), 10000),
        {ok, ack(Raw)}
    end).

bidi_unsubscribe(H, Events) ->
    with_bidi(H, fun(BH) ->
        Id = bidi_next_id(H),
        Raw = selenium_nif:bidi_unsubscribe(BH, Id, join_events(Events), 10000),
        {ok, ack(Raw)}
    end).

%% Block until an event whose method matches arrives, or timeout. Returns
%% {ok, EventMap} | {ok, timeout} on timeout/close | {error, _}. (Subscribe
%% first.)
bidi_next_event(H, Method, TimeoutMs) ->
    with_bidi(H, fun(BH) ->
        case selenium_nif:bidi_wait_event(BH, to_bin(Method), TimeoutMs) of
            <<>> -> {ok, timeout};
            Raw -> {ok, decode(Raw)}
        end
    end).

%% Issue any BiDi command and return {ok, ReplyMap} | {error, _}. Reaches BiDi
%% methods with no dedicated wrapper (script.evaluate, network.*, ...): send +
%% pump-poll until this id's reply arrives.
bidi_command(H, Method, Params, TimeoutMs) ->
    with_bidi(H, fun(BH) ->
        Id = bidi_next_id(H),
        case selenium_nif:bidi_send(BH, Id, to_bin(Method), encode(Params)) of
            0 -> bidi_await_reply(BH, Id, TimeoutMs, 50, 0, Method);
            _ -> {error, {-1, iolist_to_binary([<<"BiDi send failed: ">>, to_bin(Method)])}}
        end
    end).

bidi_await_reply(_BH, _Id, TimeoutMs, _Step, Waited, Method) when Waited >= TimeoutMs ->
    {error, {24, iolist_to_binary([<<"BiDi command timed out: ">>, to_bin(Method)])}};
bidi_await_reply(BH, Id, TimeoutMs, Step, Waited, Method) ->
    case selenium_nif:bidi_poll_reply(BH, Id) of
        <<>> ->
            case selenium_nif:bidi_pump(BH, Step) of
                Rc when Rc < 0 ->
                    {error, {-1, <<"BiDi channel closed">>}};
                _ ->
                    bidi_await_reply(BH, Id, TimeoutMs, Step, Waited + Step, Method)
            end;
        Raw -> {ok, decode(Raw)}
    end.

%% How many events the bounded queue dropped since the last call (then resets).
%% Returns {ok, Count} | {error, _}.
bidi_lost_events(H) ->
    with_bidi(H, fun(BH) -> {ok, selenium_nif:bidi_lost_events(BH)} end).

%% ---- typed BiDi convenience commands ----

%% browsingContext.getTree — {ok, TreeMap} (result.contexts[] with context ids).
bidi_get_tree(H) ->
    with_bidi(H, fun(BH) ->
        {ok, decode(selenium_nif:bidi_get_tree(BH, bidi_next_id(H), 10000))}
    end).

%% The top-level browsing context id, or undefined.
bidi_top_context(H) ->
    case bidi_get_tree(H) of
        {ok, Tree} ->
            case Tree of
                #{<<"result">> := #{<<"contexts">> := [#{<<"context">> := Ctx} | _]}} -> Ctx;
                _ -> undefined
            end;
        _ -> undefined
    end.

%% script.evaluate Expr in the top context's realm (awaitPromise). Returns
%% {ok, ReplyMap} — result.result is the BiDi-typed value. BiDi's richer
%% alternative to execute_script.
bidi_evaluate(H, Expr) ->
    case bidi_top_context(H) of
        undefined -> {error, {0, <<"no browsing context for script.evaluate">>}};
        Ctx ->
            with_bidi(H, fun(BH) ->
                {ok, decode(selenium_nif:bidi_script_evaluate(BH, bidi_next_id(H), to_bin(Expr), Ctx, 30000))}
            end)
    end.

%% script.evaluate returning just the unwrapped value (result.result.value).
bidi_evaluate_value(H, Expr) ->
    case bidi_evaluate(H, Expr) of
        {ok, #{<<"result">> := #{<<"result">> := #{<<"value">> := V}}}} -> {ok, V};
        {ok, _} -> {ok, undefined};
        Err -> Err
    end.

%% browsingContext.navigate the top context to Url (wait:complete).
bidi_navigate(H, Url) ->
    case bidi_top_context(H) of
        undefined -> {error, {0, <<"no browsing context for navigate">>}};
        Ctx ->
            with_bidi(H, fun(BH) ->
                {ok, decode(selenium_nif:bidi_navigate(BH, bidi_next_id(H), Ctx, to_bin(Url), 30000))}
            end)
    end.

%% ---- network interception ----

%% network.addIntercept for a URL pattern (full parseable URL as a "string"
%% pattern; <<>> intercepts all) at Phases (default "beforeRequestSent"). Returns
%% {ok, InterceptId} | {error, _}.
bidi_add_intercept(H, UrlPattern) ->
    bidi_add_intercept(H, UrlPattern, <<"beforeRequestSent">>).
bidi_add_intercept(H, UrlPattern, Phases) ->
    with_bidi(H, fun(BH) ->
        Reply = decode(selenium_nif:bidi_network_add_intercept(BH, bidi_next_id(H), to_bin(Phases), to_bin(UrlPattern), 10000)),
        case Reply of
            #{<<"result">> := #{<<"intercept">> := Ic}} -> {ok, Ic};
            _ -> {error, {0, <<"no intercept id">>}}
        end
    end).

bidi_remove_intercept(H, InterceptId) ->
    with_bidi(H, fun(BH) ->
        {ok, decode(selenium_nif:bidi_network_remove_intercept(BH, bidi_next_id(H), to_bin(InterceptId), 10000))}
    end).

%% Let a paused request proceed. RequestId comes from a network event's
%% params.request.request.
bidi_continue_request(H, RequestId) ->
    with_bidi(H, fun(BH) ->
        {ok, decode(selenium_nif:bidi_network_continue_request(BH, bidi_next_id(H), to_bin(RequestId), 10000))}
    end).

bidi_fail_request(H, RequestId) ->
    with_bidi(H, fun(BH) ->
        {ok, decode(selenium_nif:bidi_network_fail_request(BH, bidi_next_id(H), to_bin(RequestId), 10000))}
    end).

%% Fulfill a paused request with a MOCK response (never hits the network).
%% provide_response/2 defaults to status 200, no content-type, empty body.
bidi_provide_response(H, RequestId) ->
    bidi_provide_response(H, RequestId, 200, <<>>, <<>>).
bidi_provide_response(H, RequestId, Status, ContentType, Body) ->
    with_bidi(H, fun(BH) ->
        {ok, decode(selenium_nif:bidi_network_provide_response(BH, bidi_next_id(H),
            to_bin(RequestId), Status, to_bin(ContentType), to_bin(Body), 10000))}
    end).

%% The network.request id out of a network event: params.request.request.
bidi_event_request_id(#{<<"params">> := #{<<"request">> := #{<<"request">> := Rid}}}) -> Rid;
bidi_event_request_id(_) -> undefined.

%% ---- BiDi internals (ETS-backed per-session state) ----

bidi_table() ->
    case ets:info(?BIDI_TABLE, name) of
        undefined ->
            %% public + named so any process holding the handle can use BiDi.
            try ets:new(?BIDI_TABLE, [named_table, public, set]) of
                _ -> ?BIDI_TABLE
            catch
                error:badarg -> ?BIDI_TABLE
            end;
        _ -> ?BIDI_TABLE
    end.

bidi_register(Handle, WsUrl) ->
    ets:insert(bidi_table(), {Handle, WsUrl, undefined, 1}).

bidi_lookup(Handle) ->
    case ets:info(?BIDI_TABLE, name) of
        undefined -> error;
        _ ->
            case ets:lookup(?BIDI_TABLE, Handle) of
                [{Handle, WsUrl, BidiHandle, NextId}] -> {ok, WsUrl, BidiHandle, NextId};
                [] -> error
            end
    end.

%% Ensure the BiDi WebSocket is open (lazily) then run Fun with its handle.
with_bidi(Handle, Fun) ->
    case bidi_channel(Handle) of
        {ok, BH} -> Fun(BH);
        {error, _} = Err -> Err
    end.

bidi_channel(Handle) ->
    case bidi_lookup(Handle) of
        {ok, <<>>, _, _} ->
            {error, {0, <<"BiDi not available: no webSocketUrl negotiated">>}};
        {ok, _WsUrl, BidiHandle, _NextId} when BidiHandle =/= undefined ->
            {ok, BidiHandle};
        {ok, WsUrl, undefined, _NextId} ->
            case selenium_nif:bidi_open(WsUrl) of
                0 -> {error, {-1, <<"BiDi channel failed to open">>}};
                BH ->
                    ets:update_element(?BIDI_TABLE, Handle, {3, BH}),
                    {ok, BH}
            end;
        error ->
            {error, {0, <<"BiDi not available: unknown session handle">>}}
    end.

%% Atomic monotonic per-channel command id (field 4 in the ETS row), from 1.
bidi_next_id(Handle) ->
    ets:update_counter(?BIDI_TABLE, Handle, {4, 1}) - 1.

%% Close the BiDi channel (if open) and drop the session's ETS row.
bidi_shutdown(Handle) ->
    case bidi_lookup(Handle) of
        {ok, _WsUrl, BidiHandle, _NextId} when BidiHandle =/= undefined ->
            selenium_nif:bidi_close(BidiHandle);
        _ -> ok
    end,
    case ets:info(?BIDI_TABLE, name) of
        undefined -> ok;
        _ -> ets:delete(?BIDI_TABLE, Handle), ok
    end.

join_events(Events) when is_list(Events) ->
    lists:join(<<",">>, [to_bin(E) || E <- Events]);
join_events(Event) ->
    to_bin(Event).

ack(<<>>) -> #{};
ack(Raw) -> decode(Raw).

%% ---- pure engine helpers ----
route(Command) -> selenium_nif:route(to_bin(Command)).
error_code(W3cError) -> selenium_nif:error_code(to_bin(W3cError)).
locator(By, Value) -> selenium_nif:by_locator(to_bin(By), to_bin(Value)).

decode_by(By, Value) -> decode(selenium_nif:by_locator(to_bin(By), to_bin(Value))).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8).

%% ==== minimal JSON (maps with binary keys <-> JSON) ====

encode(V) -> iolist_to_binary(enc(V)).

enc(null) -> <<"null">>;
enc(true) -> <<"true">>;
enc(false) -> <<"false">>;
enc(B) when is_binary(B) -> [<<"\"">>, esc(B), <<"\"">>];
enc(I) when is_integer(I) -> integer_to_binary(I);
enc(F) when is_float(F) -> float_to_binary(F, [{decimals, 10}, compact]);
enc(M) when is_map(M) ->
    Pairs = [[<<"\"">>, esc(to_bin(K)), <<"\":">>, enc(Val)] || {K, Val} <- maps:to_list(M)],
    [<<"{">>, lists:join(<<",">>, Pairs), <<"}">>];
enc(L) when is_list(L) ->
    [<<"[">>, lists:join(<<",">>, [enc(E) || E <- L]), <<"]">>].

esc(B) -> esc(B, <<>>).
esc(<<>>, Acc) -> Acc;
esc(<<$", R/binary>>, Acc) -> esc(R, <<Acc/binary, "\\\"">>);
esc(<<$\\, R/binary>>, Acc) -> esc(R, <<Acc/binary, "\\\\">>);
esc(<<$\n, R/binary>>, Acc) -> esc(R, <<Acc/binary, "\\n">>);
esc(<<$\r, R/binary>>, Acc) -> esc(R, <<Acc/binary, "\\r">>);
esc(<<$\t, R/binary>>, Acc) -> esc(R, <<Acc/binary, "\\t">>);
esc(<<C, R/binary>>, Acc) -> esc(R, <<Acc/binary, C>>).

decode(B) ->
    {V, Rest} = dec(skip_ws(B)),
    <<>> = skip_ws(Rest),
    V.

skip_ws(<<C, R/binary>>) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r -> skip_ws(R);
skip_ws(B) -> B.

dec(<<"null", R/binary>>) -> {null, R};
dec(<<"true", R/binary>>) -> {true, R};
dec(<<"false", R/binary>>) -> {false, R};
dec(<<$", R/binary>>) -> dec_str(R, <<>>);
dec(<<${, R/binary>>) -> dec_obj(skip_ws(R), #{});
dec(<<$[, R/binary>>) -> dec_arr(skip_ws(R), []);
dec(B) -> dec_num(B, <<>>).

dec_str(<<$", R/binary>>, Acc) -> {Acc, R};
dec_str(<<$\\, C, R/binary>>, Acc) ->
    Ch = case C of
             $" -> $"; $\\ -> $\\; $/ -> $/;
             $n -> $\n; $r -> $\r; $t -> $\t; $b -> $\b; $f -> $\f;
             _ -> C
         end,
    case C of
        $u ->
            <<Hex:4/binary, Rest/binary>> = R,
            Cp = binary_to_integer(Hex, 16),
            dec_str(Rest, <<Acc/binary, Cp/utf8>>);
        _ -> dec_str(R, <<Acc/binary, Ch>>)
    end;
dec_str(<<C/utf8, R/binary>>, Acc) -> dec_str(R, <<Acc/binary, C/utf8>>).

dec_obj(<<$}, R/binary>>, M) -> {M, R};
dec_obj(B, M) ->
    <<$", R0/binary>> = skip_ws(B),
    {Key, R1} = dec_str(R0, <<>>),
    <<$:, R2/binary>> = skip_ws(R1),
    {Val, R3} = dec(skip_ws(R2)),
    M2 = maps:put(Key, Val, M),
    case skip_ws(R3) of
        <<$,, R4/binary>> -> dec_obj(skip_ws(R4), M2);
        <<$}, R4/binary>> -> {M2, R4}
    end.

dec_arr(<<$], R/binary>>, L) -> {lists:reverse(L), R};
dec_arr(B, L) ->
    {V, R1} = dec(skip_ws(B)),
    case skip_ws(R1) of
        <<$,, R2/binary>> -> dec_arr(skip_ws(R2), [V | L]);
        <<$], R2/binary>> -> {lists:reverse([V | L]), R2}
    end.

dec_num(<<C, R/binary>>, Acc)
  when (C >= $0 andalso C =< $9); C =:= $-; C =:= $+; C =:= $.; C =:= $e; C =:= $E ->
    dec_num(R, <<Acc/binary, C>>);
dec_num(B, Acc) ->
    N = case binary:match(Acc, [<<".">>, <<"e">>, <<"E">>]) of
            nomatch -> binary_to_integer(Acc);
            _ -> binary_to_float(Acc)
        end,
    {N, B}.
