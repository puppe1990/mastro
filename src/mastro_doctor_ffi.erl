-module(mastro_doctor_ffi).
-export([halt/1]).

%% Exit with a status the shell can act on. Flush first so the report is
%% not cut off when doctor is piped.
halt(Code) ->
    erlang:halt(Code, [{flush, true}]).
