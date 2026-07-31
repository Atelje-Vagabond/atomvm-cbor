-module(remediation_benchmark).

-export([run/3, aggregate/2, compare/4]).

-define(SAMPLES, 31).
-define(WARMUP_ITERATIONS, 1000).
-define(DEFAULT_NOISE_TOLERANCE_PERCENT, 5.0).

-define(SCALAR, <<16#18, 42>>).
-define(STRING, <<16#58, 64, 0:512>>).
-define(NESTED, <<16#82, 16#A1, 1, 16#83, 2, 3, 4, 16#82, 5, 6>>).
-define(SEQUENCE, <<
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23,
    16#18, 24, 16#18, 25, 16#18, 26, 16#18, 27, 16#18, 28,
    16#18, 29, 16#18, 30, 16#18, 31, 16#18, 32
>>).
-define(MALFORMED, <<16#9A, 0, 0, 16#10, 0, 1, 2, 3>>).

-define(NESTED_TERM, [
    {map, [{1, [2, 3, 4]}]},
    [5, 6]
]).

-define(DETERMINISTIC_TERM, {map, [
    {{text, <<"z">>}, 1},
    {24, {text, <<"wide">>}},
    {1, {text, <<"short">>}},
    {{text, <<"aa">>}, [1, 2, 3]}
]}).

-define(DETERMINISTIC_CBOR, <<
    16#A4,
    1, 16#65, "short",
    16#18, 24, 16#64, "wide",
    16#61, "z", 1,
    16#62, "aa", 16#83, 1, 2, 3
>>).

run(Mode, Identity, OutputPath) ->
    Workloads = workloads(),
    Results = [run_workload(Workload) || Workload <- Workloads],
    Metadata = [
        {mode, Mode},
        {identity, Identity},
        {otp_release, erlang:system_info(otp_release)},
        {system_architecture, erlang:system_info(system_architecture)},
        {schedulers, integer_to_list(erlang:system_info(schedulers_online))},
        {build_options, "erlc -Wall"},
        {clock, "erlang:monotonic_time(nanosecond)"},
        {samples, integer_to_list(?SAMPLES)},
        {warmup_iterations, integer_to_list(?WARMUP_ITERATIONS)}
    ],
    Data = [
        "kind,name,available,samples,iterations,median_ns,p95_ns,mad_ns,min_ns,max_ns,gc_count,gc_reclaimed_words,heap_delta_words\n",
        [io_lib:format("META,~s,~s~n", [Key, Value]) || {Key, Value} <- Metadata],
        [result_csv(Result) || Result <- Results]
    ],
    ok = file:write_file(OutputPath, Data),
    print_results(Mode, Results),
    ok.

aggregate(Paths, OutputPath) ->
    Datasets = [read_results(Path) || Path <- Paths],
    [{FirstMeta, FirstResults} | _] = Datasets,
    Names = [Name || {Name, _} <- FirstResults],
    Results = [
        {Name, aggregate_result([
            proplists:get_value(Name, DatasetResults)
            || {_Meta, DatasetResults} <- Datasets
        ])}
        || Name <- Names
    ],
    Metadata = [{"aggregate_runs", integer_to_list(length(Paths))} | FirstMeta],
    Data = [
        "kind,name,available,samples,iterations,median_ns,p95_ns,mad_ns,min_ns,max_ns,gc_count,gc_reclaimed_words,heap_delta_words\n",
        [io_lib:format("META,~s,~s~n", [Key, Value]) || {Key, Value} <- Metadata],
        [result_csv({Name, Available, Samples, Iterations, Median, P95, Mad,
                     Min, Max, GcCount, GcWords, HeapDelta})
         || {Name, {Available, Samples, Iterations, Median, P95, Mad,
                    Min, Max, GcCount, GcWords, HeapDelta}} <- Results]
    ],
    file:write_file(OutputPath, Data).

aggregate_result(Results) ->
    case [Result || Result = {true, _, _, _, _, _, _, _, _, _, _} <- Results] of
        [] ->
            {false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        Available ->
            Values = [tuple_to_list(Result) || Result <- Available],
            [AvailabilityColumn | NumericColumns] = transpose(Values),
            true = lists:all(fun(Value) -> Value =:= true end, AvailabilityColumn),
            list_to_tuple([true | [median(Values0) || Values0 <- NumericColumns]])
    end.

transpose([First | Rest]) ->
    [[Value | Values] || {Value, Values} <- lists:zip(First, transpose_rows(Rest, length(First)))].

transpose_rows([], Count) ->
    lists:duplicate(Count, []);
transpose_rows([Row | Rest], Count) ->
    [ [Value | Values]
      || {Value, Values} <- lists:zip(Row, transpose_rows(Rest, Count)) ].

median(Values) ->
    Sorted = lists:sort(Values),
    lists:nth((length(Sorted) + 1) div 2, Sorted).

workloads() ->
    [
        {"scalar_decode", 10000, fun scalar_decode/0},
        {"scalar_encode", 10000, fun scalar_encode/0},
        {"string_decode_64", 5000, fun string_decode/0},
        {"string_encode_64", 5000, fun string_encode/0},
        {"nested_decode", 3000, fun nested_decode/0},
        {"nested_encode", 3000, fun nested_encode/0},
        {"sequence_decode_32", 2000, fun sequence_decode/0},
        partial_workload()
    ] ++ deterministic_workloads() ++ [
        {"malformed_declared_array", 5000, fun malformed_decode/0}
    ].

-ifdef(HAS_PARTIAL).
partial_workload() -> {"partial_decode_nested", 3000, fun partial_decode/0}.
-else.
partial_workload() -> {"partial_decode_nested", unavailable, unavailable}.
-endif.

-ifdef(HAS_DETERMINISTIC).
deterministic_workloads() -> [
    {"deterministic_map_encode", 2000, fun deterministic_encode/0},
    {"deterministic_map_decode", 2000, fun deterministic_decode/0}
].
-else.
deterministic_workloads() -> [
    {"deterministic_map_encode", unavailable, unavailable},
    {"deterministic_map_decode", unavailable, unavailable}
].
-endif.

run_workload({Name, unavailable, unavailable}) ->
    {Name, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
run_workload({Name, Iterations, Fun}) ->
    loop(?WARMUP_ITERATIONS, Fun),
    erlang:garbage_collect(),
    {GcStart, WordsStart, _} = erlang:statistics(garbage_collection),
    {total_heap_size, HeapStart} = process_info(self(), total_heap_size),
    Samples = measure_samples(?SAMPLES, Iterations, Fun, []),
    {total_heap_size, HeapEnd} = process_info(self(), total_heap_size),
    {GcEnd, WordsEnd, _} = erlang:statistics(garbage_collection),
    Sorted = lists:sort(Samples),
    Median = percentile(Sorted, 50),
    P95 = percentile(Sorted, 95),
    Deviations = lists:sort([abs(Value - Median) || Value <- Samples]),
    Mad = percentile(Deviations, 50),
    {Name, true, ?SAMPLES, Iterations, Median, P95, Mad,
     hd(Sorted), lists:last(Sorted), GcEnd - GcStart, WordsEnd - WordsStart,
     HeapEnd - HeapStart}.

measure_samples(0, _Iterations, _Fun, Acc) -> Acc;
measure_samples(Count, Iterations, Fun, Acc) ->
    Start = erlang:monotonic_time(nanosecond),
    loop(Iterations, Fun),
    Elapsed = erlang:monotonic_time(nanosecond) - Start,
    PerOperation = erlang:max(1, Elapsed div Iterations),
    measure_samples(Count - 1, Iterations, Fun, [PerOperation | Acc]).

loop(0, _Fun) -> ok;
loop(Count, Fun) ->
    ok = Fun(),
    loop(Count - 1, Fun).

percentile(Sorted, Percent) ->
    Count = length(Sorted),
    Index = erlang:max(1, (Percent * Count + 99) div 100),
    lists:nth(Index, Sorted).

scalar_decode() ->
    {ok, 42, <<>>} = avm_cbor:decode(?SCALAR),
    ok.

scalar_encode() ->
    {ok, ?SCALAR} = avm_cbor:encode(42),
    ok.

string_decode() ->
    {ok, <<0:512>>, <<>>} = avm_cbor:decode(?STRING),
    ok.

string_encode() ->
    {ok, ?STRING} = avm_cbor:encode(<<0:512>>),
    ok.

nested_decode() ->
    {ok, ?NESTED_TERM, <<>>} = avm_cbor:decode(?NESTED),
    ok.

nested_encode() ->
    {ok, ?NESTED} = avm_cbor:encode(?NESTED_TERM),
    ok.

sequence_decode() ->
    {ok, Values} = avm_cbor:decode_all(?SEQUENCE),
    32 = length(Values),
    ok.

-ifdef(HAS_PARTIAL).
partial_decode() ->
    {ok, Partial, <<>>} = avm_cbor:partial_decode(?NESTED),
    array = avm_cbor:partial_type(Partial),
    ok.
-endif.

-ifdef(HAS_DETERMINISTIC).
deterministic_encode() ->
    {ok, _} = avm_cbor:encode(?DETERMINISTIC_TERM, [{deterministic, true}]),
    ok.

deterministic_decode() ->
    {ok, {map, _}, <<>>} = avm_cbor:decode(?DETERMINISTIC_CBOR, [{deterministic, true}]),
    ok.
-endif.

malformed_decode() ->
    case avm_cbor:decode(?MALFORMED) of
        {error, truncated} -> ok;
        {error, {max_items_exceeded, 4096}} -> ok
    end.

result_csv({Name, Available, Samples, Iterations, Median, P95, Mad,
            Min, Max, GcCount, GcWords, HeapDelta}) ->
    io_lib:format(
        "BENCH,~s,~s,~B,~B,~B,~B,~B,~B,~B,~B,~B,~B~n",
        [Name, bool_text(Available), Samples, Iterations, Median, P95, Mad,
         Min, Max, GcCount, GcWords, HeapDelta]
    ).

bool_text(true) -> "true";
bool_text(false) -> "false".

print_results(Mode, Results) ->
    io:format("~natomvm-cbor release benchmark (~s)~n", [Mode]),
    io:format("~-27s ~10s ~10s ~10s~n", ["workload", "median ns", "p95 ns", "MAD ns"]),
    lists:foreach(
        fun({Name, true, _, _, Median, P95, Mad, _, _, _, _, _}) ->
                io:format("~-27s ~10B ~10B ~10B~n", [Name, Median, P95, Mad]);
           ({Name, false, _, _, _, _, _, _, _, _, _, _}) ->
                io:format("~-27s ~10s~n", [Name, "N/A"])
        end,
        Results
    ).

compare(BaselinePath, FixedPath, JsonPath, MarkdownPath) ->
    {BaselineMeta, BaselineResults} = read_results(BaselinePath),
    {FixedMeta, FixedResults} = read_results(FixedPath),
    NoiseTolerance = noise_tolerance_percent(),
    Names = [Name || {Name, _} <- FixedResults],
    Comparisons = [
        {Name, proplists:get_value(Name, BaselineResults),
         proplists:get_value(Name, FixedResults)}
        || Name <- Names
    ],
    Failures = regression_failures(Comparisons, NoiseTolerance),
    Gate = case Failures of [] -> "pass"; _ -> "fail" end,
    ok = file:write_file(
        JsonPath,
        comparison_json(
            BaselineMeta, FixedMeta, Comparisons, NoiseTolerance, Gate)
    ),
    ok = file:write_file(
        MarkdownPath,
        comparison_markdown(
            BaselineMeta, FixedMeta, Comparisons, NoiseTolerance, Gate)
    ),
    enforce_regression_gate(Failures, NoiseTolerance).

noise_tolerance_percent() ->
    case os:getenv("BENCHMARK_NOISE_TOLERANCE_PERCENT") of
        false -> ?DEFAULT_NOISE_TOLERANCE_PERCENT;
        Text ->
            Value = case string:to_float(Text) of
                {Float, []} -> Float;
                {error, no_float} -> float(list_to_integer(Text));
                _ -> erlang:error({invalid_benchmark_noise_tolerance, Text})
            end,
            case Value >= 0.0 of
                true -> Value;
                false -> erlang:error({invalid_benchmark_noise_tolerance, Text})
            end
    end.

regression_failures(Comparisons, NoiseTolerance) ->
    lists:flatmap(
        fun({Name, {true, _, _, BaseMedian, BaseP95, _, _, _, _, _, _},
                  {true, _, _, FixedMedian, FixedP95, _, _, _, _, _, _}}) ->
                metric_regression(Name, "median", BaseMedian, FixedMedian,
                                  NoiseTolerance) ++
                metric_regression(Name, "p95", BaseP95, FixedP95,
                                  NoiseTolerance);
           (_) ->
                []
        end,
        Comparisons
    ).

metric_regression(Name, Metric, Baseline, Fixed, NoiseTolerance) ->
    Change = change_percent(Baseline, Fixed),
    case Change > NoiseTolerance of
        true -> [{Name, Metric, Baseline, Fixed, Change}];
        false -> []
    end.

enforce_regression_gate([], NoiseTolerance) ->
    io:format(
        "PERFORMANCE_GATE_OK noise_tolerance_percent=~.2f~n",
        [NoiseTolerance]
    ),
    ok;
enforce_regression_gate(Failures, NoiseTolerance) ->
    lists:foreach(
        fun({Name, Metric, Baseline, Fixed, Change}) ->
            io:format(
                standard_error,
                "PERFORMANCE_REGRESSION workload=~s metric=~s baseline_ns=~B fixed_ns=~B change_percent=~.2f tolerance_percent=~.2f~n",
                [Name, Metric, Baseline, Fixed, Change, NoiseTolerance]
            )
        end,
        Failures
    ),
    erlang:error({performance_regression, Failures}).

read_results(Path) ->
    {ok, Bin} = file:read_file(Path),
    Lines = binary:split(Bin, <<"\n">>, [global]),
    lists:foldl(fun parse_result_line/2, {[], []}, Lines).

parse_result_line(<<"META,", Rest/binary>>, {Meta, Results}) ->
    [Key, Value] = binary:split(Rest, <<",">>),
    {[{binary_to_list(Key), binary_to_list(Value)} | Meta], Results};
parse_result_line(<<"BENCH,", Rest/binary>>, {Meta, Results}) ->
    [Name, Available, Samples, Iterations, Median, P95, Mad, Min, Max,
     GcCount, GcWords, HeapDelta] = binary:split(Rest, <<",">>, [global]),
    Result = {
        Available =:= <<"true">>,
        int(Samples), int(Iterations), int(Median), int(P95), int(Mad),
        int(Min), int(Max), int(GcCount), int(GcWords), int(HeapDelta)
    },
    {Meta, [{binary_to_list(Name), Result} | Results]};
parse_result_line(_, Acc) -> Acc.

int(Bin) -> binary_to_integer(Bin).

comparison_json(BaselineMeta, FixedMeta, Comparisons, NoiseTolerance, Gate) ->
    Rows = lists:join(",\n", [comparison_json_row(Row) || Row <- Comparisons]),
    io_lib:format(
        "{\n  \"schema\": 2,\n  \"unit\": \"nanoseconds_per_operation\",\n  \"lower_is_better\": true,\n  \"noise_tolerance_percent\": ~.4f,\n  \"regression_gate\": \"~s\",\n  \"baseline\": ~s,\n  \"fixed\": ~s,\n  \"workloads\": [\n~s\n  ]\n}\n",
        [NoiseTolerance, Gate, meta_json(BaselineMeta),
         meta_json(FixedMeta), Rows]
    ).

meta_json(Meta) ->
    Entries = lists:join(", ", [
        io_lib:format("\"~s\": \"~s\"", [json_escape(Key), json_escape(Value)])
        || {Key, Value} <- lists:sort(Meta)
    ]),
    ["{", Entries, "}"].

comparison_json_row({Name, Baseline, Fixed}) ->
    io_lib:format(
        "    {\"name\": \"~s\", \"baseline\": ~s, \"fixed\": ~s, \"median_change_percent\": ~s, \"p95_change_percent\": ~s}",
        [json_escape(Name), result_json(Baseline), result_json(Fixed),
         change_json(Baseline, Fixed, 4), change_json(Baseline, Fixed, 5)]
    ).

result_json({false, _, _, _, _, _, _, _, _, _, _}) -> "null";
result_json({true, Samples, Iterations, Median, P95, Mad, Min, Max,
             GcCount, GcWords, HeapDelta}) ->
    lists:flatten(io_lib:format(
        "{\"samples\": ~B, \"iterations_per_sample\": ~B, \"median_ns\": ~B, \"p95_ns\": ~B, \"mad_ns\": ~B, \"min_ns\": ~B, \"max_ns\": ~B, \"gc_count\": ~B, \"gc_reclaimed_words\": ~B, \"heap_delta_words\": ~B}",
        [Samples, Iterations, Median, P95, Mad, Min, Max, GcCount, GcWords, HeapDelta]
    )).

change_json({false, _, _, _, _, _, _, _, _, _, _}, _Fixed, _Index) -> "null";
change_json(_Baseline, {false, _, _, _, _, _, _, _, _, _, _}, _Index) -> "null";
change_json(Baseline, Fixed, Index) ->
    BaseValue = element(Index, Baseline),
    FixedValue = element(Index, Fixed),
    lists:flatten(io_lib:format("~.4f", [change_percent(BaseValue, FixedValue)])).

comparison_markdown(BaselineMeta, FixedMeta, Comparisons, NoiseTolerance, Gate) ->
    Rows = [comparison_markdown_row(Row) || Row <- Comparisons],
    [
        "# atomvm-cbor host benchmark\n\n",
        "Lower timings are better. A negative change means the fixed implementation is faster.\n\n",
        io_lib:format("- Baseline: `~s` (`~s`)\n", [
            proplists:get_value("mode", BaselineMeta),
            proplists:get_value("identity", BaselineMeta)]),
        io_lib:format("- Fixed: `~s` (`~s`)\n", [
            proplists:get_value("mode", FixedMeta),
            proplists:get_value("identity", FixedMeta)]),
        io_lib:format("- Runtime: OTP ~s, `~s`, ~s schedulers\n", [
            proplists:get_value("otp_release", FixedMeta),
            proplists:get_value("system_architecture", FixedMeta),
            proplists:get_value("schedulers", FixedMeta)]),
        "- Build: both trees use `erlc -Wall`; each version runs in a fresh VM on the same host.\n",
        io_lib:format("- Samples: ~s per workload after ~s warm-up calls\n\n", [
            proplists:get_value("samples", FixedMeta),
            proplists:get_value("warmup_iterations", FixedMeta)]),
        io_lib:format(
            "- Regression gate: **~s**; every comparable median and p95 must stay within +~.2f% of the selected baseline. The tolerance covers scheduler and clock noise; any larger positive change exits nonzero.\n\n",
            [Gate, NoiseTolerance]
        ),
        "| Workload | Baseline median ns | Current median ns | Median change | Baseline p95 ns | Current p95 ns | p95 change | Current MAD ns |\n",
        "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n",
        Rows,
        "\nA workload is N/A only when capability probing proves that the selected baseline does not expose the required API or option. Current timings remain visible for every required representative workload.\n\n",
        "The malformed workload accepts each version's controlled failure path rather than forcing identical error vocabulary across releases.\n\n",
        "GC counters and heap deltas are recorded in the CSV and JSON artifacts. They are observational BEAM process/runtime counters, not exact allocation counts.\n"
    ].

comparison_markdown_row({Name, {false, _, _, _, _, _, _, _, _, _, _}, Fixed}) ->
    io_lib:format("| `~s` | N/A | ~B | N/A | N/A | ~B | N/A | ~B |~n",
        [Name, element(4, Fixed), element(5, Fixed), element(6, Fixed)]);
comparison_markdown_row({Name, Baseline, Fixed}) ->
    io_lib:format("| `~s` | ~B | ~B | ~.2f% | ~B | ~B | ~.2f% | ~B |~n",
        [Name, element(4, Baseline), element(4, Fixed),
         change_percent(element(4, Baseline), element(4, Fixed)),
         element(5, Baseline), element(5, Fixed),
         change_percent(element(5, Baseline), element(5, Fixed)), element(6, Fixed)]).

change_percent(Baseline, Fixed) -> (Fixed - Baseline) * 100.0 / Baseline.

json_escape(Text) ->
    lists:flatten([case C of $" -> "\\\""; $\\ -> "\\\\"; _ -> [C] end || C <- Text]).
