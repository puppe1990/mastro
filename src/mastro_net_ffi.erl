-module(mastro_net_ffi).
-export([port_available/1, listen/1, listen_random/0, close/1, lan_addresses/0, now_ms/0]).

%% Whether a TCP port can be taken on the loopback interface right now.
port_available(Port) ->
    case gen_tcp:listen(Port, [{reuseaddr, true}, {ip, {127, 0, 0, 1}}]) of
        {ok, Socket} ->
            gen_tcp:close(Socket),
            true;
        {error, _Reason} ->
            false
    end.

%% Hold a port open, so a caller (or a test) can take one on purpose.
listen(Port) ->
    case gen_tcp:listen(Port, [{reuseaddr, false}, {ip, {127, 0, 0, 1}}]) of
        {ok, Socket} ->
            {ok, Socket};
        {error, Reason} ->
            {error, atom_to_binary(Reason, utf8)}
    end.

%% Take whatever free port the OS hands out, and report which one it was.
%% Tests use this to occupy a known-busy port on purpose.
listen_random() ->
    case gen_tcp:listen(0, [{reuseaddr, false}, {ip, {127, 0, 0, 1}}]) of
        {ok, Socket} ->
            case inet:port(Socket) of
                {ok, Port} ->
                    {ok, {Socket, Port}};
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    {error, atom_to_binary(Reason, utf8)}
            end;
        {error, Reason} ->
            {error, atom_to_binary(Reason, utf8)}
    end.

close(Socket) ->
    gen_tcp:close(Socket),
    nil.

%% IPv4 addresses the LAN can reach, loopback and link-local left out.
lan_addresses() ->
    case inet:getifaddrs() of
        {ok, Interfaces} ->
            [list_to_binary(inet:ntoa(Address))
             || {_Name, Options} <- Interfaces,
                {addr, Address} <- [proplists:lookup(addr, Options)],
                is_lan(Address, Options)];
        {error, _Reason} ->
            []
    end.

is_lan(Address, Options) when tuple_size(Address) =:= 4 ->
    Flags = proplists:get_value(flags, Options, []),
    lists:member(up, Flags)
        andalso not lists:member(loopback, Flags)
        andalso Address =/= {0, 0, 0, 0}
        andalso not is_link_local(Address);
is_lan(_Address, _Options) ->
    false.

is_link_local({169, 254, _, _}) -> true;
is_link_local(_Address) -> false.

now_ms() ->
    erlang:monotonic_time(millisecond).
