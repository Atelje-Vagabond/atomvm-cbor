-module(avm_cbor_branch_counter).

-export([start/0, hit/2, hits/0]).

-define(TABLE, avm_cbor_branch_coverage).

start() ->
    case ets:whereis(?TABLE) of
        undefined -> ok;
        _ -> ets:delete(?TABLE)
    end,
    _ = ets:new(?TABLE, [named_table, public, set]),
    ok.

hit(Module, Id) ->
    true = ets:insert(?TABLE, {{Module, Id}}),
    true.

hits() ->
    [Key || {Key} <- ets:tab2list(?TABLE)].
