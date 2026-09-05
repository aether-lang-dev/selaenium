%% convenience_test — EUnit for the Erlang convenience tier (no browser).
%%
%% Covers the additive helpers in `selenium` + the `keys` module without a live
%% driver, by standing up a FAKE `selenium_nif` in place of the real NIF. The
%% fake records every execute/3 call (name + decoded params) and returns canned
%% JSON, so the tests can assert on the W3C payload the binding builds and drive
%% the select / wait / action helpers over a scripted set of responses.
%%
%% Loading a hand-written `selenium_nif` module shadows the NIF stub: this is a
%% pure-BEAM module (no -on_load), so `selenium` calls resolve to it. The fake
%% keeps its script + call log in ETS keyed by name.
-module(convenience_test).
-include_lib("eunit/include/eunit.hrl").

%% escript entry so this runs through the same run_main seam as live_test
%% (erlang.eunit's run_main path): run the EUnit suite, halt 0 on pass / 1 on
%% fail. No browser needed — the fake NIF stands in for the real .so.
-export([main/1]).
main(_) ->
    case eunit:test(?MODULE, [verbose]) of
        ok -> halt(0);
        _ -> halt(1)
    end.

%% ---- fake NIF install / teardown ----------------------------------------

%% Compile + load a fake `selenium_nif` from source embedded here, so the test
%% needs no real .so. Returns ok; call fake_nif_unload/0 to purge it.
fake_nif_load() ->
    Src = fake_nif_src(),
    {ok, selenium_nif, Bin} =
        compile:forms(merl_scan(Src), [return_errors, binary]),
    code:purge(selenium_nif),
    {module, selenium_nif} = code:load_binary(selenium_nif, "selenium_nif_fake", Bin),
    ok.

merl_scan(Src) ->
    {ok, Toks, _} = erl_scan:string(Src),
    Forms = split_forms(Toks, [], []),
    [begin {ok, F} = erl_parse:parse_form(Ts), F end || Ts <- Forms].

split_forms([], _Cur, Acc) -> lists:reverse(Acc);
split_forms([{dot, _} = D | Rest], Cur, Acc) ->
    split_forms(Rest, [], [lists:reverse([D | Cur]) | Acc]);
split_forms([T | Rest], Cur, Acc) ->
    split_forms(Rest, [T | Cur], Acc).

%% The fake module source. execute/3 records {name, params-binary} and returns
%% 0, leaving a scripted JSON blob in last_value keyed by name (a FIFO queue per
%% name in the ets table `fake_nif`). by_locator builds the same {using,value}
%% JSON the real engine returns. last_value/last_error_code/last_error read the
%% ets state the way `selenium:execute/3` expects.
fake_nif_src() ->
    "-module(selenium_nif).\n"
    "-export([execute/3, last_value/1, last_error_code/1, last_error/1,\n"
    "         by_locator/2, get_attribute/3, is_displayed/2]).\n"
    "get_attribute(_H, ElemId, Name) ->\n"
    "    execute(_H, <<\"getAttribute\">>,\n"
    "        iolist_to_binary([ElemId, <<\"/\">>, Name])), 0.\n"
    "is_displayed(_H, ElemId) ->\n"
    "    execute(_H, <<\"isDisplayed\">>, ElemId), 0.\n"
    "execute(_H, Name, Params) ->\n"
    "    ets:insert(fake_nif, {call, {Name, Params}}),\n"
    "    Old = case ets:lookup(fake_nif, calls) of [{calls,L}]->L; _->[] end,\n"
    "    ets:insert(fake_nif, {calls, Old ++ [{Name, Params}]}),\n"
    "    Q = case ets:lookup(fake_nif, {resp, Name}) of [{_,QL}]->QL; _->[] end,\n"
    "    case Q of\n"
    "        [{err, Code, Msg} | Tail] ->\n"
    "            ets:insert(fake_nif, {{resp, Name}, Tail}),\n"
    "            ets:insert(fake_nif, {value, <<>>}),\n"
    "            ets:insert(fake_nif, {ecode, Code}),\n"
    "            ets:insert(fake_nif, {emsg, Msg}), Code;\n"
    "        [Head | Tail] ->\n"
    "            ets:insert(fake_nif, {{resp, Name}, Tail}),\n"
    "            ets:insert(fake_nif, {value, Head}),\n"
    "            ets:insert(fake_nif, {ecode, 0}), 0;\n"
    "        [] -> ets:insert(fake_nif, {value, <<>>}),\n"
    "            ets:insert(fake_nif, {ecode, 0}), 0\n"
    "    end.\n"
    "last_value(_H) -> case ets:lookup(fake_nif, value) of [{value,V}]->V; _-><<>> end.\n"
    "last_error_code(_H) -> case ets:lookup(fake_nif, ecode) of [{ecode,C}]->C; _->0 end.\n"
    "last_error(_H) -> case ets:lookup(fake_nif, emsg) of [{emsg,M}]->M; _-><<>> end.\n"
    "by_locator(Strategy, Value) ->\n"
    "    iolist_to_binary([<<\"{\\\"using\\\":\\\"\">>, Strategy,\n"
    "        <<\"\\\",\\\"value\\\":\\\"\">>, Value, <<\"\\\"}\">>]).\n".

fake_nif_unload() ->
    catch code:purge(selenium_nif),
    catch code:delete(selenium_nif),
    ok.

setup() ->
    catch ets:delete(fake_nif),
    ets:new(fake_nif, [named_table, public, set]),
    fake_nif_load(),
    ok.

cleanup(_) ->
    fake_nif_unload(),
    catch ets:delete(fake_nif),
    ok.

%% Queue a JSON response (a binary) for the next execute/3 with this command name.
script(Name, JsonBin) ->
    Q = case ets:lookup(fake_nif, {resp, Name}) of [{_,L}]->L; _->[] end,
    ets:insert(fake_nif, {{resp, Name}, Q ++ [JsonBin]}).

%% Queue an ERROR response (W3C code + message) for the next execute/3 with this
%% command name — drives the {error, {Code, Msg}} path in selenium:execute/3.
script_err(Name, Code, Msg) ->
    Q = case ets:lookup(fake_nif, {resp, Name}) of [{_,L}]->L; _->[] end,
    ets:insert(fake_nif, {{resp, Name}, Q ++ [{err, Code, Msg}]}).

%% All recorded {Name, ParamsBin} execute/3 calls, in order.
calls() ->
    case ets:lookup(fake_nif, calls) of [{calls,L}]->L; _->[] end.

%% The params binary of the last execute/3 for the given command name.
last_params(Name) ->
    Matching = [P || {N, P} <- calls(), N =:= to_bin(Name)],
    lists:last(Matching).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L).

%% ---- keys (pure, no NIF needed) -----------------------------------------

keys_test() ->
    %% Exact W3C PUA code points (W3C §17.4.2), UTF-8 encoded.
    ?assertEqual(<<16#E007/utf8>>, keys:enter()),
    ?assertEqual(<<16#E004/utf8>>, keys:tab()),
    ?assertEqual(<<16#E00C/utf8>>, keys:escape()),
    ?assertEqual(<<16#E003/utf8>>, keys:backspace()),
    ?assertEqual(<<16#E017/utf8>>, keys:delete()),
    ?assertEqual(<<16#E012/utf8>>, keys:left()),
    ?assertEqual(<<16#E015/utf8>>, keys:down()),
    ?assertEqual(<<16#E031/utf8>>, keys:f1()),
    ?assertEqual(<<16#E03C/utf8>>, keys:f12()),
    ?assertEqual(<<16#E03D/utf8>>, keys:meta()),
    %% RETURN (U+E006) and ENTER (U+E007) are distinct code points.
    ?assertEqual(<<16#E006/utf8>>, keys:return()),
    ?assertNotEqual(keys:return(), keys:enter()),
    %% Aliases share the code point of their canonical key.
    ?assertEqual(keys:backspace(), keys:back_space()),
    ?assertEqual(keys:shift(), keys:left_shift()),
    ?assertEqual(keys:control(), keys:left_control()),
    ?assertEqual(keys:meta(), keys:command()),
    ?assertEqual(keys:left(), keys:arrow_left()),
    %% Each is a 3-byte UTF-8 sequence in the PUA range.
    ?assertEqual(3, byte_size(keys:enter())),
    %% Contiguity: F2 is one code point past F1.
    <<F1/utf8>> = keys:f1(),
    <<F2/utf8>> = keys:f2(),
    ?assertEqual(F1 + 1, F2).

%% ---- wait_until: returns on true / {error,timeout} on timeout ------------

wait_until_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        [
         %% Predicate true straight away -> {ok, true}, no waiting.
         ?_assertEqual({ok, true},
             selenium:wait_until(0, 1000, fun(_) -> true end)),
         %% Predicate never true within a tiny budget -> {error, timeout}.
         ?_assertEqual({error, timeout},
             selenium:wait_until(0, 0, fun(_) -> false end)),
         %% Predicate flips true after a couple of polls -> {ok, true}.
         fun() ->
             Counter = counters:new(1, []),
             R = selenium:wait_until(0, 3000, fun(_) ->
                     counters:add(Counter, 1, 1),
                     counters:get(Counter, 1) >= 3
                 end),
             ?assertEqual({ok, true}, R),
             ?assert(counters:get(Counter, 1) >= 3)
         end
        ]
    end}.

%% ---- wait_for_text_contains over the fake seam ---------------------------

wait_for_text_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            %% getElementText returns "pending" then "Approved": contains
            %% "Approv" should succeed on the second poll.
            script(<<"getElementText">>, <<"\"pending\"">>),
            script(<<"getElementText">>, <<"\"Approved\"">>),
            ?assertEqual({ok, true},
                selenium:wait_for_text_contains(0, <<"el-1">>, <<"Approv">>, 3000))
        end
    end}.

%% ---- select picks the right option (find + click) ------------------------

select_by_value_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            %% findChildElements(option) -> three option refs.
            script(<<"findChildElements">>, options_json([<<"opt-a">>, <<"opt-b">>, <<"opt-c">>])),
            %% getAttribute(value) for each until the match: "a","b" -> stop at b.
            script(<<"getAttribute">>, <<"\"a\"">>),
            script(<<"getAttribute">>, <<"\"b\"">>),
            %% is_selected(opt-b) -> false, so it gets clicked.
            script(<<"isElementSelected">>, <<"false">>),
            script(<<"clickElement">>, <<>>),
            ?assertEqual({ok, <<"opt-b">>},
                selenium:select_by_value(0, <<"sel-1">>, <<"b">>)),
            %% The findChildElements was scoped to the <select> id.
            P = last_params(<<"findChildElements">>),
            ?assert(binary:match(P, <<"sel-1">>) =/= nomatch),
            ?assert(binary:match(P, <<"tag name">>) =/= nomatch),
            %% The click targeted opt-b.
            CP = last_params(<<"clickElement">>),
            ?assert(binary:match(CP, <<"opt-b">>) =/= nomatch)
        end
    end}.

select_already_selected_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"findChildElements">>, options_json([<<"opt-x">>])),
            script(<<"getElementText">>, <<"\"Spain\"">>),
            %% Already selected -> no click, still {ok, opt-x}.
            script(<<"isElementSelected">>, <<"true">>),
            ?assertEqual({ok, <<"opt-x">>},
                selenium:select_by_visible_text(0, <<"sel">>, <<"Spain">>)),
            %% No clickElement call happened.
            ?assertEqual([], [1 || {N, _} <- calls(), N =:= <<"clickElement">>])
        end
    end}.

select_by_index_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"findChildElements">>, options_json([<<"o0">>, <<"o1">>, <<"o2">>])),
            script(<<"isElementSelected">>, <<"false">>),
            script(<<"clickElement">>, <<>>),
            ?assertEqual({ok, <<"o1">>},
                selenium:select_by_index(0, <<"sel">>, 1)),
            %% Out of range -> no_such_option (no click).
            script(<<"findChildElements">>, options_json([<<"o0">>])),
            ?assertEqual({error, no_such_option},
                selenium:select_by_index(0, <<"sel">>, 5))
        end
    end}.

select_no_match_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"findChildElements">>, options_json([<<"o0">>])),
            script(<<"getAttribute">>, <<"\"zzz\"">>),
            ?assertEqual({error, no_such_option},
                selenium:select_by_value(0, <<"sel">>, <<"nope">>))
        end
    end}.

%% ---- action gestures build the correct W3C JSON --------------------------

action_click_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_click(0, <<"btn-1">>),
            P = last_params(<<"actions">>),
            %% One mouse pointer device.
            ?assert(binary:match(P, <<"\"type\":\"pointer\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"id\":\"mouse\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"pointerType\":\"mouse\"">>) =/= nomatch),
            %% move-to-origin using the element key, then down/up button 0.
            ?assert(binary:match(P, <<"element-6066-11e4-a52e-4f735466cecf">>) =/= nomatch),
            ?assert(binary:match(P, <<"btn-1">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"type\":\"pointerMove\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"type\":\"pointerDown\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"type\":\"pointerUp\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"button\":0">>) =/= nomatch)
        end
    end}.

action_context_click_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_context_click(0, <<"row">>),
            P = last_params(<<"actions">>),
            %% Right button = 2.
            ?assert(binary:match(P, <<"\"button\":2">>) =/= nomatch),
            ?assert(binary:match(P, <<"row">>) =/= nomatch)
        end
    end}.

action_double_click_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_double_click(0, <<"cell">>),
            P = last_params(<<"actions">>),
            %% Two down/up pairs: count the pointerDown occurrences.
            ?assertEqual(2, count(P, <<"\"type\":\"pointerDown\"">>)),
            ?assertEqual(2, count(P, <<"\"type\":\"pointerUp\"">>))
        end
    end}.

action_drag_and_drop_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_drag_and_drop(0, <<"src">>, <<"dst">>),
            P = last_params(<<"actions">>),
            %% Both endpoints appear, and there are two pointerMove steps
            %% (to source, then to target).
            ?assert(binary:match(P, <<"src">>) =/= nomatch),
            ?assert(binary:match(P, <<"dst">>) =/= nomatch),
            ?assertEqual(2, count(P, <<"\"type\":\"pointerMove\"">>)),
            ?assertEqual(1, count(P, <<"\"type\":\"pointerDown\"">>)),
            ?assertEqual(1, count(P, <<"\"type\":\"pointerUp\"">>))
        end
    end}.

action_move_to_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_move_to(0, <<"hover">>),
            P = last_params(<<"actions">>),
            %% Just a move, no button press.
            ?assertEqual(1, count(P, <<"\"type\":\"pointerMove\"">>)),
            ?assertEqual(0, count(P, <<"\"type\":\"pointerDown\"">>))
        end
    end}.

%% ---- is_enabled / is_selected wrappers -----------------------------------

element_predicate_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"isElementEnabled">>, <<"true">>),
            ?assertEqual(true, selenium:is_enabled(0, <<"e">>)),
            script(<<"isElementSelected">>, <<"false">>),
            ?assertEqual(false, selenium:is_selected(0, <<"e">>)),
            %% They hit the dedicated W3C endpoints (not a generic execute name).
            ?assert(lists:any(fun({N,_}) -> N =:= <<"isElementEnabled">> end, calls())),
            ?assert(lists:any(fun({N,_}) -> N =:= <<"isElementSelected">> end, calls()))
        end
    end}.

%% ---- full-feature-bar additions -----------------------------------------

%% Frame switching: index, element ref, and default/parent.
frame_switch_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"switchToFrame">>, <<>>),
            {ok, _} = selenium:switch_to_frame(0, 2),
            ?assert(binary:match(last_params(<<"switchToFrame">>), <<"\"id\":2">>) =/= nomatch),
            script(<<"switchToFrame">>, <<>>),
            {ok, _} = selenium:switch_to_frame(0, <<"frame-el">>),
            P = last_params(<<"switchToFrame">>),
            ?assert(binary:match(P, <<"frame-el">>) =/= nomatch),
            ?assert(binary:match(P, <<"element-6066-11e4-a52e-4f735466cecf">>) =/= nomatch),
            script(<<"switchToFrame">>, <<>>),
            {ok, _} = selenium:switch_to_default_content(0),
            ?assert(binary:match(last_params(<<"switchToFrame">>), <<"\"id\":null">>) =/= nomatch),
            script(<<"switchToFrameParent">>, <<>>),
            {ok, _} = selenium:switch_to_parent_frame(0),
            ?assert(lists:any(fun({N,_}) -> N =:= <<"switchToFrameParent">> end, calls()))
        end
    end}.

%% new_window returns the handle from the {handle: ...} reply; close_window
%% issues `close`.
window_lifecycle_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"newWindow">>, <<"{\"handle\":\"win-2\",\"type\":\"tab\"}">>),
            ?assertEqual({ok, <<"win-2">>}, selenium:new_window(0, <<"tab">>)),
            ?assert(binary:match(last_params(<<"newWindow">>), <<"\"type\":\"tab\"">>) =/= nomatch),
            script(<<"close">>, <<"[\"win-1\"]">>),
            {ok, _} = selenium:close_window(0),
            ?assert(lists:any(fun({N,_}) -> N =:= <<"close">> end, calls()))
        end
    end}.

%% css_value / active_element / clear / print_pdf hit their W3C endpoints.
misc_driver_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"getElementValueOfCssProperty">>, <<"\"rgb(1, 2, 3)\"">>),
            script(<<"getElementValueOfCssProperty">>, <<"\"rgb(1, 2, 3)\"">>),
            ?assertEqual({ok, <<"rgb(1, 2, 3)">>}, selenium:css_value(0, <<"e">>, <<"color">>)),
            ?assertEqual({ok, <<"rgb(1, 2, 3)">>}, selenium:value_of_css_property(0, <<"e">>, <<"color">>)),
            script(<<"getActiveElement">>, <<"{\"element-6066-11e4-a52e-4f735466cecf\":\"focused\"}">>),
            ?assertEqual({ok, <<"focused">>}, selenium:active_element(0)),
            script(<<"clearElement">>, <<>>),
            {ok, _} = selenium:clear(0, <<"input-1">>),
            ?assert(binary:match(last_params(<<"clearElement">>), <<"input-1">>) =/= nomatch),
            script(<<"printPage">>, <<"\"JVBER...\"">>),
            ?assertEqual({ok, <<"JVBER...">>}, selenium:print_pdf(0))
        end
    end}.

%% exists -> true/false; alert_present maps code 15 to false.
presence_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"findElement">>, <<"{\"element-6066-11e4-a52e-4f735466cecf\":\"e1\"}">>),
            ?assertEqual({ok, true}, selenium:exists(0, {css, <<"#a">>})),
            script_err(<<"findElement">>, 17, <<"no such element">>),
            ?assertEqual({ok, false}, selenium:exists(0, {css, <<"#missing">>})),
            script(<<"getAlertText">>, <<"\"hi\"">>),
            ?assertEqual({ok, true}, selenium:alert_present(0)),
            script_err(<<"getAlertText">>, 15, <<"no such alert">>),
            ?assertEqual({ok, false}, selenium:alert_present(0))
        end
    end}.

%% Select query helpers: all_selected / first_selected / is_multiple / deselect.
select_query_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            %% all_selected_options: 3 options, middle one selected.
            script(<<"findChildElements">>, options_json([<<"o1">>, <<"o2">>, <<"o3">>])),
            script(<<"isElementSelected">>, <<"false">>),
            script(<<"isElementSelected">>, <<"true">>),
            script(<<"isElementSelected">>, <<"false">>),
            ?assertEqual({ok, [<<"o2">>]}, selenium:all_selected_options(0, <<"sel">>)),
            %% first_selected_option: same scripted shape.
            script(<<"findChildElements">>, options_json([<<"o1">>, <<"o2">>, <<"o3">>])),
            script(<<"isElementSelected">>, <<"false">>),
            script(<<"isElementSelected">>, <<"true">>),
            script(<<"isElementSelected">>, <<"false">>),
            ?assertEqual({ok, <<"o2">>}, selenium:first_selected_option(0, <<"sel">>)),
            %% is_multiple reads the `multiple` attribute (getAttribute atom).
            script(<<"getAttribute">>, <<"\"true\"">>),
            ?assertEqual({ok, true}, selenium:is_multiple(0, <<"sel">>))
        end
    end}.

%% Keyboard chord: Ctrl held around a click, released after.
action_chord_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_chord(0, [keys:control()], <<"cell">>),
            P = last_params(<<"actions">>),
            %% A keyboard device is present, with a keyDown and a keyUp.
            ?assert(binary:match(P, <<"\"type\":\"key\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"id\":\"keyboard\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"type\":\"keyDown\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"\"type\":\"keyUp\"">>) =/= nomatch),
            %% and a click in the middle.
            ?assert(binary:match(P, <<"\"type\":\"pointerDown\"">>) =/= nomatch),
            ?assert(binary:match(P, <<"cell">>) =/= nomatch)
        end
    end}.

%% click_and_hold presses without releasing; release lifts button 0.
action_hold_release_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_click_and_hold(0, <<"knob">>),
            P1 = last_params(<<"actions">>),
            ?assertEqual(1, count(P1, <<"\"type\":\"pointerDown\"">>)),
            ?assertEqual(0, count(P1, <<"\"type\":\"pointerUp\"">>)),
            script(<<"actions">>, <<>>),
            {ok, _} = selenium:action_release(0),
            P2 = last_params(<<"actions">>),
            ?assertEqual(1, count(P2, <<"\"type\":\"pointerUp\"">>))
        end
    end}.

%% wait_until_not returns once the predicate flips false; wait_for_title_is
%% matches on equality (not substring).
wait_variants_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        fun() ->
            %% title equality: first "Loading", then "Ready".
            script(<<"getTitle">>, <<"\"Loading\"">>),
            script(<<"getTitle">>, <<"\"Ready\"">>),
            ?assertEqual({ok, true}, selenium:wait_for_title_is(0, <<"Ready">>, 2000)),
            %% until_not: element present then gone.
            script(<<"findElement">>, <<"{\"element-6066-11e4-a52e-4f735466cecf\":\"e\"}">>),
            script_err(<<"findElement">>, 17, <<"no such element">>),
            ?assertEqual({ok, true}, selenium:wait_until_gone(0, css, <<"#x">>, 2000))
        end
    end}.

%% ---- helpers -------------------------------------------------------------

%% A findElements-style JSON array of element refs.
options_json(Ids) ->
    Objs = [iolist_to_binary([<<"{\"element-6066-11e4-a52e-4f735466cecf\":\"">>, Id, <<"\"}">>])
            || Id <- Ids],
    iolist_to_binary([<<"[">>, lists:join(<<",">>, Objs), <<"]">>]).

%% Count non-overlapping occurrences of Needle in Hay.
count(Hay, Needle) ->
    length(binary:matches(Hay, Needle)).
