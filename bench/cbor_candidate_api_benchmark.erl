-module(cbor_candidate_api_benchmark).

-export([start/0]).

-define(ITERATIONS, 50).
-define(WATCHDOG_CHUNK_ITERS, 4).
-define(WATCHDOG_YIELD_MS, 100).

-define(NESTED, <<16#82, 16#A1, 1, 16#83, 2, 3, 4, 16#82, 5, 6>>).
-define(NESTED_TERM, [
    {map, [{1, [2, 3, 4]}]},
    [5, 6]
]).
-define(SEQUENCE, <<
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23,
    16#18, 24, 16#18, 25, 16#18, 26, 16#18, 27, 16#18, 28,
    16#18, 29, 16#18, 30, 16#18, 31, 16#18, 32
>>).
-define(SEQUENCE_TERM, [
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32
]).
-define(BENEFIT_MAP, <<16#A3, 1, 2, 3, 4, 5, 6>>).
-define(BENEFIT_ARRAY, <<16#85, 1, 2, 3, 4, 5>>).

start() ->
    timer:sleep(3000),
    io:format("CBOR_CANDIDATE_API_BENCHMARK_BEGIN~n", []),
    bench("encode_with_size_nested", fun encode_with_size_nested/0),
    bench("encode_sequence_32", fun encode_sequence_32/0),
    bench("sequence_fold_32", fun sequence_fold_32/0),
    bench("validate_all_nested", fun validate_all_nested/0),
    bench("partial_map_fold", fun partial_map_fold/0),
    bench("partial_array_fold", fun partial_array_fold/0),
    bench("partial_select", fun partial_select/0),
    bench("partial_map_find", fun partial_map_find/0),
    bench("partial_array_nth", fun partial_array_nth/0),
    io:format("CBOR_CANDIDATE_API_BENCHMARK_END~n", []),
    ok.

bench(Name, Fun) ->
    ok = Fun(),
    Total = timed_chunks(?ITERATIONS, Fun, 0),
    Average = Total / ?ITERATIONS,
    io:format(
        "BENCH0_3,~s,~B,~B,~.2f~n",
        [Name, ?ITERATIONS, Total, Average]
    ).

timed_chunks(0, _Fun, Total) ->
    Total;
timed_chunks(Remaining, Fun, Total) ->
    Chunk = case Remaining > ?WATCHDOG_CHUNK_ITERS of
        true -> ?WATCHDOG_CHUNK_ITERS;
        false -> Remaining
    end,
    Start = erlang:system_time(microsecond),
    loop(Chunk, Fun),
    Elapsed = erlang:system_time(microsecond) - Start,
    timer:sleep(?WATCHDOG_YIELD_MS),
    timed_chunks(Remaining - Chunk, Fun, Total + Elapsed).

loop(0, _Fun) -> ok;
loop(Count, Fun) ->
    ok = Fun(),
    loop(Count - 1, Fun).

encode_with_size_nested() ->
    {ok, ?NESTED, 10} = avm_cbor:encode_with_size(?NESTED_TERM),
    ok.

encode_sequence_32() ->
    {ok, ?SEQUENCE} = avm_cbor:encode_sequence(?SEQUENCE_TERM),
    ok.

sequence_fold_32() ->
    {ok, 528, <<>>} = avm_cbor:sequence_fold(
        ?SEQUENCE, fun sum_fold/2, 0),
    ok.

validate_all_nested() ->
    ok = avm_cbor:validate_all(?NESTED).

partial_map_fold() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?BENEFIT_MAP),
    {ok, 3} = avm_cbor:partial_map_fold(
        Partial, fun count_map/3, 0),
    ok.

partial_array_fold() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?BENEFIT_ARRAY),
    {ok, 5} = avm_cbor:partial_array_fold(
        Partial, fun count_array/2, 0),
    ok.

partial_select() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?BENEFIT_MAP),
    {ok, [{1, _}, {5, _}], []} = avm_cbor:partial_select(Partial, [1, 5]),
    ok.

partial_map_find() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?BENEFIT_MAP),
    {ok, ValuePartial} = avm_cbor:partial_map_find(Partial, 5),
    {ok, 6} = avm_cbor:partial_deep_decode(ValuePartial),
    ok.

partial_array_nth() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?BENEFIT_ARRAY),
    {ok, ValuePartial} = avm_cbor:partial_array_nth(Partial, 3),
    {ok, 4} = avm_cbor:partial_deep_decode(ValuePartial),
    ok.

sum_fold(Item, Acc) -> {cont, Item + Acc}.
count_map(_Key, _Value, Count) -> {cont, Count + 1}.
count_array(_Value, Count) -> {cont, Count + 1}.
