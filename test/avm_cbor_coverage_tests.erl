-module(avm_cbor_coverage_tests).

-include_lib("eunit/include/eunit.hrl").

smoke_test() ->
    ?assertEqual(ok, avm_cbor_smoke:run_coverage()).

partial_test() ->
    ?assertEqual(ok, avm_cbor_partial_tests:run_coverage()).

rfc8949_test() ->
    ?assertEqual(ok, avm_cbor_rfc8949:run_coverage()).

full_decode_edge_paths_test() ->
    ?assertEqual(11, length(avm_cbor:ble_options())),
    ?assertMatch({error, _}, avm_cbor:encode({unsupported})),
    ?assertEqual({error, unexpected_break}, avm_cbor:decode_all(<<16#FF>>)),
    ?assertEqual(
        {error, {max_bytes_exceeded, 1}},
        avm_cbor:decode_sequence(<<1, 2>>, [{max_bytes, 1}])
    ),
    ?assertEqual({error, indefinite_length_unsupported}, avm_cbor:decode(<<16#1F>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#42, 1>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#62, $a>>)),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:decode(<<16#62, $a, $b>>, [{max_string_bytes, 1}])
    ),
    ?assertEqual(
        {error, {invalid_option, {max_string_bytes, 0}}},
        avm_cbor:decode(<<16#41, 1>>, [{max_string_bytes, 0}])
    ),
    ?assertMatch(
        {error, {invalid_option, _}},
        avm_cbor:decode(<<16#81, 1>>, [{max_items, 0}])
    ),
    ?assertMatch(
        {error, {invalid_option, _}},
        avm_cbor:decode(<<16#81, 1>>, [{max_depth, 0}])
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:decode(<<16#5F, 16#FF>>, [{allow_indefinite, false}])
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:decode(<<16#7F, 16#FF>>, [{allow_indefinite, false}])
    ),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#5F>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#7F>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#5F, 16#58>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#7F, 16#78>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#5F, 16#42, 1>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#7F, 16#62, $a>>)),
    ?assertEqual(
        {ok, <<1>>, <<>>},
        avm_cbor:decode(<<16#5F, 16#58, 1, 1, 16#FF>>)
    ),
    ?assertEqual(
        {ok, {text, <<$a>>}, <<>>},
        avm_cbor:decode(<<16#7F, 16#78, 1, $a, 16#FF>>)
    ),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:decode(<<16#5F, 16#42, 1, 2, 16#FF>>, [{max_string_bytes, 1}])
    ),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:decode(<<16#7F, 16#62, $a, $b, 16#FF>>, [{max_string_bytes, 1}])
    ),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:decode(
            <<16#5F, 16#41, 1, 16#41, 2, 16#FF>>, [{max_string_bytes, 1}]
        )
    ),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:decode(
            <<16#7F, 16#61, $a, 16#61, $b, 16#FF>>, [{max_string_bytes, 1}]
        )
    ),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#9F>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#BF>>)),
    ?assertEqual({ok, [], <<16#FF>>}, avm_cbor:decode(<<16#9F, 16#FF, 16#FF>>)),
    ?assertEqual({ok, {map, []}, <<16#FF>>}, avm_cbor:decode(<<16#BF, 16#FF, 16#FF>>)),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:decode(<<16#9F, 16#1C>>)),
    ?assertEqual({error, unexpected_break}, avm_cbor:decode(<<16#BF, 1, 16#FF>>)),
    ?assertEqual({error, truncated}, avm_cbor:decode(<<16#A1, 1>>)),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:decode(<<16#A1, 16#1C>>)),
    ?assertEqual(
        {error, {max_depth_exceeded, 1}},
        avm_cbor:decode(<<16#A1, 1, 16#A1, 2, 3>>, [{max_depth, 1}])
    ),
    ?assertEqual(
        {error, {unsupported_simple_value, 24}},
        avm_cbor:decode(<<16#F8, 24>>, [{allow_simple, false}])
    ),
    ?assertEqual(
        {error, floats_not_allowed},
        avm_cbor:decode(<<16#FA, 16#3F, 16#80, 0, 0>>, [{allow_floats, false}])
    ),
    ?assertEqual(
        {error, floats_not_allowed},
        avm_cbor:decode(
            <<16#FB, 16#3F, 16#F0, 0, 0, 0, 0, 0, 0>>, [{allow_floats, false}]
        )
    ),
    ?assertEqual(
        {error, {max_depth_exceeded, 1}},
        avm_cbor:decode(<<16#9F, 16#9F, 16#FF, 16#FF>>, [{max_depth, 1}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 2}},
        avm_cbor:decode(<<16#9F, 1, 2, 3, 16#FF>>, [{max_items, 2}])
    ),
    ?assertEqual(
        {error, {max_depth_exceeded, 1}},
        avm_cbor:decode(<<16#BF, 1, 16#BF, 16#FF, 16#FF>>, [{max_depth, 1}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 1}},
        avm_cbor:decode(<<16#BF, 1, 2, 3, 4, 16#FF>>, [{max_items, 1}])
    ),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:decode(<<16#BF, 16#1C>>)),
    ?assertEqual(
        {error, simple_values_not_allowed},
        avm_cbor:encode({simple, 24}, [{allow_simple, false}])
    ),
    ok.

partial_measure_edge_paths_test() ->
    ?assertEqual({error, invalid_input}, avm_cbor:partial_decode(not_binary)),
    ?assertEqual(
        {error, {invalid_option, {max_string_bytes, 0}}},
        avm_cbor:partial_decode(<<16#41, 1>>, [{max_string_bytes, 0}])
    ),
    ?assertEqual(
        {error, {invalid_option, {max_string_size, 0}}},
        avm_cbor:partial_decode(<<16#41, 1>>, [{max_string_size, 0}])
    ),
    ?assertEqual(
        {error, {non_preferred_argument, 23}},
        avm_cbor:partial_decode(<<16#18, 23>>, [{preferred, true}])
    ),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#A1, 1>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#5F>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#7F>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#81, 16#20>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#81, 16#5F, 16#40, 16#FF>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#81, 16#7F, 16#60, 16#FF>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#81, 16#9F, 1, 16#FF>>)),
    ?assertMatch({ok, _, <<>>}, avm_cbor:partial_decode(<<16#81, 16#BF, 1, 2, 16#FF>>)),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:partial_decode(
            <<16#81, 16#5F, 16#FF>>, [{allow_indefinite, false}]
        )
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:partial_decode(<<16#7F, 16#FF>>, [{allow_indefinite, false}])
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:partial_decode(
            <<16#81, 16#7F, 16#FF>>, [{allow_indefinite, false}]
        )
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:partial_decode(
            <<16#81, 16#9F, 16#FF>>, [{allow_indefinite, false}]
        )
    ),
    ?assertEqual(
        {error, {max_depth_exceeded, 1}},
        avm_cbor:partial_decode(<<16#81, 16#9F, 16#FF>>, [{max_depth, 1}])
    ),
    ?assertEqual(
        {error, indefinite_length_unsupported},
        avm_cbor:partial_decode(
            <<16#81, 16#BF, 16#FF>>, [{allow_indefinite, false}]
        )
    ),
    ?assertEqual({error, indefinite_length_unsupported}, avm_cbor:partial_decode(<<16#81, 16#1F>>)),
    ?assertEqual(
        {error, {non_preferred_argument, 23}},
        avm_cbor:partial_decode(<<16#81, 16#18, 23>>, [{preferred, true}])
    ),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#18>>)),
    ?assertEqual(
        {error, {invalid_indefinite_chunk, expected_byte_string}},
        avm_cbor:partial_decode(<<16#81, 16#5F, 16#60, 16#FF>>)
    ),
    ?assertEqual(
        {error, {invalid_indefinite_chunk, expected_text_string}},
        avm_cbor:partial_decode(<<16#81, 16#7F, 16#40, 16#FF>>)
    ),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#5F, 16#58>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#7F, 16#78>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#5F, 16#42, 1>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#7F, 16#62, $a>>)),
    ?assertEqual(
        {error, {max_string_bytes_exceeded, 1}},
        avm_cbor:partial_decode(<<16#81, 16#42, 1, 2>>, [{max_string_bytes, 1}])
    ),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#62, $a>>)),
    ?assertEqual({error, invalid_utf8}, avm_cbor:partial_decode(<<16#81, 16#7F, 16#61, 16#FF, 16#FF>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#9F, 1>>)),
    ?assertEqual({error, truncated}, avm_cbor:partial_decode(<<16#81, 16#BF, 1, 2>>)),
    ?assertEqual({error, unexpected_break}, avm_cbor:partial_decode(<<16#81, 16#BF, 1, 16#FF>>)),
    ?assertEqual(
        {error, {unsupported_simple_value, 0}},
        avm_cbor:partial_decode(<<16#81, 16#E0>>, [{allow_simple, false}])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 1}},
        avm_cbor:partial_decode(<<16#81, 16#A2, 1, 2, 3, 4>>, [{max_items, 1}])
    ),
    ?assertEqual(
        {error, {max_depth_exceeded, 1}},
        avm_cbor:partial_decode(<<16#81, 16#A1, 1, 2>>, [{max_depth, 1}])
    ),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:partial_decode(<<16#81, 16#A1, 16#1C>>)),
    ?assertEqual(
        {error, {max_string_size_exceeded, 1}},
        avm_cbor:partial_decode(
            <<16#81, 16#7F, 16#61, $a, 16#61, $b, 16#FF>>, [{max_string_size, 1}]
        )
    ),
    ?assertEqual(
        {error, reserved_additional_info},
        avm_cbor:partial_decode(<<16#81, 16#9F, 16#1C, 16#FF>>)
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 1}},
        avm_cbor:partial_decode(
            <<16#81, 16#BF, 1, 2, 3, 4, 16#FF>>, [{max_items, 1}]
        )
    ),
    ?assertEqual(
        {error, reserved_additional_info},
        avm_cbor:partial_decode(<<16#81, 16#BF, 16#1C, 16#FF>>)
    ),
    ok.

utf8_boundary_paths_test() ->
    Valid = [
        <<16#E0, 16#A0, 16#80>>,
        <<16#E1, 16#80, 16#80>>,
        <<16#ED, 16#80, 16#80>>,
        <<16#EE, 16#80, 16#80>>,
        <<16#F0, 16#90, 16#80, 16#80>>,
        <<16#F1, 16#80, 16#80, 16#80>>,
        <<16#F4, 16#80, 16#80, 16#80>>
    ],
    [?assertMatch({ok, _}, avm_cbor:encode({text, Bin})) || Bin <- Valid],
    Invalid = [
        <<16#E0, 16#9F, 16#80>>,
        <<16#E1, 16#80>>,
        <<16#ED, 16#A0, 16#80>>,
        <<16#EE, 16#80>>,
        <<16#F0, 16#8F, 16#80, 16#80>>,
        <<16#F1, 16#80, 16#80>>,
        <<16#F4, 16#90, 16#80, 16#80>>
    ],
    [?assertEqual({error, invalid_utf8}, avm_cbor:encode({text, Bin})) || Bin <- Invalid],
    ok.

float_edge_paths_test() ->
    ?assertMatch({ok, _}, avm_cbor:encode(5.0e-324, [{preferred, true}])),
    ?assertMatch({ok, _}, avm_cbor:encode(1.0e-10, [{preferred, true}])),
    ok.
