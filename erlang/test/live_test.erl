%% Live end-to-end + surface test (Erlang): a real headless Chrome session
%% driven through the pure-Aether engine via the NIF, with a gen_tcp content
%% server for a real cookie/nav origin. Run as an escript. Exits 0 on pass/skip,
%% non-zero on failure. Skips if chromedriver is absent.
-module(live_test).
-export([main/1]).

-define(PAGE_ONE, <<"<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
                    "<a id=\"go\" href=\"/two\">to two</a>"
                    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>">>).
-define(PAGE_TWO, <<"<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>">>).
-define(W3C_KEY, <<"element-6066-11e4-a52e-4f735466cecf">>).

main(_) ->
    case which("chromedriver") of
        false ->
            io:format("SKIPPED: chromedriver not on PATH~n"), halt(0);
        DriverBin ->
            run(DriverBin)
    end.

run(DriverBin) ->
    {WebPort, WebPid} = start_content_server(),
    Base = lists:flatten(io_lib:format("http://127.0.0.1:~p", [WebPort])),
    CdPort = free_port(),
    CdPortS = integer_to_list(CdPort),
    Cd = open_port({spawn_executable, DriverBin},
                   [{args, ["--port=" ++ CdPortS]}, {line, 256}, stderr_to_stdout, exit_status]),
    try
        case wait_up(CdPort, 10000) of
            false -> io:format("SKIPPED: chromedriver did not come up~n"), halt(0);
            true -> ok
        end,
        {ok, D} = selenium:chrome("http://127.0.0.1:" ++ CdPortS, chrome_opts()),
        try
            Sid = selenium:session_id(D),
            true = byte_size(Sid) > 0,
            io:format("  ok: session started~n"),

            {ok, _} = selenium:get(D, Base ++ "/one"),
            {ok, <<"Page One">>} = selenium:title(D),
            {ok, Hdr} = selenium:find_element(D, <<"id">>, <<"hdr">>),
            {ok, <<"One">>} = selenium:element_text(D, Hdr),
            io:format("  ok: navigate + find + text~n"),

            %% navigation history
            {ok, Go} = selenium:find_element(D, <<"id">>, <<"go">>),
            {ok, _} = selenium:click(D, Go),
            {ok, <<"Page Two">>} = selenium:title(D),
            {ok, _} = selenium:back(D),
            {ok, <<"Page One">>} = selenium:title(D),
            {ok, _} = selenium:forward(D),
            {ok, <<"Page Two">>} = selenium:title(D),
            {ok, _} = selenium:back(D),
            io:format("  ok: back / forward history~n"),

            %% cookies
            {ok, _} = selenium:delete_all_cookies(D),
            {ok, _} = selenium:add_cookie(D, #{<<"name">> => <<"flavor">>, <<"value">> => <<"mint">>}),
            {ok, C} = selenium:cookie(D, <<"flavor">>),
            <<"mint">> = maps:get(<<"value">>, C),
            {ok, _} = selenium:delete_cookie(D, <<"flavor">>),
            io:format("  ok: cookies~n"),

            %% windows
            {ok, Handles} = selenium:window_handles(D),
            true = length(Handles) >= 1,
            {ok, _} = selenium:set_window_rect(D, #{<<"width">> => 900, <<"height">> => 650}),
            {ok, Rect} = selenium:get_window_rect(D),
            900 = maps:get(<<"width">>, Rect),
            io:format("  ok: windows~n"),

            %% execute_script shapes
            {ok, 42} = selenium:execute_script(D, <<"return 6*7;">>),
            {ok, <<"hi">>} = selenium:execute_script(D, <<"return 'hi';">>),
            {ok, 42} = selenium:execute_script(D, <<"return arguments[0]+arguments[1];">>, [40, 2]),
            io:format("  ok: execute_script~n"),

            %% W3C actions: pointer click on the button
            {ok, Btn} = selenium:find_element(D, <<"id">>, <<"btn">>),
            {ok, BR} = selenium:execute(D, <<"getElementRect">>, #{<<"id">> => Btn}),
            Cx = trunc(maps:get(<<"x">>, BR) + maps:get(<<"width">>, BR) / 2),
            Cy = trunc(maps:get(<<"y">>, BR) + maps:get(<<"height">>, BR) / 2),
            {ok, _} = selenium:perform_actions(D, [#{
                <<"type">> => <<"pointer">>, <<"id">> => <<"mouse">>,
                <<"parameters">> => #{<<"pointerType">> => <<"mouse">>},
                <<"actions">> => [
                    #{<<"type">> => <<"pointerMove">>, <<"duration">> => 0, <<"x">> => Cx, <<"y">> => Cy},
                    #{<<"type">> => <<"pointerDown">>, <<"button">> => 0},
                    #{<<"type">> => <<"pointerUp">>, <<"button">> => 0}
                ]}]),
            {ok, Hdr2} = selenium:find_element(D, <<"id">>, <<"hdr">>),
            {ok, <<"clicked">>} = selenium:element_text(D, Hdr2),
            {ok, _} = selenium:clear_actions(D),
            io:format("  ok: W3C actions~n"),

            %% screenshot -> PNG
            {ok, Shot} = selenium:screenshot(D),
            Raw = base64:decode(Shot),
            <<_, "PNG", _/binary>> = Raw,
            io:format("  ok: screenshot (~p bytes PNG)~n", [byte_size(Raw)]),

            %% negative path
            {error, {17, _}} = selenium:find_element(D, <<"id">>, <<"does-not-exist">>),
            io:format("  ok: no such element error~n"),

            %% WebDriver-BiDi: subscribe to console log entries, emit one via the
            %% classic script channel, and receive the event asynchronously over
            %% the demux — the bidirectional half, over the negotiated webSocketUrl.
            LogEntryAdded = <<"log.entryAdded">>,
            true = selenium:bidi_available(D),
            {ok, Ack} = selenium:bidi_subscribe(D, [LogEntryAdded]),
            <<"success">> = maps:get(<<"type">>, Ack),
            {ok, _} = selenium:execute_script(D, <<"console.log('bidi-hello');">>),
            {ok, Ev} = selenium:bidi_next_event(D, LogEntryAdded, 8000),
            true = is_map(Ev),
            LogEntryAdded = maps:get(<<"method">>, Ev),
            true = binary:match(iolist_to_binary(io_lib:format("~p", [Ev])),
                                <<"bidi-hello">>) =/= nomatch,
            {ok, Status} = selenium:bidi_command(D, <<"session.status">>, #{}, 10000),
            <<"success">> = maps:get(<<"type">>, Status),
            io:format("  ok: BiDi (log.entryAdded event + session.status command)~n"),

            %% script.evaluate — the richer alternative to execute_script.
            TopCtx = selenium:bidi_top_context(D),
            true = is_binary(TopCtx) andalso byte_size(TopCtx) > 0,
            {ok, 42} = selenium:bidi_evaluate_value(D, <<"6*7">>),
            {ok, 42} = selenium:bidi_evaluate_value(D, <<"Promise.resolve(41+1)">>),
            io:format("  ok: BiDi evaluate (6*7 -> 42, Promise -> 42)~n"),

            %% atom-backed commands: isDisplayed / getAttribute / relative
            %% locators — the shared JS atoms run in-page by the engine (the
            %% same atoms every other binding uses), reached through the NIF.
            AtomsHtml = <<"<!doctype html><title>Atoms</title>"
                          "<h1 id='hdr'>Header</h1>"
                          "<button id='btn'>Click</button>"
                          "<p id='gone' style='display:none'>hidden</p>"
                          "<a id='lnk' href='https://example.com/x'>link</a>">>,
            {ok, _} = selenium:get(D, <<"data:text/html,", (uri_pct(AtomsHtml))/binary>>),
            {ok, AHdr} = selenium:find_element(D, <<"id">>, <<"hdr">>),
            {ok, AGone} = selenium:find_element(D, <<"id">>, <<"gone">>),
            {ok, ALnk} = selenium:find_element(D, <<"id">>, <<"lnk">>),
            true = selenium:is_displayed(D, AHdr),
            false = selenium:is_displayed(D, AGone),
            Href = selenium:get_attribute(D, ALnk, <<"href">>),
            true = is_binary(Href),
            true = binary:match(Href, <<"example.com/x">>) =/= nomatch,
            {ok, Below} = selenium:find_relative(D, <<"button">>,
                              [#{<<"kind">> => <<"below">>, <<"sel">> => <<"#hdr">>}]),
            true = length(Below) >= 1,
            io:format("  ok: atoms (is_displayed hdr=true gone=false, "
                      "get_attribute href=~s, find_relative below #hdr=~p)~n",
                      [Href, length(Below)]),

            io:format("PASS: Erlang live surface test green~n")
        after
            selenium:quit(D)
        end
    after
        catch port_close(Cd),
        WebPid ! stop
    end,
    halt(0).

%% Public alias so the test can reach the raw execute for getElementRect.
%% (selenium:execute/3 is not exported; use a thin re-entry.)

%% Minimal percent-encoding so the HTML rides safely in a data: URL (spaces,
%% quotes, '#' and the like would otherwise derail the URL parse).
%% Headless-chrome caps; point at an explicit binary when SEL_CHROME_BINARY is
%% set (a box with no system Chrome but a cached Chrome-for-Testing).
chrome_opts() ->
    Args = [<<"--headless=new">>, <<"--no-sandbox">>, <<"--disable-gpu">>, <<"--disable-dev-shm-usage">>],
    ChromeOpts0 = #{<<"args">> => Args},
    ChromeOpts = case os:getenv("SEL_CHROME_BINARY") of
        false -> ChromeOpts0;
        "" -> ChromeOpts0;
        Bin -> ChromeOpts0#{<<"binary">> => list_to_binary(Bin)}
    end,
    #{<<"goog:chromeOptions">> => ChromeOpts}.

uri_pct(Bin) -> uri_pct(Bin, <<>>).
uri_pct(<<>>, Acc) -> Acc;
uri_pct(<<C, R/binary>>, Acc)
  when (C >= $A andalso C =< $Z); (C >= $a andalso C =< $z);
       (C >= $0 andalso C =< $9); C =:= $-; C =:= $_; C =:= $.; C =:= $~ ->
    uri_pct(R, <<Acc/binary, C>>);
uri_pct(<<C, R/binary>>, Acc) ->
    Hex = list_to_binary(io_lib:format("%~2.16.0B", [C])),
    uri_pct(R, <<Acc/binary, Hex/binary>>).

which(Cmd) ->
    case os:find_executable(Cmd) of
        false -> false;
        Path -> Path
    end.

free_port() ->
    {ok, S} = gen_tcp:listen(0, [{ip, {127,0,0,1}}]),
    {ok, Port} = inet:port(S),
    gen_tcp:close(S),
    Port.

wait_up(_Port, T) when T =< 0 -> false;
wait_up(Port, T) ->
    case gen_tcp:connect({127,0,0,1}, Port, [], 500) of
        {ok, S} -> gen_tcp:close(S), true;
        _ -> timer:sleep(100), wait_up(Port, T - 100)
    end.

%% A minimal gen_tcp HTTP/1.1 content server on its own process.
start_content_server() ->
    {ok, L} = gen_tcp:listen(0, [binary, {ip, {127,0,0,1}}, {active, false}, {reuseaddr, true}]),
    {ok, Port} = inet:port(L),
    Pid = spawn(fun() -> accept_loop(L) end),
    {Port, Pid}.

accept_loop(L) ->
    case gen_tcp:accept(L, 200) of
        {ok, Sock} -> spawn(fun() -> serve(Sock) end), accept_loop(L);
        {error, timeout} ->
            receive stop -> gen_tcp:close(L) after 0 -> accept_loop(L) end;
        {error, _} -> ok
    end.

serve(Sock) ->
    case gen_tcp:recv(Sock, 0, 2000) of
        {ok, Req} ->
            Body = case binary:match(Req, <<"/two">>) of nomatch -> ?PAGE_ONE; _ -> ?PAGE_TWO end,
            Resp = [<<"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ">>,
                    integer_to_binary(byte_size(Body)), <<"\r\nConnection: close\r\n\r\n">>, Body],
            gen_tcp:send(Sock, Resp);
        _ -> ok
    end,
    gen_tcp:close(Sock).
