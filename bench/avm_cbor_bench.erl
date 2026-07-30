-module(avm_cbor_bench).
-export([run/0]).

-define(ITERATIONS, 10000).

run() ->
    io:format("~nAtomVM CBOR Benchmark~n"),
    io:format("====================~n~n"),
    io:format("~-25s | ~10s | ~8s | ~8s~n", ["Workload", "Iterations", "Total ms", "Ops/sec"]),
    io:format("~-25s-|------------|----------|--------~n", ["------------------------"]),
    warmup(),
    bench("decode_unsigned_small",  fun bench_decode_unsigned_small/0),
    bench("encode_unsigned_small",  fun bench_encode_unsigned_small/0),
    bench("decode_text_utf8",       fun bench_decode_text_utf8/0),
    bench("encode_text_utf8",       fun bench_encode_text_utf8/0),
    bench("decode_ble_map",         fun bench_decode_ble_map/0),
    bench("encode_ble_map",         fun bench_encode_ble_map/0),
    bench("decode_nested_map",      fun bench_decode_nested_map/0),
    bench("encode_nested_map",      fun bench_encode_nested_map/0),
    bench("decode_tags",            fun bench_decode_tags/0),
    bench("encode_tags",            fun bench_encode_tags/0),
    bench("decode_sequence_10",     fun bench_decode_sequence_10/0),
    bench("decode_indefinite_array", fun bench_decode_indefinite_array/0),
    io:format("~n"),
    ok.

warmup() ->
    _ = F = fun() ->
        _ = avm_cbor:decode(<<24, 42>>),
        _ = avm_cbor:encode(42),
        _ = avm_cbor:decode(<<16#65, "hello">>),
        _ = avm_cbor:encode({text, <<"hello">>}),
        _ = avm_cbor:decode(<<
            16#A4,
            16#01, 16#68, "set_wifi",
            16#02, 16#66, "MySSID",
            16#03, 16#46, "secret",
            16#04, 16#F5
        >>)
    end,
    _ = F(),
    _ = F(),
    _ = F(),
    ok.

bench(Name, F) ->
    _ = F(),
    T0 = erlang:monotonic_time(microsecond),
    run_n(F, ?ITERATIONS),
    T1 = erlang:monotonic_time(microsecond),
    TotalUs = T1 - T0,
    TotalMs = TotalUs / 1000,
    OpsSec = (?ITERATIONS * 1000000) div TotalUs,
    io:format("~-25s | ~10w | ~8.1f | ~8w~n", [Name, ?ITERATIONS, TotalMs, OpsSec]).

run_n(_F, 0) -> ok;
run_n(F, N) -> F(), run_n(F, N - 1).

%% Deterministic CBOR payloads

-define(UNSIGNED_SMALL, <<24, 42>>).
-define(TEXT_UTF8, <<16#65, "hello">>).

-define(BLE_MAP, <<16#A4,
    16#01, 16#68, "set_wifi",
    16#02, 16#66, "MySSID",
    16#03, 16#46, "secret",
    16#04, 16#F5>>).

-define(NESTED_MAP, <<
    16#A1, 16#01, 16#A1, 16#02,
    16#83, 16#03, 16#04,
    16#A1, 16#05, 16#06
>>).

-define(TAGS, <<16#C1, 16#65, "hello">>).
-define(SEQUENCE_10, <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>).
-define(INDEF_ARRAY, <<16#9F, 1, 2, 3, 16#FF>>).

bench_decode_unsigned_small() ->
    {ok, 42, <<>>} = avm_cbor:decode(?UNSIGNED_SMALL).

bench_encode_unsigned_small() ->
    {ok, ?UNSIGNED_SMALL} = avm_cbor:encode(42).

bench_decode_text_utf8() ->
    {ok, {text, <<"hello">>}, <<>>} = avm_cbor:decode(?TEXT_UTF8).

bench_encode_text_utf8() ->
    {ok, ?TEXT_UTF8} = avm_cbor:encode({text, <<"hello">>}).

bench_decode_ble_map() ->
    {ok, _, <<>>} = avm_cbor:decode(?BLE_MAP).

bench_encode_ble_map() ->
    {ok, _} = avm_cbor:encode({map, [
        {1, {text, <<"set_wifi">>}},
        {2, {text, <<"MySSID">>}},
        {3, <<"secret">>},
        {4, true}
    ]}).

bench_decode_nested_map() ->
    {ok, _, <<>>} = avm_cbor:decode(?NESTED_MAP).

bench_encode_nested_map() ->
    {ok, _} = avm_cbor:encode({map, [
        {1, {map, [
            {2, [3, 4, {map, [{5, 6}]}]}
        ]}}
    ]}).

bench_decode_tags() ->
    {ok, {tag, 1, {text, <<"hello">>}}, <<>>} = avm_cbor:decode(?TAGS).

bench_encode_tags() ->
    {ok, ?TAGS} = avm_cbor:encode({tag, 1, {text, <<"hello">>}}).

bench_decode_sequence_10() ->
    {ok, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]} = avm_cbor:decode_all(?SEQUENCE_10).

bench_decode_indefinite_array() ->
    {ok, [1, 2, 3], <<>>} = avm_cbor:decode(?INDEF_ARRAY).
