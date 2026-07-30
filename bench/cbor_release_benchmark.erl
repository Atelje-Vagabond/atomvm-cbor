-module(cbor_release_benchmark).
-export([start/0]).

-define(COMMON_ITERS, 50).
-define(PARTIAL_ITERS, 50).
-define(ACCESSOR_ITERS, 250).
-define(WATCHDOG_CHUNK_ITERS, 8).
%% One ESP-IDF scheduler tick was not a reliable idle window: depending on the
%% tick boundary, the AtomVM main task could become runnable again before IDLE0
%% serviced the task watchdog.  Ten ticks make the out-of-band pause robust.
-define(WATCHDOG_YIELD_MS, 100).

-define(MAP_VALUE, {map, [
    {{text, <<"key1">>}, {text, <<"value1">>}},
    {{text, <<"key2">>}, 42}
]}).
-define(MAP_CBOR, <<16#A2,
    16#64, "key1", 16#66, "value1",
    16#64, "key2", 16#18, 42>>).

start() ->
    io:format("CBOR_RELEASE_BENCHMARK_BEGIN~n"),
    warmup(),
    bench("encode/1", ?COMMON_ITERS, fun encode_map/0),
    bench("decode/1", ?COMMON_ITERS, fun decode_map/0),
    run_partial_benchmarks(),
    io:format("CBOR_RELEASE_BENCHMARK_END~n"),
    ok.

warmup() ->
    encode_map(),
    decode_map(),
    warmup_partial().

encode_map() ->
    {ok, ?MAP_CBOR} = avm_cbor:encode(?MAP_VALUE).

decode_map() ->
    {ok, ?MAP_VALUE, <<>>} = avm_cbor:decode(?MAP_CBOR).

bench(Name, Iterations, Fun) ->
    Fun(),
    Total = timed_chunks(Iterations, Fun, 0),
    Average = Total / Iterations,
    io:format("BENCH,~s,~B,~B,~.2f~n", [Name, Iterations, Total, Average]).

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
    %% The sleep is outside the timed interval. Bounded chunks let the MCU idle
    %% task run often enough to service the watchdog without polluting results.
    timer:sleep(?WATCHDOG_YIELD_MS),
    timed_chunks(Remaining - Chunk, Fun, Total + Elapsed).

loop(0, _Fun) -> ok;
loop(N, Fun) ->
    Fun(),
    loop(N - 1, Fun).

-ifdef(V020).

warmup_partial() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?MAP_CBOR),
    map = avm_cbor:partial_type(Partial),
    ok.

run_partial_benchmarks() ->
    {ok, MapPartial, <<>>} = avm_cbor:partial_decode(?MAP_CBOR),
    {ok, TagPartial, <<>>} = avm_cbor:partial_decode(<<16#C1, 1>>),
    {ok, TextPartial, <<>>} = avm_cbor:partial_decode(<<16#62, "ok">>),
    bench("partial_decode/1", ?PARTIAL_ITERS,
        fun() -> {ok, _, <<>>} = avm_cbor:partial_decode(?MAP_CBOR) end),
    bench("partial_decode/2", ?PARTIAL_ITERS,
        fun() -> {ok, _, <<>>} = avm_cbor:partial_decode(?MAP_CBOR, []) end),
    bench("partial_deep_decode/1", ?PARTIAL_ITERS,
        fun() -> {ok, ?MAP_VALUE} = avm_cbor:partial_deep_decode(MapPartial) end),
    bench("partial_value_bytes/1", ?ACCESSOR_ITERS,
        fun() -> ?MAP_CBOR = avm_cbor:partial_value_bytes(MapPartial) end),
    bench("partial_contents/1", ?ACCESSOR_ITERS,
        fun() -> {ok, _} = avm_cbor:partial_contents(MapPartial) end),
    bench("partial_skip/1", ?ACCESSOR_ITERS,
        fun() -> ok = avm_cbor:partial_skip(MapPartial) end),
    bench("partial_type/1", ?ACCESSOR_ITERS,
        fun() -> map = avm_cbor:partial_type(MapPartial) end),
    bench("partial_count/1", ?ACCESSOR_ITERS,
        fun() -> 2 = avm_cbor:partial_count(MapPartial) end),
    bench("partial_tag/1", ?ACCESSOR_ITERS,
        fun() -> 1 = avm_cbor:partial_tag(TagPartial) end),
    bench("partial_size/1", ?ACCESSOR_ITERS,
        fun() -> 2 = avm_cbor:partial_size(TextPartial) end),
    bench("partial_offset/1", ?ACCESSOR_ITERS,
        fun() -> 0 = avm_cbor:partial_offset(MapPartial) end),
    bench("partial_length/1", ?ACCESSOR_ITERS,
        fun() -> 20 = avm_cbor:partial_length(MapPartial) end).

-else.

warmup_partial() -> ok.
run_partial_benchmarks() -> ok.

-endif.
