-module(mastro_console_ffi).
-export([read_line/0]).

%% One line from stdin, without the trailing newline. `eof` and read errors
%% become `{error, nil}`, which the REPL treats as "stop".
read_line() ->
    case io:get_line("") of
        eof -> {error, nil};
        {error, _Reason} -> {error, nil};
        Line -> {ok, unicode:characters_to_binary(string:trim(Line, trailing, "\n"))}
    end.
