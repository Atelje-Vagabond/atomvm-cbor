#!/usr/bin/env escript
%%! -noshell

-mode(compile).

main([CoverData, ThresholdText, DiffPath, BranchEnvPath]) ->
    Threshold = list_to_integer(ThresholdText),
    ok = ensure_directory("coverage/placeholder"),
    {ok, _Pid} = cover:start(),
    ok = cover:import(CoverData),
    Modules = [avm_cbor, avm_cbor_partial],
    ChangedLines = read_changed_lines(DiffPath),
    CriticalRanges = critical_ranges(Modules),
    Results = line_results(Modules, ChangedLines, CriticalRanges),
    Total = metric(Results, fun(_Changed, _Critical) -> true end),
    Changed = metric(Results, fun(IsChanged, _Critical) -> IsChanged end),
    Critical = metric(Results, fun(_Changed, IsCritical) -> IsCritical end),
    Branches = read_env(BranchEnvPath),
    print_metric("Line coverage", Total),
    print_metric("Changed-line coverage", Changed),
    print_metric("Critical-path line coverage", Critical),
    ok = write_lines_json(Total, Changed, Critical, Results, Threshold),
    ok = write_uncovered(Results),
    ok = write_summary(Total, Changed, Critical, Branches, Threshold),
    enforce(Total, Changed, Critical, Threshold);
main(_) ->
    io:format(
        standard_error,
        "usage: check-coverage.escript COVERDATA THRESHOLD CHANGED_DIFF BRANCH_ENV~n",
        []
    ),
    halt(2).

ensure_directory(Path) ->
    case filelib:ensure_dir(Path) of
        ok -> ok;
        {error, Reason} -> erlang:error({coverage_directory, Reason})
    end.

line_results(Modules, ChangedLines, CriticalRanges) ->
    lists:flatmap(
        fun(Module) ->
            {ok, Lines} = cover:analyse(Module, calls, line),
            Source = module_source(Module),
            [
                {Module, Line, Calls,
                 maps:is_key({Source, Line}, ChangedLines),
                 is_critical_line(Module, Line, CriticalRanges)}
                || {{_ResultModule, Line}, Calls} <- Lines
            ]
        end,
        Modules
    ).

metric(Results, Predicate) ->
    lists:foldl(
        fun({_Module, _Line, Calls, Changed, Critical}, {Covered0, Total0}) ->
            case Predicate(Changed, Critical) of
                true -> {Covered0 + bool_int(Calls > 0), Total0 + 1};
                false -> {Covered0, Total0}
            end
        end,
        {0, 0},
        Results
    ).

bool_int(true) -> 1;
bool_int(false) -> 0.

critical_ranges(Modules) ->
    maps:from_list([{Module, module_function_ranges(Module)} || Module <- Modules]).

module_function_ranges(Module) ->
    Source = module_source(Module),
    {ok, Forms} = epp:parse_file(Source, ["src"], []),
    Functions0 = [
        {anno_line(Anno), Name, Arity}
        || {function, Anno, Name, Arity, _Clauses} <- Forms,
           anno_line(Anno) > 0
    ],
    Functions = lists:sort(Functions0),
    function_ranges(Functions).

function_ranges([]) -> [];
function_ranges([{Start, Name, Arity}]) ->
    [{Start, 16#7FFFFFFF, Name, Arity}];
function_ranges([{Start, Name, Arity}, {Next, _, _} = NextFunction | Rest]) ->
    [{Start, Next - 1, Name, Arity} | function_ranges([NextFunction | Rest])].

anno_line(Anno) ->
    try erl_anno:line(Anno) of
        Line when is_integer(Line) -> Line
    catch
        _:_ -> 0
    end.

is_critical_line(Module, Line, Ranges) ->
    lists:any(
        fun({Start, End, Name, _Arity}) ->
            Line >= Start andalso Line =< End andalso is_critical(Name)
        end,
        maps:get(Module, Ranges)
    ).

is_critical(Function) ->
    lists:member(Function, [
        decode, decode_normalized, decode_all, decode_all_normalized,
        decode_all_items, decode_all_small_items, decode_sequence,
        decode_sequence_normalized, decode_sequence_items,
        decode_sequence_small_items, normalize_opts,
        decode_item, decode_charged_item, decode_indefinite,
        requires_deterministic_decode, check_deterministic_map_key,
        compare_key_bytes, arg, byte_string, text_string,
        array, items, map, pairs, deterministic_pairs, ensure_declared_items, tag,
        indef_byte_string, indef_bstr_chunks, indef_text_string,
        indef_tstr_chunks, indef_array, indef_items, indef_map, indef_pairs,
        partial_decode, partial_deep_decode, deep_decode, valid_partial,
        parse, parse_item, parse_charged_item, parse_definite,
        parse_indefinite, measure, measure_charged, measure_indefinite, measure_value,
        skip_string, skip_text, measure_array, measure_n_items,
        measure_map, measure_n_pairs, measure_n_deterministic_pairs, measure_tag,
        measure_bstr_chunks, measure_tstr_chunks,
        measure_indef_items, measure_indef_pairs,
        consume_node, consume_nodes, ensure_node_budget, consume_string_bytes,
        check_max_bytes, check_string_byte_limit, check_depth,
        check_preferred, preferred_arg, preferred_float_arg, is_half_nan,
        simple, decode_half, encode_preferred_float, try_half_encode,
        float_to_half_bits, float_bits_to_half_bits, float_to_half_finite,
        try_single_encode, encode_map_pairs, sort_map_pairs
    ]).

read_changed_lines(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> parse_diff(binary:split(Bin, <<"\n">>, [global]), undefined, #{});
        {error, Reason} -> erlang:error({changed_diff, Path, Reason})
    end.

parse_diff([], _File, Acc) -> Acc;
parse_diff([<<"+++ b/", Path/binary>> | Rest], _File, Acc) ->
    parse_diff(Rest, binary_to_list(Path), Acc);
parse_diff([<<"+++ /dev/null">> | Rest], _File, Acc) ->
    parse_diff(Rest, undefined, Acc);
parse_diff([<<"@@ ", Hunk/binary>> | Rest], File, Acc0) when File =/= undefined ->
    parse_diff(Rest, File, add_hunk_lines(File, Hunk, Acc0));
parse_diff([_ | Rest], File, Acc) -> parse_diff(Rest, File, Acc).

add_hunk_lines(File, Hunk, Acc0) ->
    case re:run(Hunk, <<"\\+([0-9]+)(?:,([0-9]+))?">>, [{capture, all_but_first, binary}]) of
        {match, [StartBin, CountBin]} ->
            Start = binary_to_integer(StartBin),
            Count = case CountBin of <<>> -> 1; _ -> binary_to_integer(CountBin) end,
            lists:foldl(fun(Line, A) -> maps:put({File, Line}, true, A) end, Acc0,
                lists:seq(Start, Start + Count - 1));
        {match, [StartBin]} ->
            maps:put({File, binary_to_integer(StartBin)}, true, Acc0);
        nomatch -> Acc0
    end.

read_env(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            maps:from_list([
                begin
                    [Key, Value] = binary:split(Line, <<"=">>),
                    {binary_to_list(Key), binary_to_list(Value)}
                end
                || Line <- binary:split(Bin, <<"\n">>, [global]),
                   Line =/= <<>>
            ]);
        {error, Reason} -> erlang:error({branch_summary, Path, Reason})
    end.

write_lines_json(Total, Changed, Critical, Results, Threshold) ->
    LinesJson = lists:join(",\n", [line_json(Result) || Result <- Results]),
    {TotalCovered, TotalCount} = Total,
    {ChangedCovered, ChangedCount} = Changed,
    {CriticalCovered, CriticalCount} = Critical,
    Json = io_lib:format(
        "{\n  \"schema\": 1,\n  \"definition\": \"OTP executable-line coverage\",\n  \"threshold\": ~B,\n  \"summary\": {\n    \"total\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f},\n    \"changed\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f},\n    \"critical\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f}\n  },\n  \"lines\": [\n~s\n  ]\n}\n",
        [Threshold,
         TotalCovered, TotalCount, percentage(TotalCovered, TotalCount),
         ChangedCovered, ChangedCount, percentage(ChangedCovered, ChangedCount),
         CriticalCovered, CriticalCount, percentage(CriticalCovered, CriticalCount),
         LinesJson]
    ),
    file:write_file("coverage/lines.json", Json).

line_json({Module, Line, Calls, Changed, Critical}) ->
    io_lib:format(
        "    {\"module\": \"~s\", \"line\": ~B, \"calls\": ~B, \"covered\": ~s, \"changed\": ~s, \"critical\": ~s}",
        [atom_to_list(Module), Line, Calls, json_bool(Calls > 0),
         json_bool(Changed), json_bool(Critical)]
    ).

json_bool(true) -> "true";
json_bool(false) -> "false".

write_uncovered(Results) ->
    LineEntries = [
        io_lib:format(
            "~s:~B changed=~p critical=~p~n",
            [module_source(Module), Line, Changed, Critical]
        )
        || {Module, Line, 0, Changed, Critical} <- Results
    ],
    BranchEntries = case file:read_file("coverage/uncovered-branches.txt") of
        {ok, Bin} -> Bin;
        {error, Reason} -> erlang:error({uncovered_branches, Reason})
    end,
    file:write_file(
        "coverage/uncovered.txt",
        ["Uncovered executable lines\n", LineEntries,
         "Uncovered true branches\n", BranchEntries]
    ).

write_summary(Total, Changed, Critical, Branches, Threshold) ->
    {LineCovered, LineTotal} = Total,
    {ChangedLineCovered, ChangedLineTotal} = Changed,
    {CriticalLineCovered, CriticalLineTotal} = Critical,
    LinePercent = percentage(LineCovered, LineTotal),
    BranchPercentText = maps:get("TRUE_BRANCH_COVERAGE", Branches),
    BranchPercent = list_to_float(BranchPercentText),
    BadgePercent = erlang:min(LinePercent, BranchPercent),
    Summary = io_lib:format(
        "LINE_COVERED=~B~nLINE_TOTAL=~B~nLINE_COVERAGE=~.4f~n"
        "CHANGED_LINE_COVERED=~B~nCHANGED_LINE_TOTAL=~B~nCHANGED_LINE_COVERAGE=~.4f~n"
        "CRITICAL_LINE_COVERED=~B~nCRITICAL_LINE_TOTAL=~B~nCRITICAL_LINE_COVERAGE=~.4f~n"
        "BRANCH_COVERAGE=~s~nCHANGED_BRANCH_COVERAGE=~s~nCRITICAL_BRANCH_COVERAGE=~s~n"
        "BADGE_COVERAGE=~.2f~nCOVERAGE_THRESHOLD=~B~n",
        [LineCovered, LineTotal, LinePercent,
         ChangedLineCovered, ChangedLineTotal, percentage(ChangedLineCovered, ChangedLineTotal),
         CriticalLineCovered, CriticalLineTotal, percentage(CriticalLineCovered, CriticalLineTotal),
         BranchPercentText, maps:get("CHANGED_BRANCH_COVERAGE", Branches),
         maps:get("CRITICAL_BRANCH_COVERAGE", Branches), BadgePercent, Threshold]
    ),
    file:write_file("coverage/summary.env", Summary).

print_metric(Label, {Covered, Total}) ->
    io:format("~s: ~.2f% (~B/~B)~n", [Label, percentage(Covered, Total), Covered, Total]).

enforce(Total, Changed, Critical, Threshold) ->
    case passes(Total, Threshold) andalso passes(Changed, Threshold) andalso
         passes(Critical, 100) of
        true ->
            io:format(
                "Line gate passed: total and changed >= ~B%; critical = 100%.~n",
                [Threshold]
            );
        false ->
            io:format(
                standard_error,
                "Line gate failed: total and changed must be >= ~B%; critical must be 100%.~n",
                [Threshold]
            ),
            halt(1)
    end.

percentage(_Covered, 0) -> 0.0;
percentage(Covered, Total) -> Covered * 100.0 / Total.

passes({_Covered, 0}, _Threshold) -> false;
passes({Covered, Total}, Threshold) -> Covered * 100 >= Total * Threshold.

module_source(avm_cbor) -> "src/avm_cbor.erl";
module_source(avm_cbor_partial) -> "src/avm_cbor_partial.erl".
