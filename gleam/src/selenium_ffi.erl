-module(selenium_ffi).

%% Minimal Erlang FFI shim for the Gleam binding. os:getenv/1 yields an Erlang
%% string (char list) or the atom `false` when unset; Gleam's String is an
%% Erlang binary, so return the value as a binary (empty binary when unset) to
%% match the `-> String` type at the Gleam boundary.
-export([getenv/1]).

getenv(Name) when is_binary(Name) ->
    getenv(binary_to_list(Name));
getenv(Name) ->
    case os:getenv(Name) of
        false -> <<>>;
        Value -> unicode:characters_to_binary(Value)
    end.
