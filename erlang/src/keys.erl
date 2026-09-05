%% keys — the W3C WebDriver special-key code points for the Erlang binding.
%%
%% Mirrors mainstream Selenium's `Keys` (and the Python reference
%% selenium/webdriver/common/keys.py): the Unicode Private-Use-Area code points
%% the WebDriver spec (§17.4.2) assigns to non-text keys — Enter, Tab, the arrows,
%% the function keys, the modifiers. Each is returned as a UTF-8 binary so it
%% drops straight into selenium:send_keys/3, either alone or concatenated with
%% text:
%%
%%     selenium:send_keys(D, Field, [<<"admin">>, keys:tab(), <<"secret">>, keys:enter()]).
%%
%% (send_keys/3 flattens an iolist, so a list of these + text binaries is one
%% keystroke sequence.) The engine forwards these code points unchanged — they
%% are the exact protocol values, not names to be translated.
-module(keys).

-export([
    null/0, cancel/0, help/0, backspace/0, back_space/0, tab/0, clear/0,
    return/0, enter/0, shift/0, left_shift/0, control/0, left_control/0,
    alt/0, left_alt/0, pause/0, escape/0, space/0, page_up/0, page_down/0,
    'end'/0, home/0, left/0, arrow_left/0, up/0, arrow_up/0, right/0,
    arrow_right/0, down/0, arrow_down/0, insert/0, delete/0, semicolon/0,
    equals/0,
    numpad0/0, numpad1/0, numpad2/0, numpad3/0, numpad4/0, numpad5/0,
    numpad6/0, numpad7/0, numpad8/0, numpad9/0,
    multiply/0, add/0, separator/0, subtract/0, decimal/0, divide/0,
    f1/0, f2/0, f3/0, f4/0, f5/0, f6/0, f7/0, f8/0, f9/0, f10/0, f11/0, f12/0,
    meta/0, command/0
]).

null()        -> <<16#E000/utf8>>.
cancel()      -> <<16#E001/utf8>>.
help()        -> <<16#E002/utf8>>.
backspace()   -> <<16#E003/utf8>>.
back_space()  -> backspace().
tab()         -> <<16#E004/utf8>>.
clear()       -> <<16#E005/utf8>>.
return()      -> <<16#E006/utf8>>.
enter()       -> <<16#E007/utf8>>.
shift()       -> <<16#E008/utf8>>.
left_shift()  -> shift().
control()     -> <<16#E009/utf8>>.
left_control()-> control().
alt()         -> <<16#E00A/utf8>>.
left_alt()    -> alt().
pause()       -> <<16#E00B/utf8>>.
escape()      -> <<16#E00C/utf8>>.
space()       -> <<16#E00D/utf8>>.
page_up()     -> <<16#E00E/utf8>>.
page_down()   -> <<16#E00F/utf8>>.
'end'()       -> <<16#E010/utf8>>.
home()        -> <<16#E011/utf8>>.
left()        -> <<16#E012/utf8>>.
arrow_left()  -> left().
up()          -> <<16#E013/utf8>>.
arrow_up()    -> up().
right()       -> <<16#E014/utf8>>.
arrow_right() -> right().
down()        -> <<16#E015/utf8>>.
arrow_down()  -> down().
insert()      -> <<16#E016/utf8>>.
delete()      -> <<16#E017/utf8>>.
semicolon()   -> <<16#E018/utf8>>.
equals()      -> <<16#E019/utf8>>.

numpad0()     -> <<16#E01A/utf8>>.
numpad1()     -> <<16#E01B/utf8>>.
numpad2()     -> <<16#E01C/utf8>>.
numpad3()     -> <<16#E01D/utf8>>.
numpad4()     -> <<16#E01E/utf8>>.
numpad5()     -> <<16#E01F/utf8>>.
numpad6()     -> <<16#E020/utf8>>.
numpad7()     -> <<16#E021/utf8>>.
numpad8()     -> <<16#E022/utf8>>.
numpad9()     -> <<16#E023/utf8>>.
multiply()    -> <<16#E024/utf8>>.
add()         -> <<16#E025/utf8>>.
separator()   -> <<16#E026/utf8>>.
subtract()    -> <<16#E027/utf8>>.
decimal()     -> <<16#E028/utf8>>.
divide()      -> <<16#E029/utf8>>.

f1()          -> <<16#E031/utf8>>.
f2()          -> <<16#E032/utf8>>.
f3()          -> <<16#E033/utf8>>.
f4()          -> <<16#E034/utf8>>.
f5()          -> <<16#E035/utf8>>.
f6()          -> <<16#E036/utf8>>.
f7()          -> <<16#E037/utf8>>.
f8()          -> <<16#E038/utf8>>.
f9()          -> <<16#E039/utf8>>.
f10()         -> <<16#E03A/utf8>>.
f11()         -> <<16#E03B/utf8>>.
f12()         -> <<16#E03C/utf8>>.

meta()        -> <<16#E03D/utf8>>.
command()     -> meta().
