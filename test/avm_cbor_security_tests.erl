-module(avm_cbor_security_tests).

-include_lib("eunit/include/eunit.hrl").

deterministic_decode_boundaries_test() ->
    Opts = [{deterministic, true}],
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:decode(<<16#81, 16#9F, 1, 16#FF>>, Opts)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:decode(<<16#A2, 2, 0, 1, 0>>, Opts)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:partial_decode(<<16#A2, 2, 0, 1, 0>>, Opts)
    ),
    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:partial_decode(<<16#A2, 1, 0, 1, 1>>, Opts)
    ).

global_node_budget_test() ->
    Nested = <<16#82, 16#82, 1, 2, 16#82, 3, 4>>,
    ?assertEqual(
        {error, {max_items_exceeded, 6}},
        avm_cbor:decode(Nested, [{max_items, 6}])
    ),
    ?assertEqual(
        {ok, [[1, 2], [3, 4]], <<>>},
        avm_cbor:decode(Nested, [{max_items, 7}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 6}},
        avm_cbor:partial_decode(Nested, [{max_items, 6}])
    ),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(Nested, [{max_items, 7}])).

wide_container_boundaries_test() ->
    Array = <<16#83, 1, 2, 3>>,
    ?assertEqual(
        {error, {max_items_exceeded, 3}},
        avm_cbor:decode(Array, [{max_items, 3}])
    ),
    ?assertEqual({ok, [1, 2, 3], <<>>}, avm_cbor:decode(Array, [{max_items, 4}])),
    Map = <<16#A2, 1, 2, 3, 4>>,
    ?assertEqual(
        {error, {max_items_exceeded, 4}},
        avm_cbor:decode(Map, [{max_items, 4}])
    ),
    ?assertEqual(
        {ok, {map, [{1, 2}, {3, 4}]}, <<>>},
        avm_cbor:decode(Map, [{max_items, 5}])
    ).

fixed_cost_container_boundaries_test() ->
    ArrayPayload = binary:copy(<<0>>, 4095),
    Array = <<16#99, 4095:16, ArrayPayload/binary>>,
    ?assertMatch(
        {ok, Values, <<>>} when length(Values) =:= 4095,
        avm_cbor:decode(Array)
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 4095}},
        avm_cbor:decode(Array, [{max_items, 4095}])
    ),
    ?assertEqual(
        {error, {max_bytes_exceeded, 4097}},
        avm_cbor:decode(Array, [{max_bytes, 4097}])
    ),
    OverArrayPayload = binary:copy(<<0>>, 4096),
    OverArray = <<16#99, 4096:16, OverArrayPayload/binary>>,
    ?assertEqual(
        {error, {max_items_exceeded, 4096}},
        avm_cbor:decode(OverArray)
    ),
    ?assertMatch(
        {ok, OverValues, <<>>} when length(OverValues) =:= 4096,
        avm_cbor:decode(OverArray, [{max_items, 4097}])
    ),
    TruncatedArray = <<16#99, 4095:16, (binary:copy(<<0>>, 4094))/binary>>,
    ?assertEqual({error, truncated}, avm_cbor:decode(TruncatedArray)),
    ?assertEqual(
        {error, reserved_additional_info},
        avm_cbor:decode(<<16#98, 64, 16#FC>>)
    ),
    Pairs = binary:copy(<<0, 0>>, 2047),
    TaggedMap = <<16#C0, 16#B9, 2047:16, Pairs/binary>>,
    ?assertMatch(
        {ok, {tag, 0, {map, Values}}, <<>>} when length(Values) =:= 2047,
        avm_cbor:decode(TaggedMap)
    ),
    OverPairs = binary:copy(<<0, 0>>, 2048),
    OverTaggedMap = <<16#C0, 16#B9, 2048:16, OverPairs/binary>>,
    ?assertEqual(
        {error, {max_items_exceeded, 4096}},
        avm_cbor:decode(OverTaggedMap)
    ),
    ?assertMatch(
        {ok, {tag, 0, {map, Values}}, <<>>} when length(Values) =:= 2048,
        avm_cbor:decode(OverTaggedMap, [{max_items, 4098}])
    ),
    ?assertEqual(
        {error, reserved_additional_info},
        avm_cbor:decode(<<16#B8, 64, 16#FC>>)
    ),
    ?assertEqual(
        {error, unexpected_break},
        avm_cbor:decode(<<16#B8, 64, 16#FF>>)
    ).

fixed_cost_container_fallback_test() ->
    ?assertEqual(
        {ok, [0, 24, -1], <<>>},
        avm_cbor:decode(<<16#83, 0, 16#18, 24, 16#20>>)
    ),
    ?assertEqual(
        {ok, [0, false, true], <<>>},
        avm_cbor:decode(<<16#83, 0, 16#F4, 16#F5>>)
    ),
    ?assertEqual(
        {error, {unsupported_simple_value, 1}},
        avm_cbor:decode(<<16#82, 0, 16#E1>>, [{allow_simple, false}])
    ),
    ?assertEqual(
        {error, reserved_additional_info},
        avm_cbor:decode(<<16#82, 0, 16#FC>>)
    ),
    ?assertEqual(
        {error, unexpected_break},
        avm_cbor:decode(<<16#82, 0, 16#FF>>)
    ),
    ?assertEqual(
        {ok, {map, [{0, 0}, {1, 24}]}, <<>>},
        avm_cbor:decode(<<16#A2, 0, 0, 1, 16#18, 24>>)
    ),
    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:decode(<<16#A2, 0, 0, 0, 0>>, [{deterministic, true}])
    ),
    ?assertEqual(
        {ok, {map, [{0, 0}, {1, 0}]}, <<>>},
        avm_cbor:decode(<<16#A2, 0, 0, 1, 0>>, [{deterministic, true}])
    ).

fixed_cost_container_nested_budget_test() ->
    ?assertEqual(
        {error, {max_items_exceeded, 3}},
        avm_cbor:decode(<<16#82, 16#81, 0, 0>>, [{max_items, 3}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 4}},
        avm_cbor:decode(
            <<16#83, 16#82, 0, 0, 0, 16#40>>, [{max_items, 4}]
        )
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 5}},
        avm_cbor:decode(
            <<16#A2, 0, 16#82, 0, 0, 0, 0>>, [{max_items, 5}]
        )
    ).

depth_boundaries_test() ->
    DeepArrays = <<16#81, 16#81, 16#81, 1>>,
    ?assertEqual(
        {error, {max_depth_exceeded, 2}},
        avm_cbor:decode(DeepArrays, [{max_depth, 2}])
    ),
    ?assertEqual(
        {ok, [[[1]]], <<>>},
        avm_cbor:decode(DeepArrays, [{max_depth, 3}])
    ),
    DeepMaps = <<16#A1, 1, 16#A1, 2, 16#A1, 3, 4>>,
    ?assertEqual(
        {error, {max_depth_exceeded, 2}},
        avm_cbor:decode(DeepMaps, [{max_depth, 2}])
    ),
    ?assertMatch({ok, _, <<>>}, avm_cbor:decode(DeepMaps, [{max_depth, 3}])),
    Alternating = <<16#81, 16#A1, 1, 16#81, 2>>,
    ?assertEqual(
        {error, {max_depth_exceeded, 2}},
        avm_cbor:decode(Alternating, [{max_depth, 2}])
    ),
    ?assertMatch({ok, _, <<>>}, avm_cbor:decode(Alternating, [{max_depth, 3}])).

cumulative_string_boundaries_test() ->
    Strings = <<16#83, 16#41, $a, 16#41, $b, 16#41, $c>>,
    BaseOpts = [{max_items, 4}, {max_string_bytes, 1}],
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 2}},
        avm_cbor:decode(Strings, [{max_total_string_bytes, 2} | BaseOpts])
    ),
    ?assertEqual(
        {ok, [<<"a">>, <<"b">>, <<"c">>], <<>>},
        avm_cbor:decode(Strings, [{max_total_string_bytes, 3} | BaseOpts])
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 2}},
        avm_cbor:partial_decode(Strings, [{max_total_string_bytes, 2} | BaseOpts])
    ),
    ?assertMatch(
        {ok, _, <<>>},
        avm_cbor:partial_decode(Strings, [{max_total_string_bytes, 3} | BaseOpts])
    ),
    TextStrings = <<16#82, 16#61, $a, 16#61, $b>>,
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 1}},
        avm_cbor:decode(TextStrings, [{max_items, 3}, {max_total_string_bytes, 1}])
    ).

indefinite_chunk_boundaries_test() ->
    EmptyChunks = <<16#5F, 16#40, 16#40, 16#40, 16#FF>>,
    ?assertEqual(
        {error, {max_items_exceeded, 3}},
        avm_cbor:decode(EmptyChunks, [{max_items, 3}])
    ),
    ?assertEqual({ok, <<>>, <<>>}, avm_cbor:decode(EmptyChunks, [{max_items, 4}])),
    OneByteChunks = one_byte_chunks(1000),
    ?assertEqual(
        {error, {max_items_exceeded, 1000}},
        avm_cbor:decode(
            OneByteChunks,
            [{max_items, 1000}, {max_string_bytes, 1000},
             {max_total_string_bytes, 1000}]
        )
    ),
    ?assertMatch(
        {ok, Value, <<>>} when byte_size(Value) =:= 1000,
        avm_cbor:decode(
            OneByteChunks,
            [{max_items, 1001}, {max_string_bytes, 1000},
             {max_total_string_bytes, 1000}]
        )
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 999}},
        avm_cbor:decode(
            OneByteChunks,
            [{max_items, 1001}, {max_string_bytes, 1000},
             {max_total_string_bytes, 999}]
        )
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 1}},
        avm_cbor:decode(
            <<16#7F, 16#61, $a, 16#61, $b, 16#FF>>,
            [{max_total_string_bytes, 1}]
        )
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 1}},
        avm_cbor:partial_decode(
            <<16#7F, 16#61, $a, 16#61, $b, 16#FF>>,
            [{max_total_string_bytes, 1}]
        )
    ),
    ?assertEqual(
        {error, {max_total_string_bytes_exceeded, 1}},
        avm_cbor:partial_decode(<<16#62, $a, $b>>, [{max_total_string_bytes, 1}])
    ),
    ?assertEqual(
        {error, {invalid_indefinite_chunk, expected_text_string}},
        avm_cbor:partial_decode(<<16#7F, 16#7F, 16#FF, 16#FF>>)
    ).

declared_length_failures_test() ->
    %% A definite declaration needs at least one remaining byte per child.
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#83, 1, 2>>)),
    ?assertEqual({ok, [1, 2, 3], <<>>}, avm_cbor:decode(<<16#83, 1, 2, 3>>)),
    ?assertEqual({ok, [1, 2, 3], <<4>>}, avm_cbor:decode(<<16#83, 1, 2, 3, 4>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#83, 1, 2>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#83, 1, 2, 3>>)),
    ?assertMatch({ok, _, <<4>>}, avm_cbor:partial_decode(<<16#83, 1, 2, 3, 4>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#A2, 1, 2, 3>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:decode(<<16#A2, 1, 2, 3, 4>>)),
    ?assertMatch({ok, _, <<5>>}, avm_cbor:decode(<<16#A2, 1, 2, 3, 4, 5>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#A2, 1, 2, 3>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#A2, 1, 2, 3, 4>>)),
    ?assertMatch({ok, _, <<5>>}, avm_cbor:partial_decode(<<16#A2, 1, 2, 3, 4, 5>>)),
    Huge = 16#FFFFFFFFFFFFFFFF,
    HugeString = <<16#5B, Huge:64>>,
    HugeLimits = [
        {max_bytes, 9},
        {max_string_bytes, Huge},
        {max_total_string_bytes, Huge}
    ],
    ?assertEqual({error, truncated}, avm_cbor:decode(HugeString, HugeLimits)),
    ?assertEqual(
        {error, truncated},
        avm_cbor:partial_decode(HugeString, [{max_string_size, Huge} | HugeLimits])
    ),
    HugeArray = <<16#9B, Huge:64>>,
    HugeNodeLimit = Huge + 1,
    ?assertEqual(
        {error, truncated},
        avm_cbor:decode(HugeArray, [{max_bytes, 9}, {max_items, HugeNodeLimit}])
    ),
    ?assertEqual(
        {error, truncated},
        avm_cbor:partial_decode(HugeArray, [{max_bytes, 9}, {max_items, HugeNodeLimit}])
    ).

sequence_and_tag_budget_test() ->
    ?assertEqual(
        {error, {max_items_exceeded, 2}},
        avm_cbor:decode_all(<<1, 2, 3>>, [{max_items, 2}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 2}},
        avm_cbor:decode_sequence(<<1, 2, 3>>, [{max_items, 2}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 1}},
        avm_cbor:decode(<<16#C1, 1>>, [{max_items, 1}])
    ),
    ?assertEqual(
        {ok, {tag, 1, 1}, <<>>},
        avm_cbor:decode(<<16#C1, 1>>, [{max_items, 2}])
    ).

malformed_map_termination_test() ->
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#A1, 1>>)),
    ?assertEqual({error, unexpected_break}, avm_cbor:decode(<<16#BF, 1, 16#FF>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#BF, 1, 2>>)),
    ?assertEqual({error, unexpected_break}, avm_cbor:partial_decode(<<16#BF, 1, 16#FF>>)).

public_boundary_errors_test() ->
    InvalidInputs = [not_binary, 1, [], {}, {map, []}],
    [?assertEqual({error, invalid_input}, avm_cbor:decode(Value)) || Value <- InvalidInputs],
    [?assertEqual({error, invalid_input}, avm_cbor:decode_all(Value)) || Value <- InvalidInputs],
    [?assertEqual({error, invalid_input}, avm_cbor:decode_sequence(Value)) ||
        Value <- InvalidInputs],
    [?assertEqual({error, invalid_input}, avm_cbor:partial_decode(Value)) ||
        Value <- InvalidInputs],
    ?assertEqual({error, invalid_input}, avm_cbor:decode(not_binary, not_a_list)),
    ?assertEqual({error, invalid_input}, avm_cbor:decode_all(not_binary, not_a_list)),
    ?assertEqual({error, invalid_input}, avm_cbor:decode_sequence(not_binary, not_a_list)),
    ?assertEqual({error, invalid_input}, avm_cbor:partial_decode(not_binary, not_a_list)),
    ?assertEqual({error, invalid_options_list}, avm_cbor:decode(<<1>>, not_a_list)),
    ?assertEqual({error, invalid_options_list}, avm_cbor:decode_all(<<1>>, not_a_list)),
    ?assertEqual({error, invalid_options_list}, avm_cbor:decode_sequence(<<1>>, not_a_list)),
    ?assertEqual({error, invalid_options_list}, avm_cbor:partial_decode(<<1>>, not_a_list)),
    InvalidBooleanOptions = [
        allow_floats, allow_simple, allow_tags, allow_indefinite, preferred, deterministic
    ],
    [?assertEqual(
        {error, {invalid_option, {Name, invalid}}},
        avm_cbor:decode(<<1>>, [{Name, invalid}])
    ) || Name <- InvalidBooleanOptions],
    InvalidEncodeValues = [
        {text, not_binary},
        {simple, -1},
        {simple, 256},
        {tag, not_an_integer, 1},
        {map, not_a_list}
    ],
    [?assertMatch({error, {unsupported_value, _}}, avm_cbor:encode(Value)) ||
        Value <- InvalidEncodeValues].

forged_partial_descriptor_test() ->
    Forged = {cbor_partial, array, 0, 999, undefined, undefined, undefined,
              999, false, not_binary, not_options, none},
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_value_bytes(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_deep_decode(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_contents(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_skip(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_type(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_count(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_tag(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_size(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_offset(Forged)),
    ?assertEqual({error, not_a_partial}, avm_cbor:partial_length(Forged)),
    {ok, Valid, <<>>} = avm_cbor:partial_decode(<<16#80>>),
    InvalidFields = [
        setelement(2, Valid, invalid_type),
        setelement(3, Valid, not_integer),
        setelement(3, Valid, -1),
        setelement(4, Valid, not_integer),
        setelement(4, Valid, 0),
        setelement(5, Valid, -1),
        setelement(6, Valid, -1),
        setelement(7, Valid, -1),
        setelement(8, Valid, not_integer),
        setelement(8, Valid, 0),
        setelement(8, Valid, 2),
        setelement(9, Valid, invalid),
        setelement(10, Valid, not_binary),
        setelement(10, Valid, <<16#80, 0>>),
        setelement(9, Valid, true),
        setelement(11, Valid, not_options),
        setelement(12, Valid, invalid),
        setelement(12, Valid, {some}),
        setelement(12, Valid, {invalid, value})
    ],
    [?assertEqual({error, not_a_partial}, avm_cbor:partial_skip(Invalid)) ||
        Invalid <- InvalidFields],
    Trailing = setelement(10, setelement(4, Valid, 2), <<16#80, 0>>),
    ?assertEqual({error, {trailing_bytes, 1}}, avm_cbor:partial_deep_decode(Trailing)),
    InvalidCbor = setelement(10, Valid, <<16#1C>>),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:partial_deep_decode(InvalidCbor)),
    {ok, Scalar, <<>>} = avm_cbor:partial_decode(<<1>>),
    ?assertEqual(
        {error, not_a_partial},
        avm_cbor:partial_deep_decode(setelement(4, Scalar, 0))
    ),
    ?assertEqual({error, no_contents}, avm_cbor:partial_contents(Scalar)).

one_byte_chunks(Count) ->
    list_to_binary([16#5F, lists:duplicate(Count, <<16#41, 0>>), 16#FF]).
