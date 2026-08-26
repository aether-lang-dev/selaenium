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
    execute/3,
    execute_script/2, execute_script/3,
    window_handles/1, current_window_handle/1, set_window_rect/2, get_window_rect/1,
    add_cookie/2, cookies/1, cookie/2, delete_cookie/2, delete_all_cookies/1,
    perform_actions/2, clear_actions/1,
    set_timeouts/2, screenshot/1,
    session_id/1, quit/1,
    route/1, error_code/1, locator/2
]).

-define(W3C_KEY, <<"element-6066-11e4-a52e-4f735466cecf">>).

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
            Payload = #{<<"capabilities">> => #{<<"alwaysMatch">> => Caps}},
            case execute(Handle, <<"newSession">>, Payload) of
                {ok, _} -> {ok, Handle};
                Err -> selenium_nif:close(Handle), Err
            end
    end.

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
    R = execute(H, <<"quit">>, #{}),
    selenium_nif:close(H),
    R.

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
