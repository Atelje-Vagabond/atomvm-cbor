-module(avm_cbor_continuation_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MAX_STEPS, 20000).

public_boundary_test() ->
    ?assertEqual({error, invalid_input}, avm_cbor:decode_start(not_binary, [])),
    ?assertEqual({error, invalid_options_list}, avm_cbor:decode_start(<<1>>, invalid)),
    ?assertEqual(
        {error, {invalid_option, {max_items, 0}}},
        avm_cbor:decode_start(<<1>>, [{max_items, 0}])
    ),
    ?assertEqual({error, empty}, avm_cbor:decode_start(<<>>, [])),
    ?assertEqual({error, {invalid_budget, 0}}, avm_cbor:decode_continue(invalid, 0)),
    ?assertEqual({error, {invalid_budget, -1}}, avm_cbor:decode_continue(invalid, -1)),
    ?assertEqual({error, {invalid_budget, invalid}},
                 avm_cbor:decode_continue(invalid, invalid)),
    ?assertEqual({error, invalid_continuation}, avm_cbor:decode_continue(invalid, 1)),
    ?assertEqual({error, invalid_continuation},
                 avm_cbor:decode_continue({cbor_cont, 1, invalid}, 1)).

exact_budget_and_replay_test() ->
    {ok, Start} = avm_cbor:decode_start(<<1, 2>>, []),
    {more, AfterParse} = avm_cbor:decode_continue(Start, 1),
    ?assertEqual({done, 1, <<2>>}, avm_cbor:decode_continue(AfterParse, 1)),
    %% Continuations are immutable values: replaying the original state is safe.
    ?assertEqual({done, 1, <<2>>}, avm_cbor:decode_continue(Start, 2)).

representative_equivalence_test() ->
    Cases = [
        {<<0, 99>>, []},
        {<<16#1B, 0, 0, 0, 1, 0, 0, 0, 0>>, []},
        {<<16#38, 99>>, []},
        {<<16#43, 1, 2, 3>>, []},
        {<<16#63, "abc">>, []},
        {<<16#83, 1, 16#82, 2, 3, 4>>, []},
        {<<16#A2, 1, 2, 3, 4>>, []},
        {<<16#C1, 16#82, 1, 2>>, []},
        {<<16#F9, 16#3E, 0>>, []},
        {<<16#FA, 16#3F, 16#C0, 0, 0>>, []},
        {<<16#FB, 16#3F, 16#F8, 0, 0, 0, 0, 0, 0>>, []},
        {<<16#5F, 16#42, 1, 2, 16#41, 3, 16#FF>>, []},
        {<<16#7F, 16#62, "ab", 16#61, "c", 16#FF>>, []},
        {<<16#9F, 1, 16#82, 2, 3, 16#FF>>, []},
        {<<16#BF, 1, 2, 3, 4, 16#FF>>, []},
        {<<16#A2, 1, 0, 2, 0>>, [{deterministic, true}]},
        {<<16#18, 23>>, [{preferred, true}]},
        {<<16#9F, 1, 16#FF>>, [{allow_indefinite, false}]},
        {<<16#C1, 1>>, [{allow_tags, false}]},
        {<<16#F5>>, [{allow_floats, false}]}
    ],
    lists:foreach(
        fun({Bin, Opts}) ->
            assert_equivalent(Bin, Opts, 1),
            assert_equivalent(Bin, Opts, 7)
        end,
        Cases
    ).

controlled_error_equivalence_test() ->
    Cases = [
        {<<16#82, 1>>, []},
        {<<16#A1, 1>>, []},
        {<<16#BF, 1, 16#FF>>, []},
        {<<16#7F, 16#61, 16#80, 16#FF>>, []},
        {<<16#7F, 16#5F, 16#FF, 16#FF>>, []},
        {<<16#A2, 2, 0, 1, 0>>, [{deterministic, true}]},
        {<<16#A2, 1, 0, 1, 1>>, [{deterministic, true}]},
        {<<16#9F, 1, 16#FF>>, [{deterministic, true}]},
        {<<16#82, 1, 2>>, [{max_items, 2}]},
        {<<16#9F, 1, 2, 16#FF>>, [{max_items, 2}]},
        {<<16#81, 16#81, 1>>, [{max_depth, 1}]},
        {<<16#A1, 1, 16#A1, 2, 3>>, [{max_depth, 1}]},
        {<<16#9F, 16#9F, 1, 16#FF, 16#FF>>, [{max_depth, 1}]},
        {<<16#BF, 1, 16#BF, 2, 3, 16#FF, 16#FF>>, [{max_depth, 1}]},
        {<<16#C1, 1>>, [{max_items, 1}]},
        {<<16#C1>>, []},
        {<<16#E0>>, [{allow_simple, false}]},
        {<<16#42, $a, $b>>, [{max_total_string_bytes, 1}]},
        {<<16#62, $a, $b>>, [{max_total_string_bytes, 1}]},
        {<<16#82, 16#FF>>, []},
        {<<16#5F>>, []},
        {<<16#5F, 0, 16#FF>>, []},
        {<<16#5F, 16#42, 1>>, []},
        {<<16#5F, 16#42, 1, 2, 16#FF>>, [{max_string_bytes, 1}]},
        {<<16#5F, 16#42, 1, 2, 16#FF>>, [{max_total_string_bytes, 1}]},
        {<<16#5F, 16#40, 16#FF>>, [{max_items, 1}]}
    ],
    [assert_equivalent(Bin, Opts, 1) || {Bin, Opts} <- Cases].

utf8_scan_boundary_test() ->
    Prefix = binary:copy(<<$a>>, 255),
    Text = <<Prefix/binary, 16#E2, 16#82, 16#AC>>,
    Bin = <<16#79, (byte_size(Text)):16, Text/binary>>,
    assert_equivalent(Bin, [], 1),
    BadText = <<Prefix/binary, 16#E2, 16#28, 16#A1>>,
    BadBin = <<16#79, (byte_size(BadText)):16, BadText/binary>>,
    assert_equivalent(BadBin, [], 1).

utf8_all_forms_test() ->
    Values = [
        <<$a>>,
        <<16#C2, 16#A9>>,
        <<16#E0, 16#A0, 16#80>>,
        <<16#E1, 16#80, 16#80>>,
        <<16#ED, 16#9F, 16#BF>>,
        <<16#EE, 16#80, 16#80>>,
        <<16#F0, 16#90, 16#80, 16#80>>,
        <<16#F1, 16#80, 16#80, 16#80>>,
        <<16#F4, 16#8F, 16#BF, 16#BF>>
    ],
    [assert_equivalent(<<(16#60 + byte_size(Value)), Value/binary>>, [], 1) ||
        Value <- Values].

indefinite_text_scan_segments_test() ->
    Text = binary:copy(<<$a>>, 300),
    Bin = <<16#7F, 16#79, 300:16, Text/binary, 16#FF>>,
    assert_equivalent(Bin, [], 1),
    BadText = <<(binary:copy(<<$a>>, 299))/binary, 16#80>>,
    BadBin = <<16#7F, 16#79, 300:16, BadText/binary, 16#FF>>,
    assert_equivalent(BadBin, [], 1).

opaque_state_validation_test() ->
    {ok, Start = {cbor_cont, 1, {next, <<1>>, [], State, 0}}} =
        avm_cbor:decode_start(<<1>>, []),
    ?assertError(function_clause, avm_cbor_cont:start(<<1>>, invalid_state)),
    ?assertError(function_clause, avm_cbor_cont:start(not_binary, State)),
    BadOptsState = setelement(2, State, invalid_opts),
    ?assertEqual(
        {error, invalid_continuation},
        avm_cbor:decode_continue(
            {cbor_cont, 1, {next, <<16#40>>, [], BadOptsState, 0}}, 1)
    ),
    ForgedModes = [
        {next, <<1>>, [], State, -1},
        {emit, 1, invalid_rest, [], State},
        {validate_text, <<>>, invalid_scan, <<>>, [], State},
        {validate_indef_text, <<>>, <<>>, <<>>, [], State, 0, -1, []},
        {reverse, [], [], invalid_kind, <<>>, [], State},
        {join_binary, [], invalid_kind, <<>>, [], State}
    ],
    [?assertEqual({error, invalid_continuation},
                  avm_cbor:decode_continue({cbor_cont, 1, Mode}, 1)) ||
        Mode <- ForgedModes],
    ?assertEqual(
        {error, invalid_continuation},
        avm_cbor:decode_continue({cbor_cont, 1, {emit, 1, <<>>, [invalid], State}}, 1)
    ),
    ?assertEqual(
        {error, invalid_continuation},
        avm_cbor:decode_continue(
            {cbor_cont, 1,
                {emit, key, <<1>>, [{map_key, 1, [], 1, none, <<>>}], State}},
            1)
    ),
    ?assertMatch({more, _}, avm_cbor:decode_continue(Start, 1)).

maximum_depth_explicit_frames_test() ->
    Bin = nested_arrays(128, <<0>>),
    ?assertEqual(129, byte_size(Bin)),
    assert_equivalent(Bin, [{max_depth, 128}, {max_items, 129}], 1),
    ?assertEqual(
        {error, {max_depth_exceeded, 127}},
        continue_binary(Bin, [{max_depth, 127}, {max_items, 129}], 1)
    ).

maximum_node_budget_test_() ->
    {timeout, 30, fun maximum_node_budget/0}.

maximum_node_budget() ->
    Items = binary:copy(<<0>>, 4095),
    Bin = <<16#99, 4095:16, Items/binary>>,
    ?assertMatch({done, Values, <<>>} when length(Values) =:= 4095,
                 continue_binary(Bin, [{max_items, 4096}], 31)),
    ?assertEqual(
        {error, {max_items_exceeded, 4095}},
        continue_binary(Bin, [{max_items, 4095}], 31)
    ),
    Pairs = binary:copy(<<0, 0>>, 2047),
    TaggedMap = <<16#C0, 16#B9, 2047:16, Pairs/binary>>,
    ?assertMatch(
        {ok, {tag, 0, {map, DecodedPairs}}, <<>>}
            when length(DecodedPairs) =:= 2047,
        avm_cbor:decode(TaggedMap)
    ),
    ?assertMatch(
        {done, {tag, 0, {map, ContinuedPairs}}, <<>>}
            when length(ContinuedPairs) =:= 2047,
        continue_binary(TaggedMap, [], 31)
    ).

maximum_string_and_input_size_test_() ->
    {timeout, 30, fun maximum_string_and_input_size/0}.

maximum_string_and_input_size() ->
    Text = binary:copy(<<$x>>, 65536),
    StringBin = <<16#7A, 65536:32, Text/binary>>,
    ?assertMatch({done, {text, Value}, <<>>} when byte_size(Value) =:= 65536,
                 continue_binary(StringBin, [], 1)),
    FullInput = <<0, (binary:copy(<<0>>, 1048575))/binary>>,
    ?assertMatch({done, 0, Rest} when byte_size(Rest) =:= 1048575,
                 continue_binary(FullInput, [], 1)),
    TooLarge = <<FullInput/binary, 0>>,
    ?assertEqual(
        {error, {max_bytes_exceeded, 1048576}},
        avm_cbor:decode_start(TooLarge, [])
    ).

continuation_never_embeds_wait_test() ->
    {ok, Source} = file:read_file("src/avm_cbor_cont.erl"),
    ?assertEqual(nomatch, binary:match(Source, <<"timer:sleep">>)),
    ?assertEqual(nomatch, binary:match(Source, <<"erlang:yield">>)),
    ?assertEqual(nomatch, binary:match(Source, <<"receive after">>)).

assert_equivalent(Bin, Opts, Budget) ->
    Expected = case avm_cbor:decode(Bin, Opts) of
        {ok, Value, Rest} -> {done, Value, Rest};
        {error, _} = Err -> Err
    end,
    ?assertEqual(Expected, continue_binary(Bin, Opts, Budget)).

continue_binary(Bin, Opts, Budget) ->
    case avm_cbor:decode_start(Bin, Opts) of
        {ok, Continuation} -> continue_to_result(Continuation, Budget, ?MAX_STEPS);
        {error, _} = Err -> Err
    end.

continue_to_result(_Continuation, _Budget, 0) ->
    erlang:error(continuation_step_limit);
continue_to_result(Continuation, Budget, Remaining) ->
    case avm_cbor:decode_continue(Continuation, Budget) of
        {more, Next} -> continue_to_result(Next, Budget, Remaining - 1);
        Result -> Result
    end.

nested_arrays(0, Inner) -> Inner;
nested_arrays(Count, Inner) -> nested_arrays(Count - 1, <<16#81, Inner/binary>>).

