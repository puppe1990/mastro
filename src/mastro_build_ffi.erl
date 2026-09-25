-module(mastro_build_ffi).
-export([run_cmd/1]).

run_cmd(Cmd) ->
    Result = os:cmd(binary_to_list(Cmd)),
    %% A child that prints unicode (gleam's error renderer does) hands back
    %% codepoints, not bytes, so plain list_to_binary/1 would raise.
    unicode:characters_to_binary(Result).
