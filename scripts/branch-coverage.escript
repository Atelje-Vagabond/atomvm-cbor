#!/usr/bin/env escript
%%! -noshell

-mode(compile).

-record(branch, {
    module,
    function,
    arity,
    line,
    kind,
    outcome,
    id,
    critical = false
}).

-record(state, {
    next_branch = 1,
    next_var = 1,
    branches = []
}).

main([ThresholdText, DiffPath]) ->
    Threshold = list_to_integer(ThresholdText),
    ok = ensure_directory("coverage/placeholder"),
    BranchDir = "coverage/branch-ebin",
    ok = ensure_directory(filename:join(BranchDir, "placeholder")),
    ok = compile_counter(BranchDir),
    {Manifest, Modules} = compile_instrumented_modules(),
    ok = compile_tests(BranchDir),
    ok = avm_cbor_branch_counter:start(),
    ok = run_tests(Modules),
    Hits = sets:from_list(avm_cbor_branch_counter:hits()),
    ChangedLines = read_changed_lines(DiffPath),
    Results = annotate(Manifest, Hits, ChangedLines),
    Summary = summarize(Results),
    ok = write_json(Summary, Results, Threshold),
    ok = write_summary_env(Summary),
    ok = write_uncovered(Results),
    print_summary(Summary),
    enforce(Summary, Threshold);
main(_) ->
    io:format(
        standard_error,
        "usage: branch-coverage.escript THRESHOLD CHANGED_DIFF~n",
        []
    ),
    halt(2).

ensure_directory(Path) ->
    case filelib:ensure_dir(Path) of
        ok -> ok;
        {error, Reason} -> erlang:error({coverage_directory, Reason})
    end.

compile_counter(OutDir) ->
    case compile:file(
        "test/avm_cbor_branch_counter.erl",
        [debug_info, return_errors, return_warnings, {outdir, OutDir}]
    ) of
        {ok, avm_cbor_branch_counter} -> load_beam(OutDir, avm_cbor_branch_counter);
        {ok, avm_cbor_branch_counter, _Warnings} ->
            load_beam(OutDir, avm_cbor_branch_counter);
        Error -> erlang:error({branch_counter_compile, Error})
    end.

compile_instrumented_modules() ->
    Sources = [
        {avm_cbor, "src/avm_cbor.erl"},
        {avm_cbor_cont, "src/avm_cbor_cont.erl"},
        {avm_cbor_partial, "src/avm_cbor_partial.erl"}
    ],
    {State, Modules} = lists:foldl(
        fun({Module, Source}, {State0, Modules0}) ->
            {ok, Forms} = epp:parse_file(Source, ["src"], []),
            {Forms1, State1} = transform_forms(Module, Forms, State0),
            case compile:forms(
                Forms1,
                [binary, debug_info, export_all, return_errors, return_warnings]
            ) of
                {ok, Module, Beam} -> ok = load_binary(Module, Source, Beam);
                {ok, Module, Beam, _Warnings} -> ok = load_binary(Module, Source, Beam);
                Error -> erlang:error({instrumented_compile, Module, Error})
            end,
            {State1, [Module | Modules0]}
        end,
        {#state{}, []},
        Sources
    ),
    {lists:reverse(State#state.branches), lists:reverse(Modules)}.

transform_forms(Module, Forms, State0) ->
    lists:mapfoldl(
        fun(Form = {function, _Anno, Function, Arity, _Clauses}, StateAcc) ->
            Context = {Module, Function, Arity},
            {Tree, StateNew} = erl_syntax_lib:mapfold(
                fun(Node, StateIn) -> transform_node(Node, StateIn, Context) end,
                StateAcc,
                Form
            ),
            {erl_syntax:revert(Tree), StateNew};
           (Form, StateAcc) -> {Form, StateAcc}
        end,
        State0,
        Forms
    ).

transform_node(Node, State0, Context) ->
    case erl_syntax:type(Node) of
        function -> transform_function(Node, State0, Context);
        fun_expr -> transform_fun(Node, State0, Context);
        case_expr -> transform_case(Node, State0, Context);
        if_expr -> transform_if(Node, State0, Context);
        try_expr -> transform_try(Node, State0, Context);
        infix_expr -> transform_infix(Node, State0, Context);
        _ -> {Node, State0}
    end.

transform_function(Node, State0, Context) ->
    Clauses = erl_syntax:function_clauses(Node),
    case needs_dispatch_rewrite(Clauses) of
        false -> {Node, State0};
        true ->
            Arity = erl_syntax:function_arity(Node),
            {Args, State1} = fresh_vars(Arity, State0),
            Value = erl_syntax:tuple(Args),
            TupleClauses = [tuple_clause(C) || C <- Clauses],
            Final = error_call(function_clause),
            {Dispatch, State2} = build_clause_chain(
                Value, TupleClauses, Final, function_clause, State1, Context
            ),
            Clause = erl_syntax:clause(Args, none, [Dispatch]),
            Function1 = erl_syntax:function(erl_syntax:function_name(Node), [Clause]),
            {copy_pos(Node, Function1), State2}
    end.

transform_fun(Node, State0, Context) ->
    Clauses = erl_syntax:fun_expr_clauses(Node),
    case needs_dispatch_rewrite(Clauses) of
        false -> {Node, State0};
        true ->
            Arity = erl_syntax:fun_expr_arity(Node),
            {Args, State1} = fresh_vars(Arity, State0),
            Value = erl_syntax:tuple(Args),
            TupleClauses = [tuple_clause(C) || C <- Clauses],
            Final = error_call(function_clause),
            {Dispatch, State2} = build_clause_chain(
                Value, TupleClauses, Final, fun_clause, State1, Context
            ),
            Fun1 = erl_syntax:fun_expr([erl_syntax:clause(Args, none, [Dispatch])]),
            {copy_pos(Node, Fun1), State2}
    end.

transform_case(Node, State0, Context) ->
    Arg = erl_syntax:case_expr_argument(Node),
    Clauses = erl_syntax:case_expr_clauses(Node),
    {Value, State1} = fresh_var(State0),
    Final = error_call(
        erl_syntax:tuple([erl_syntax:atom(case_clause), Value])
    ),
    {Dispatch, State2} = build_clause_chain(
        Value, Clauses, Final, case_clause, State1, Context
    ),
    Match = erl_syntax:match_expr(Value, Arg),
    {copy_pos(Node, erl_syntax:block_expr([Match, Dispatch])), State2}.

transform_if(Node, State0, Context) ->
    Clauses = erl_syntax:if_expr_clauses(Node),
    Final = error_call(if_clause),
    {If1, State1} = build_if_chain(Clauses, Final, State0, Context),
    {copy_pos(Node, If1), State1}.

transform_try(Node, State0, Context) ->
    Clauses0 = erl_syntax:try_expr_clauses(Node),
    Handlers0 = erl_syntax:try_expr_handlers(Node),
    {Clauses1, State1} = instrument_try_clauses(
        Clauses0, try_success, State0, Context
    ),
    {Handlers1, State2} = instrument_try_clauses(
        Handlers0, try_exception, State1, Context
    ),
    {Clauses2, State3} = case Clauses1 of
        [] ->
            {Value, StateValue} = fresh_var(State2),
            {Hit, StateHit} = branch_call(
                source_line(Node), try_success, "result", StateValue, Context
            ),
            {[erl_syntax:clause([Value], none, [Hit, Value])], StateHit};
        _ -> {Clauses1, State2}
    end,
    Try1 = erl_syntax:try_expr(
        erl_syntax:try_expr_body(Node),
        Clauses2,
        Handlers1,
        erl_syntax:try_expr_after(Node)
    ),
    {copy_pos(Node, Try1), State3}.

instrument_try_clauses([], _Kind, State, _Context) -> {[], State};
instrument_try_clauses([Clause | Rest], Kind, State0, Context) ->
    Line = source_line(Clause),
    {Hit, State1} = branch_call(Line, Kind, "selected", State0, Context),
    Body = erl_syntax:clause_body(Clause),
    Clause1 = erl_syntax:clause(
        erl_syntax:clause_patterns(Clause),
        erl_syntax:clause_guard(Clause),
        [Hit | Body]
    ),
    {Rest1, State2} = instrument_try_clauses(Rest, Kind, State1, Context),
    {[copy_pos(Clause, Clause1) | Rest1], State2}.

transform_infix(Node, State0, Context) ->
    Operator = erl_syntax:operator_name(erl_syntax:infix_expr_operator(Node)),
    case Operator of
        'andalso' ->
            transform_short_circuit(Node, andalso_branch, false, State0, Context);
        'orelse' ->
            transform_short_circuit(Node, orelse_branch, true, State0, Context);
        _ -> {Node, State0}
    end.

transform_short_circuit(Node, Kind, ShortValue, State0, Context) ->
    Line = source_line(Node),
    Left = erl_syntax:infix_expr_left(Node),
    Right = erl_syntax:infix_expr_right(Node),
    {TrueHit, State1} = branch_call(Line, Kind, "left_true", State0, Context),
    {FalseHit, State2} = branch_call(Line, Kind, "left_false", State1, Context),
    TrueBody = case ShortValue of
        true -> [TrueHit, erl_syntax:atom(true)];
        false -> [TrueHit, Right]
    end,
    FalseBody = case ShortValue of
        true -> [FalseHit, Right];
        false -> [FalseHit, erl_syntax:atom(false)]
    end,
    Clauses = [
        erl_syntax:clause([erl_syntax:atom(true)], none, TrueBody),
        erl_syntax:clause([erl_syntax:atom(false)], none, FalseBody),
        erl_syntax:clause([erl_syntax:underscore()], none, [error_call(badarg)])
    ],
    {copy_pos(Node, erl_syntax:case_expr(Left, Clauses)), State2}.

needs_dispatch_rewrite(Clauses) ->
    length(Clauses) > 1 orelse
    lists:any(fun(C) -> erl_syntax:clause_guard(C) =/= none end, Clauses).

tuple_clause(Clause) ->
    TuplePattern = erl_syntax:tuple(erl_syntax:clause_patterns(Clause)),
    Clause1 = erl_syntax:clause(
        [TuplePattern], erl_syntax:clause_guard(Clause), erl_syntax:clause_body(Clause)
    ),
    copy_pos(Clause, Clause1).

build_clause_chain(_Value, [], Final, _Kind, State, _Context) ->
    {Final, State};
build_clause_chain(Value, [Clause | Rest], Final, Kind, State0, Context) ->
    {RestExpr, State1} = build_clause_chain(
        Value, Rest, Final, Kind, State0, Context
    ),
    {RestVar, State2} = fresh_var(State1),
    RestFun = erl_syntax:fun_expr([
        erl_syntax:clause([], none, [RestExpr])
    ]),
    RestBind = erl_syntax:match_expr(RestVar, RestFun),
    RestCall = erl_syntax:application(RestVar, []),
    Line = source_line(Clause),
    Guard = erl_syntax:clause_guard(Clause),
    {SelectedBody, State3} = case Guard of
        none ->
            {Hit, StateHit} = branch_call(Line, Kind, "selected", State2, Context),
            {[Hit | erl_syntax:clause_body(Clause)], StateHit};
        _ ->
            build_guarded_body(Guard, erl_syntax:clause_body(Clause), RestCall,
                Line, State2, Context)
    end,
    MatchClause = erl_syntax:clause(
        erl_syntax:clause_patterns(Clause), none, SelectedBody
    ),
    FallbackClause = erl_syntax:clause(
        [erl_syntax:underscore()], none, [RestCall]
    ),
    Case = erl_syntax:case_expr(Value, [MatchClause, FallbackClause]),
    {erl_syntax:block_expr([RestBind, Case]), State3}.

build_guarded_body(Guard, Body, RestCall, Line, State0, Context) ->
    case guard_always_true(Guard) of
        true ->
            {Hit, State1} = branch_call(Line, guard, "true", State0, Context),
            {[Hit | Body], State1};
        false ->
            SafeGuard = safe_guard_expression(Guard),
            {TrueHit, State1} = branch_call(Line, guard, "true", State0, Context),
            {FalseHit, State2} = branch_call(Line, guard, "false", State1, Context),
            GuardCase = erl_syntax:case_expr(SafeGuard, [
                erl_syntax:clause(
                    [erl_syntax:atom(true)], none, [TrueHit | Body]
                ),
                erl_syntax:clause(
                    [erl_syntax:atom(false)], none, [FalseHit, RestCall]
                )
            ]),
            {[GuardCase], State2}
    end.

build_if_chain([], Final, State, _Context) -> {Final, State};
build_if_chain([Clause | Rest], Final, State0, Context) ->
    {RestExpr, State1} = build_if_chain(Rest, Final, State0, Context),
    {RestVar, State2} = fresh_var(State1),
    RestFun = erl_syntax:fun_expr([erl_syntax:clause([], none, [RestExpr])]),
    RestBind = erl_syntax:match_expr(RestVar, RestFun),
    RestCall = erl_syntax:application(RestVar, []),
    Line = source_line(Clause),
    {GuardBody, State3} = build_guarded_body(
        erl_syntax:clause_guard(Clause), erl_syntax:clause_body(Clause), RestCall,
        Line, State2, Context
    ),
    {erl_syntax:block_expr([RestBind | GuardBody]), State3}.

safe_guard_expression(Guard) ->
    Conjunctions = erl_syntax:disjunction_body(Guard),
    Safe = [safe_conjunction(C) || C <- Conjunctions],
    fold_operator('orelse', Safe).

safe_conjunction(Conjunction) ->
    Expressions = erl_syntax:conjunction_body(Conjunction),
    Combined = fold_operator('andalso', Expressions),
    erl_syntax:infix_expr(
        erl_syntax:catch_expr(Combined),
        erl_syntax:operator('=:=') ,
        erl_syntax:atom(true)
    ).

fold_operator(_Operator, [Expression]) -> Expression;
fold_operator(Operator, [Expression | Rest]) ->
    erl_syntax:infix_expr(
        Expression, erl_syntax:operator(Operator), fold_operator(Operator, Rest)
    ).

guard_always_true(Guard) ->
    case erl_syntax:disjunction_body(Guard) of
        [Conjunction] ->
            case erl_syntax:conjunction_body(Conjunction) of
                [Expression] ->
                    erl_syntax:type(Expression) =:= atom andalso
                    erl_syntax:atom_value(Expression) =:= true;
                _ -> false
            end;
        _ -> false
    end.

branch_call(Line0, Kind, Outcome, State0, {Module, Function, Arity}) ->
    Id = State0#state.next_branch,
    Line = normalize_line(Line0),
    Branch = #branch{
        module = Module,
        function = Function,
        arity = Arity,
        line = Line,
        kind = Kind,
        outcome = Outcome,
        id = Id,
        critical = is_critical(Function)
    },
    Call = erl_syntax:application(
        erl_syntax:module_qualifier(
            erl_syntax:atom(avm_cbor_branch_counter), erl_syntax:atom(hit)
        ),
        [erl_syntax:atom(Module), erl_syntax:integer(Id)]
    ),
    {Call, State0#state{
        next_branch = Id + 1,
        branches = [Branch | State0#state.branches]
    }}.

fresh_vars(Count, State0) ->
    lists:mapfoldl(fun(_Index, State) -> fresh_var(State) end, State0,
        lists:seq(1, Count)).

fresh_var(State0) ->
    Id = State0#state.next_var,
    Name = list_to_atom("__CBOR_BRANCH_VAR_" ++ integer_to_list(Id)),
    {erl_syntax:variable(Name), State0#state{next_var = Id + 1}}.

error_call(Reason) when is_atom(Reason) ->
    error_call(erl_syntax:atom(Reason));
error_call(Reason) ->
    erl_syntax:application(
        erl_syntax:module_qualifier(erl_syntax:atom(erlang), erl_syntax:atom(error)),
        [Reason]
    ).

copy_pos(Source, Target) -> erl_syntax:set_pos(Target, erl_syntax:get_pos(Source)).

source_line(Node) ->
    normalize_line(erl_syntax:get_pos(Node)).

normalize_line(Line) when is_integer(Line), Line > 0 -> Line;
normalize_line(Anno) ->
    try erl_anno:line(Anno) of
        Line when is_integer(Line), Line > 0 -> Line;
        _ -> 0
    catch
        _:_ -> 0
    end.

is_critical(Function) ->
    lists:member(Function, [
        decode, decode_start, decode_continue, decode_normalized,
        start, continue, run, step, step_next,
        decode_all, decode_all_normalized,
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

compile_tests(OutDir) ->
    Files = filelib:wildcard("test/*.erl"),
    lists:foreach(
        fun(File) ->
            case compile:file(
                File,
                [debug_info, {d, 'BRANCH_COVERAGE'}, return_errors, return_warnings,
                 {i, "src"}, {outdir, OutDir}]
            ) of
                {ok, _Module} -> ok;
                {ok, _Module, _Warnings} -> ok;
                Error -> erlang:error({test_compile, File, Error})
            end
        end,
        Files
    ),
    true = code:add_patha(filename:absname(OutDir)),
    ok.

load_beam(OutDir, Module) ->
    BeamPath = filename:join(OutDir, atom_to_list(Module)),
    case code:load_abs(filename:absname(BeamPath)) of
        {module, Module} -> ok;
        Error -> erlang:error({load_beam, Module, Error})
    end.

load_binary(Module, Source, Beam) ->
    case code:load_binary(Module, Source, Beam) of
        {module, Module} -> ok;
        Error -> erlang:error({load_binary, Module, Error})
    end.

run_tests(_Modules) ->
    Tests = [
        avm_cbor_coverage_tests,
        avm_cbor_deterministic_decode_tests,
        avm_cbor_security_tests,
        avm_cbor_property_tests,
        avm_cbor_continuation_tests,
        avm_cbor_internal_branch_tests
    ],
    case eunit:test(Tests, [verbose]) of
        ok -> ok;
        Error -> erlang:error({instrumented_tests_failed, Error})
    end.

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

annotate(Manifest, Hits, ChangedLines) ->
    [
        {Branch,
         sets:is_element({Branch#branch.module, Branch#branch.id}, Hits),
         maps:is_key({module_source(Branch#branch.module), Branch#branch.line}, ChangedLines)}
        || Branch <- Manifest
    ].

module_source(avm_cbor) -> "src/avm_cbor.erl";
module_source(avm_cbor_cont) -> "src/avm_cbor_cont.erl";
module_source(avm_cbor_partial) -> "src/avm_cbor_partial.erl".

summarize(Results) ->
    #{
        total => metric(Results, fun(_B, _Changed) -> true end),
        changed => metric(Results, fun(_B, IsChanged) -> IsChanged end),
        critical => metric(Results, fun(B, _Changed) -> B#branch.critical end)
    }.

metric(Results, Predicate) ->
    lists:foldl(
        fun({Branch, Covered, Changed}, {Covered0, Total0}) ->
            case Predicate(Branch, Changed) of
                true -> {Covered0 + bool_int(Covered), Total0 + 1};
                false -> {Covered0, Total0}
            end
        end,
        {0, 0},
        Results
    ).

bool_int(true) -> 1;
bool_int(false) -> 0.

write_json(Summary, Results, Threshold) ->
    BranchJson = lists:join(",\n", [branch_json(Item) || Item <- Results]),
    {TotalCovered, TotalCount} = maps:get(total, Summary),
    {ChangedCovered, ChangedCount} = maps:get(changed, Summary),
    {CriticalCovered, CriticalCount} = maps:get(critical, Summary),
    Json = io_lib:format(
        "{\n  \"schema\": 1,\n  \"definition\": \"Instrumented source control-flow outcomes: case/if/function/fun clauses, guard true/false, short-circuit true/false, and try success/exception\",\n  \"threshold\": ~B,\n  \"summary\": {\n    \"total\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f},\n    \"changed\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f},\n    \"critical\": {\"covered\": ~B, \"total\": ~B, \"percent\": ~.4f}\n  },\n  \"branches\": [\n~s\n  ]\n}\n",
        [
            Threshold,
            TotalCovered, TotalCount, percentage(TotalCovered, TotalCount),
            ChangedCovered, ChangedCount, percentage(ChangedCovered, ChangedCount),
            CriticalCovered, CriticalCount, percentage(CriticalCovered, CriticalCount),
            BranchJson
        ]
    ),
    file:write_file("coverage/branches.json", Json).

write_summary_env(Summary) ->
    {TotalCovered, TotalCount} = maps:get(total, Summary),
    {ChangedCovered, ChangedCount} = maps:get(changed, Summary),
    {CriticalCovered, CriticalCount} = maps:get(critical, Summary),
    Data = io_lib:format(
        "TRUE_BRANCH_COVERED=~B~nTRUE_BRANCH_TOTAL=~B~nTRUE_BRANCH_COVERAGE=~.4f~n"
        "CHANGED_BRANCH_COVERED=~B~nCHANGED_BRANCH_TOTAL=~B~nCHANGED_BRANCH_COVERAGE=~.4f~n"
        "CRITICAL_BRANCH_COVERED=~B~nCRITICAL_BRANCH_TOTAL=~B~nCRITICAL_BRANCH_COVERAGE=~.4f~n",
        [
            TotalCovered, TotalCount, percentage(TotalCovered, TotalCount),
            ChangedCovered, ChangedCount, percentage(ChangedCovered, ChangedCount),
            CriticalCovered, CriticalCount, percentage(CriticalCovered, CriticalCount)
        ]
    ),
    file:write_file("coverage/branches.env", Data).

branch_json({Branch, Covered, Changed}) ->
    io_lib:format(
        "    {\"module\": \"~s\", \"function\": \"~s/~B\", \"line\": ~B, \"kind\": \"~s\", \"outcome\": \"~s\", \"id\": ~B, \"covered\": ~s, \"changed\": ~s, \"critical\": ~s}",
        [
            atom_to_list(Branch#branch.module), atom_to_list(Branch#branch.function),
            Branch#branch.arity, Branch#branch.line, atom_to_list(Branch#branch.kind),
            json_escape(Branch#branch.outcome), Branch#branch.id,
            json_bool(Covered), json_bool(Changed), json_bool(Branch#branch.critical)
        ]
    ).

json_escape(Text) ->
    lists:flatten([case C of $" -> "\\\""; $\\ -> "\\\\"; _ -> [C] end || C <- Text]).

json_bool(true) -> "true";
json_bool(false) -> "false".

write_uncovered(Results) ->
    Lines = [
        io_lib:format(
            "~s:~B ~s/~B ~s outcome=~s id=~B changed=~p critical=~p~n",
            [module_source(B#branch.module), B#branch.line,
             B#branch.function, B#branch.arity, B#branch.kind, B#branch.outcome,
             B#branch.id, Changed, B#branch.critical]
        )
        || {B, false, Changed} <- Results
    ],
    file:write_file("coverage/uncovered-branches.txt", Lines).

print_summary(Summary) ->
    print_metric("True branch coverage", maps:get(total, Summary)),
    print_changed_metric("Changed-branch coverage", maps:get(changed, Summary)),
    print_metric("Critical-path branch coverage", maps:get(critical, Summary)).

print_metric(Label, {Covered, Total}) ->
    io:format("~s: ~.2f% (~B/~B)~n", [Label, percentage(Covered, Total), Covered, Total]).

print_changed_metric(Label, {_Covered, 0}) ->
    io:format("~s: N/A (0/0; no changed executable branches)~n", [Label]);
print_changed_metric(Label, Metric) ->
    print_metric(Label, Metric).

enforce(Summary, Threshold) ->
    TotalPass = passes(maps:get(total, Summary), Threshold),
    ChangedPass = passes_if_present(maps:get(changed, Summary), Threshold),
    CriticalPass = passes(maps:get(critical, Summary), 100),
    case TotalPass andalso ChangedPass andalso CriticalPass of
        true ->
            io:format(
                "True branch gate passed: total >= ~B%; changed >= ~B% when present; critical = 100%.~n",
                [Threshold, Threshold]
            );
        false ->
            io:format(
                standard_error,
                "True branch gate failed: total must be >= ~B%; changed must be >= ~B% when present; critical must be 100%.~n",
                [Threshold, Threshold]
            ),
            halt(1)
    end.

passes_if_present({_Covered, 0}, _Threshold) -> true;
passes_if_present(Metric, Threshold) -> passes(Metric, Threshold).

percentage(_Covered, 0) -> 0.0;
percentage(Covered, Total) -> Covered * 100.0 / Total.

passes({_Covered, 0}, _Threshold) -> false;
passes({Covered, Total}, Threshold) -> Covered * 100 >= Total * Threshold.
