-module(avm_cbor_property_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/avm_cbor_opts.hrl").

-define(SEED, {2026, 7, 30}).

arbitrary_binary_never_throws_test() ->
    rand:seed(exsplus, ?SEED),
    run_random_binaries(2000, ?SEED).

arbitrary_terms_never_throw_test() ->
    rand:seed(exsplus, ?SEED),
    run_random_terms(1000, ?SEED).

continuation_matches_decode_property_test() ->
    rand:seed(exsplus, ?SEED),
    run_random_continuations(2000, ?SEED).

truncation_property_test() ->
    Terms = [
        [1, 2, 3],
        {map, [{1, {text, <<"alpha">>}}, {2, [3, 4]}]},
        {tag, 24, <<1, 2, 3, 4>>},
        {text, <<16#E2, 16#82, 16#AC>>}
    ],
    lists:foreach(fun truncations_are_controlled/1, Terms).

budgets_are_monotonic_test() ->
    {ok, Opts} = avm_cbor:normalize_partial_opts([
        {max_items, 4},
        {max_total_string_bytes, 5}
    ]),
    S0 = avm_cbor:new_decode_state(Opts),
    ?assertEqual(4, S0#cbor_decode_state.nodes_left),
    ?assertEqual(5, S0#cbor_decode_state.string_bytes_left),
    {ok, S1} = avm_cbor:consume_node(S0),
    {ok, S2} = avm_cbor:consume_node(S1),
    ?assertEqual(3, S1#cbor_decode_state.nodes_left),
    ?assertEqual(2, S2#cbor_decode_state.nodes_left),
    {ok, S3} = avm_cbor:consume_string_bytes(2, S2),
    {ok, S4} = avm_cbor:consume_string_bytes(3, S3),
    ?assertEqual(3, S3#cbor_decode_state.string_bytes_left),
    ?assertEqual(0, S4#cbor_decode_state.string_bytes_left),
    ?assertEqual(
        {error, {max_items_exceeded, 4}},
        consume_nodes_to_failure(S2, 3)
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 5}},
        avm_cbor:consume_string_bytes(1, S4)
    ).

nested_containers_never_reset_budget_test() ->
    Nested = <<16#82, 16#82, 1, 2, 16#82, 3, 4>>,
    ?assertEqual(
        {error, {max_items_exceeded, 6}},
        avm_cbor:decode(Nested, [{max_items, 6}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 6}},
        avm_cbor:partial_decode(Nested, [{max_items, 6}])
    ).

sequence_never_resets_budget_test() ->
    ?assertEqual(
        {error, {max_items_exceeded, 2}},
        avm_cbor:decode_all(<<1, 2, 3>>, [{max_items, 2}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 2}},
        avm_cbor:decode_sequence(<<1, 2, 3>>, [{max_items, 2}])
    ).

deterministic_encoding_is_stable_test() ->
    rand:seed(exsplus, ?SEED),
    Terms = [random_supported_term(3) || _ <- lists:seq(1, 500)],
    lists:foreach(fun(Term) -> assert_deterministic_stable(Term, ?SEED) end, Terms).

preferred_encodings_roundtrip_test() ->
    Terms = [
        0,
        23,
        24,
        -1,
        -25,
        <<>>,
        <<1, 2, 3>>,
        {text, <<"hello">>},
        [1, {text, <<"x">>}],
        {map, [{2, <<2>>}, {1, <<1>>}]},
        {tag, 1, 42},
        0.0,
        -0.0,
        1.5,
        65504.0,
        16777216.0,
        1.1
    ],
    lists:foreach(
        fun(Term) ->
            {ok, Bin} = avm_cbor:encode(Term, [{preferred, true}]),
            ?assertMatch({ok, _, <<>>}, avm_cbor:decode(Bin, [{preferred, true}]))
        end,
        Terms
    ).

non_preferred_encodings_are_rejected_test() ->
    Cases = [
        <<16#18, 23>>,
        <<16#19, 0, 16#FF>>,
        <<16#1A, 0, 0, 16#FF, 16#FF>>,
        <<16#1B, 0, 0, 0, 0, 16#FF, 16#FF, 16#FF, 16#FF>>,
        <<16#58, 1, 0>>,
        <<16#78, 1, $a>>
    ],
    lists:foreach(
        fun(Bin) -> ?assertMatch({error, _}, avm_cbor:decode(Bin, [{preferred, true}])) end,
        Cases
    ).

run_random_binaries(0, _Seed) -> ok;
run_random_binaries(Count, Seed) ->
    Bin = random_binary(128),
    assert_no_binary_exception(decode, fun avm_cbor:decode/1, Bin, Seed),
    assert_no_binary_exception(decode_all, fun avm_cbor:decode_all/1, Bin, Seed),
    assert_no_binary_exception(decode_sequence, fun avm_cbor:decode_sequence/1, Bin, Seed),
    assert_no_binary_exception(partial_decode, fun avm_cbor:partial_decode/1, Bin, Seed),
    run_random_binaries(Count - 1, Seed).

run_random_continuations(0, _Seed) -> ok;
run_random_continuations(Count, Seed) ->
    Bin = random_binary(128),
    Expected = case avm_cbor:decode(Bin, []) of
        {ok, Value, Rest} -> {done, Value, Rest};
        {error, _} = Err -> Err
    end,
    Actual = continue_binary(Bin, 3, 2048),
    case Actual =:= Expected of
        true -> run_random_continuations(Count - 1, Seed);
        false -> erlang:error({property_failure, continuation_matches_decode,
                               Seed, Bin, {Expected, Actual}})
    end.

run_random_terms(0, _Seed) -> ok;
run_random_terms(Count, Seed) ->
    Input = random_term(3),
    Opts = random_term(2),
    assert_no_term_exception(decode_1, fun avm_cbor:decode/1, Input, Seed),
    assert_no_term_exception(decode_2, fun(Value) -> avm_cbor:decode(Value, Opts) end,
                             {Input, Opts}, Seed),
    assert_no_term_exception(decode_all_1, fun avm_cbor:decode_all/1,
                             Input, Seed),
    assert_no_term_exception(decode_all_2, fun(Value) -> avm_cbor:decode_all(Value, Opts) end,
                             {Input, Opts}, Seed),
    assert_no_term_exception(decode_sequence_1,
                             fun avm_cbor:decode_sequence/1, Input, Seed),
    assert_no_term_exception(decode_sequence_2,
                             fun(Value) -> avm_cbor:decode_sequence(Value, Opts) end,
                             {Input, Opts}, Seed),
    assert_no_term_exception(partial_decode_1,
                             fun avm_cbor:partial_decode/1, Input, Seed),
    assert_no_term_exception(partial_decode_2,
                             fun(Value) -> avm_cbor:partial_decode(Value, Opts) end,
                             {Input, Opts}, Seed),
    assert_no_term_exception(decode_start,
                             fun(Value) -> avm_cbor:decode_start(Value, Opts) end,
                             {Input, Opts}, Seed),
    assert_no_term_exception(decode_continue,
                             fun(Value) -> avm_cbor:decode_continue(Value, Opts) end,
                             {Input, Opts}, Seed),
    PartialAccessors = [
        {partial_value_bytes, fun avm_cbor:partial_value_bytes/1},
        {partial_deep_decode, fun avm_cbor:partial_deep_decode/1},
        {partial_skip, fun avm_cbor:partial_skip/1},
        {partial_type, fun avm_cbor:partial_type/1},
        {partial_count, fun avm_cbor:partial_count/1},
        {partial_tag, fun avm_cbor:partial_tag/1},
        {partial_size, fun avm_cbor:partial_size/1},
        {partial_offset, fun avm_cbor:partial_offset/1},
        {partial_length, fun avm_cbor:partial_length/1},
        {partial_contents, fun avm_cbor:partial_contents/1}
    ],
    [assert_no_term_exception(Name, Fun, Input, Seed) || {Name, Fun} <- PartialAccessors],
    run_random_terms(Count - 1, Seed).

assert_no_binary_exception(Name, Fun, Bin, Seed) ->
    try Fun(Bin) of
        _ -> ok
    catch
        Class:Reason ->
            Minimized = minimize_binary(Bin, Fun),
            erlang:error({property_failure, Name, Seed, Minimized, {Class, Reason}})
    end.

assert_no_term_exception(Name, Fun, Input, Seed) ->
    TestInput = case Input of
        {Value, _Options} when Name =:= decode_2; Name =:= decode_all_2;
                              Name =:= decode_sequence_2; Name =:= partial_decode_2;
                              Name =:= decode_start; Name =:= decode_continue -> Value;
        _ -> Input
    end,
    try Fun(TestInput) of
        _ -> ok
    catch
        Class:Reason ->
            Minimized = minimize_term(TestInput, Fun),
            Payload = case Input of
                {_Value, Options} when Name =:= decode_2; Name =:= decode_all_2;
                                       Name =:= decode_sequence_2;
                                       Name =:= partial_decode_2;
                                       Name =:= decode_start;
                                       Name =:= decode_continue -> {Minimized, Options};
                _ -> Minimized
            end,
            erlang:error({property_failure, Name, Seed, Payload, {Class, Reason}})
    end.

assert_deterministic_stable(Term, Seed) ->
    Fun = fun(Value) ->
        First = avm_cbor:encode(Value, [{deterministic, true}]),
        First =/= avm_cbor:encode(Value, [{deterministic, true}])
    end,
    Outcome = try Fun(Term) of
        Value -> {ok, Value}
    catch
        CaughtClass:CaughtReason -> {exception, CaughtClass, CaughtReason}
    end,
    case Outcome of
        {ok, false} -> ok;
        {ok, true} ->
            Minimized = minimize_failing_term(Term, Fun),
            erlang:error({property_failure, deterministic_encoding_is_stable,
                          Seed, Minimized, unstable_encoding});
        {exception, ReportClass, ReportReason} ->
            Throwing = fun(Candidate) -> throws_term(Fun, Candidate) end,
            Minimized = minimize_failing_term(Term, Throwing),
            erlang:error({property_failure, deterministic_encoding_is_stable,
                          Seed, Minimized, {ReportClass, ReportReason}})
    end.

continue_binary(Bin, Budget, Remaining) ->
    case avm_cbor:decode_start(Bin, []) of
        {ok, Continuation} -> continue_state(Continuation, Budget, Remaining);
        {error, _} = Err -> Err
    end.

continue_state(_Continuation, _Budget, 0) -> continuation_step_limit;
continue_state(Continuation, Budget, Remaining) ->
    case avm_cbor:decode_continue(Continuation, Budget) of
        {more, Next} -> continue_state(Next, Budget, Remaining - 1);
        Result -> Result
    end.

minimize_binary(Bin, Fun) -> minimize_binary(Bin, Fun, 0).

minimize_binary(Bin, _Fun, Index) when Index >= byte_size(Bin) -> Bin;
minimize_binary(Bin, Fun, Index) ->
    Candidate = remove_byte(Bin, Index),
    case throws(Fun, Candidate) of
        true -> minimize_binary(Candidate, Fun, 0);
        false -> minimize_binary(Bin, Fun, Index + 1)
    end.

throws(Fun, Bin) ->
    try Fun(Bin) of
        _ -> false
    catch
        _:_ -> true
    end.

minimize_term(Term, Fun) ->
    minimize_failing_term(Term, fun(Candidate) -> throws_term(Fun, Candidate) end).

minimize_failing_term(Term, Predicate) ->
    Candidates = [Candidate || Candidate <- shrink_candidates(Term), Candidate =/= Term],
    case first_failing(Candidates, Predicate) of
        none -> Term;
        Smaller -> minimize_failing_term(Smaller, Predicate)
    end.

first_failing([], _Predicate) -> none;
first_failing([Candidate | Rest], Predicate) ->
    case Predicate(Candidate) of
        true -> Candidate;
        false -> first_failing(Rest, Predicate)
    end.

throws_term(Fun, Term) ->
    try Fun(Term) of
        _ -> false
    catch
        _:_ -> true
    end.

shrink_candidates(Bin) when is_binary(Bin), byte_size(Bin) > 0 ->
    Size = byte_size(Bin),
    Half = Size div 2,
    [<<>>, binary:part(Bin, 0, Half), binary:part(Bin, Half, Size - Half)];
shrink_candidates([Head | Tail]) -> [[], [Head], Tail, Head];
shrink_candidates(Tuple) when is_tuple(Tuple), tuple_size(Tuple) > 0 ->
    [element(Index, Tuple) || Index <- lists:seq(1, tuple_size(Tuple))] ++ [{}];
shrink_candidates(Integer) when is_integer(Integer), Integer =/= 0 -> [0];
shrink_candidates(Float) when is_float(Float), Float =/= +0.0 -> [+0.0];
shrink_candidates(Atom) when is_atom(Atom), Atom =/= undefined -> [undefined];
shrink_candidates(_) -> [].

remove_byte(Bin, Index) ->
    <<Prefix:Index/binary, _:8, Suffix/binary>> = Bin,
    <<Prefix/binary, Suffix/binary>>.

truncations_are_controlled(Term) ->
    {ok, Bin} = avm_cbor:encode(Term, [{preferred, true}]),
    truncations_are_controlled(Bin, 0, byte_size(Bin)).

truncations_are_controlled(_Bin, Size, Size) -> ok;
truncations_are_controlled(Bin, Size, FullSize) ->
    <<Prefix:Size/binary, _/binary>> = Bin,
    Result = avm_cbor:decode(Prefix),
    ?assertMatch({error, _}, Result),
    PartialResult = avm_cbor:partial_decode(Prefix),
    ?assertMatch({error, _}, PartialResult),
    truncations_are_controlled(Bin, Size + 1, FullSize).

consume_nodes_to_failure(State, 0) -> avm_cbor:consume_node(State);
consume_nodes_to_failure(State, Count) ->
    case avm_cbor:consume_node(State) of
        {ok, State1} -> consume_nodes_to_failure(State1, Count - 1);
        {error, _} = Err -> Err
    end.

random_binary(MaxLength) ->
    Length = rand:uniform(MaxLength + 1) - 1,
    list_to_binary([rand:uniform(256) - 1 || _ <- lists:seq(1, Length)]).

random_term(0) ->
    case rand:uniform(7) of
        1 -> rand:uniform(200) - 100;
        2 -> random_binary(16);
        3 -> random_atom();
        4 -> [];
        5 -> {};
        6 -> 1.5;
        7 -> {simple, rand:uniform(300) - 1}
    end;
random_term(Depth) ->
    case rand:uniform(7) of
        1 -> random_term(0);
        2 -> [random_term(Depth - 1), random_term(Depth - 1)];
        3 -> {random_term(Depth - 1), random_term(Depth - 1)};
        4 -> [random_term(Depth - 1) | random_term(0)];
        5 -> {map, [{random_term(Depth - 1), random_term(Depth - 1)}]};
        6 -> {text, random_binary(8)};
        7 -> random_binary(32)
    end.

random_supported_term(0) ->
    case rand:uniform(6) of
        1 -> rand:uniform(1000) - 500;
        2 -> random_binary(12);
        3 -> {text, <<"text">>};
        4 -> rand:uniform() * 100.0;
        5 -> true;
        6 -> null
    end;
random_supported_term(Depth) ->
    case rand:uniform(4) of
        1 -> random_supported_term(0);
        2 -> [random_supported_term(Depth - 1), random_supported_term(Depth - 1)];
        3 -> {map, [{random_supported_term(0), random_supported_term(Depth - 1)}]};
        4 -> {tag, rand:uniform(32) - 1, random_supported_term(Depth - 1)}
    end.

random_atom() ->
    case rand:uniform(6) of
        1 -> true;
        2 -> false;
        3 -> null;
        4 -> undefined;
        5 -> invalid;
        6 -> atom
    end.
