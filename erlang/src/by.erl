%% by — Selenium-style By locator factory for the Erlang binding.
%%
%% Each function returns a {Strategy, Value} locator tuple (binaries) that
%% selenium:find_element/2 and selenium:find_elements/2 accept, mirroring
%% Selenium's By.id(...)/By.className(...) factory. Strategy strings match the
%% ones the shared engine's by_locator understands; class_name maps to the W3C
%% "class name" (NOT "className"), matching every other Selenium binding.
-module(by).

-export([id/1, name/1, class_name/1, css/1, css_selector/1, tag_name/1,
         link_text/1, partial_link_text/1, xpath/1]).

-type locator() :: {binary(), binary()}.
-export_type([locator/0]).

id(V) -> {<<"id">>, to_bin(V)}.
name(V) -> {<<"name">>, to_bin(V)}.
class_name(V) -> {<<"class name">>, to_bin(V)}.
css(V) -> css_selector(V).
css_selector(V) -> {<<"css selector">>, to_bin(V)}.
tag_name(V) -> {<<"tag name">>, to_bin(V)}.
link_text(V) -> {<<"link text">>, to_bin(V)}.
partial_link_text(V) -> {<<"partial link text">>, to_bin(V)}.
xpath(V) -> {<<"xpath">>, to_bin(V)}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8).
