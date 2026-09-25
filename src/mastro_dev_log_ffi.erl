-module(mastro_dev_log_ffi).
-export([install/1, installed/0, uninstall/0]).

%% One process-global slot. A generated app has a single dev log store, so a
%% plain persistent_term beats a name registry: reads are lock-free and the
%% value disappears when the node stops.
-define(KEY, {mastro_dev_log, store}).

install(Store) ->
    persistent_term:put(?KEY, Store),
    nil.

installed() ->
    case persistent_term:get(?KEY, undefined) of
        undefined -> {error, nil};
        Store -> {ok, Store}
    end.

uninstall() ->
    persistent_term:erase(?KEY),
    nil.
