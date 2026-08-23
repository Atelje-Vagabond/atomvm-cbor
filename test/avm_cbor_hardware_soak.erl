-module(avm_cbor_hardware_soak).

-export([start/0]).

-define(WARMUP_ITERATIONS, 64).
-define(ROUNDS, 40).
-define(ITERATIONS_PER_ROUND, 16).
-define(WATCHDOG_CHUNK_ITERS, 4).
-define(WATCHDOG_YIELD_MS, 100).
-define(MAX_HEAP_GROWTH_WORDS, 2048).
-define(MAX_MEMORY_GROWTH_BYTES, 16384).
-define(MAX_LATE_HEAP_TREND_WORDS, 128).
-define(MAX_LATE_MEMORY_TREND_BYTES, 1024).

-define(SOAK_TERM, {map, [
    {{text, <<"sensor">>}, {text, <<"outdoor">>}},
    {{text, <<"samples">>}, [1, 2, 3, 4, 5, 6, 7, 8]},
    {{text, <<"enabled">>}, true}
]}).

start() ->
    io:format(
        "CBOR_HARDWARE_SOAK_BEGIN rounds=~B iterations_per_round=~B~n",
        [?ROUNDS, ?ITERATIONS_PER_ROUND]
    ),
    ok = run_chunked(?WARMUP_ITERATIONS),
    true = erlang:garbage_collect(),
    io:format("SOAK_PRIME gc=ok~n", []),
    true = erlang:garbage_collect(),
    {BaseHeap, BaseMemory} = snapshot(),
    HeapLimit = BaseHeap + ?MAX_HEAP_GROWTH_WORDS,
    MemoryLimit = BaseMemory + ?MAX_MEMORY_GROWTH_BYTES,
    io:format(
        "SOAK_LIMIT base_heap_words=~B max_heap_words=~B base_memory_bytes=~B max_memory_bytes=~B~n",
        [BaseHeap, HeapLimit, BaseMemory, MemoryLimit]
    ),
    case run_rounds(
        1,
        HeapLimit,
        MemoryLimit,
        {BaseHeap, BaseMemory, BaseHeap, BaseMemory}
    ) of
        {ok, {FirstHeapMax, FirstMemoryMax, LateHeapMax, LateMemoryMax}} ->
            true = erlang:garbage_collect(),
            {FinalHeap, FinalMemory} = snapshot(),
            ok = require_at_most(
                LateHeapMax,
                FirstHeapMax + ?MAX_LATE_HEAP_TREND_WORDS,
                late_heap_growth
            ),
            ok = require_at_most(
                LateMemoryMax,
                FirstMemoryMax + ?MAX_LATE_MEMORY_TREND_BYTES,
                late_memory_growth
            ),
            ok = require_at_most(FinalHeap, HeapLimit, final_heap_growth),
            ok = require_at_most(FinalMemory, MemoryLimit, final_memory_growth),
            io:format(
                "CBOR_HARDWARE_SOAK_SUMMARY base_heap_words=~B final_heap_words=~B first_heap_max=~B late_heap_max=~B base_memory_bytes=~B final_memory_bytes=~B first_memory_max=~B late_memory_max=~B explicit_gc_rounds=~B retained_growth_gate=pass~n",
                [BaseHeap, FinalHeap, FirstHeapMax, LateHeapMax,
                 BaseMemory, FinalMemory, FirstMemoryMax, LateMemoryMax,
                 ?ROUNDS]
            ),
            io:format("CBOR_HARDWARE_SOAK_END~n", []),
            ok;
        {error, _} = Error ->
            Error
    end.

run_rounds(Round, _HeapLimit, _MemoryLimit, Trends) when Round > ?ROUNDS ->
    {ok, Trends};
run_rounds(Round, HeapLimit, MemoryLimit, Trends) ->
    {PreHeap, PreMemory} = snapshot(),
    ok = run_chunked(?ITERATIONS_PER_ROUND),
    {PeakHeap, PeakMemory} = snapshot(),
    true = erlang:garbage_collect(),
    {PostHeap, PostMemory} = snapshot(),
    io:format(
        "SOAK round=~B pre_heap_words=~B peak_heap_words=~B post_gc_heap_words=~B pre_memory_bytes=~B peak_memory_bytes=~B post_gc_memory_bytes=~B gc=ok~n",
        [Round, PreHeap, PeakHeap, PostHeap,
         PreMemory, PeakMemory, PostMemory]
    ),
    case require_at_most(PostHeap, HeapLimit, retained_heap_growth) of
        {error, _} = Error -> Error;
        ok ->
            case require_at_most(PostMemory, MemoryLimit, retained_memory_growth) of
                {error, _} = Error -> Error;
                ok ->
                    run_rounds(
                        Round + 1,
                        HeapLimit,
                        MemoryLimit,
                        update_trends(Round, PostHeap, PostMemory, Trends)
                    )
            end
    end.

update_trends(Round, Heap, Memory,
              {FirstHeapMax, FirstMemoryMax, LateHeapMax, LateMemoryMax})
  when Round =< (?ROUNDS div 2) ->
    {erlang:max(Heap, FirstHeapMax), erlang:max(Memory, FirstMemoryMax),
     LateHeapMax, LateMemoryMax};
update_trends(_Round, Heap, Memory,
              {FirstHeapMax, FirstMemoryMax, LateHeapMax, LateMemoryMax}) ->
    {FirstHeapMax, FirstMemoryMax,
     erlang:max(Heap, LateHeapMax), erlang:max(Memory, LateMemoryMax)}.

run_chunked(0) -> ok;
run_chunked(Remaining) ->
    Chunk = case Remaining > ?WATCHDOG_CHUNK_ITERS of
        true -> ?WATCHDOG_CHUNK_ITERS;
        false -> Remaining
    end,
    ok = run_iterations(Chunk),
    timer:sleep(?WATCHDOG_YIELD_MS),
    run_chunked(Remaining - Chunk).

run_iterations(0) -> ok;
run_iterations(Count) ->
    {ok, Encoded} = avm_cbor:encode(?SOAK_TERM),
    {ok, ?SOAK_TERM, <<>>} = avm_cbor:decode(Encoded),
    {ok, Partial, <<>>} = avm_cbor:partial_decode(Encoded),
    {ok, ?SOAK_TERM} = avm_cbor:partial_deep_decode(Partial),
    run_iterations(Count - 1).

snapshot() ->
    {total_heap_size, HeapWords} =
        erlang:process_info(self(), total_heap_size),
    {memory, MemoryBytes} = erlang:process_info(self(), memory),
    {HeapWords, MemoryBytes}.

require_at_most(Value, Limit, _Reason) when Value =< Limit -> ok;
require_at_most(Value, Limit, Reason) ->
    {error, {soak_memory_limit_exceeded, Reason, Value, Limit}}.
