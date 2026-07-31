-module(avm_cbor_internal_branch_tests).

-ifdef(TEST).
-define(INTERNAL_COVERAGE_TESTS, true).
-endif.

-ifdef(BRANCH_COVERAGE).
-ifndef(INTERNAL_COVERAGE_TESTS).
-define(INTERNAL_COVERAGE_TESTS, true).
-endif.
-endif.

-ifdef(INTERNAL_COVERAGE_TESTS).

-include_lib("eunit/include/eunit.hrl").
-include("../src/avm_cbor_opts.hrl").

internal_contract_boundaries_test() ->
    {ok, Opts} = avm_cbor:normalize_partial_opts([]),
    State = avm_cbor:new_decode_state(Opts),
    ?assertEqual(ok, avm_cbor:check_string_byte_limit(1,
        Opts#cbor_opts{max_string_bytes = 0})),
    ?assertError(function_clause, avm_cbor:consume_nodes(-1, State)),
    ?assertError(function_clause, avm_cbor:ensure_node_budget(-1, State)),
    ?assertError(function_clause, avm_cbor:consume_string_bytes(-1, State)),
    ?assertEqual(
        {error, {max_items_exceeded, 64}},
        avm_cbor_partial:parse_item(<<1>>, setelement(3, State, 0))
    ),
    ?assertEqual({error, truncated}, avm_cbor_partial:parse_item(<<>>, State)),
    ?assertEqual(false, avm_cbor_partial:valid_partial(not_a_partial)),
    DepthState = avm_cbor:new_decode_state(Opts#cbor_opts{max_depth = 0}),
    ?assertEqual(
        {error, {max_depth_exceeded, 0}},
        avm_cbor_partial:parse_indefinite(5, <<16#FF>>, DepthState)
    ),
    ?assertError(function_clause, avm_cbor:array(-1, <<>>, State, 0)),
    ?assertError(function_clause, avm_cbor:map(-1, <<>>, State, 0)),
    ?assertMatch(
        {ok, [seed, 1], <<>>, #cbor_decode_state{nodes_left = 63}},
        avm_cbor:items_general(1, <<1>>, State, 0, [seed])
    ),
    ?assertMatch(
        {ok, {map, [{seed, seed}, {1, 2}]}, <<>>,
         #cbor_decode_state{nodes_left = 62}},
        avm_cbor:pairs_general(1, <<1, 2>>, State, 0, [{seed, seed}])
    ),
    EmptyState = setelement(3, State, 0),
    ?assertEqual(
        {error, {max_items_exceeded, 64}},
        avm_cbor:items(64, binary:copy(<<0>>, 64), EmptyState, 0, [])
    ),
    ?assertEqual(
        {error, {max_items_exceeded, 64}},
        avm_cbor:pairs(32, binary:copy(<<0, 0>>, 32), EmptyState, 0, [])
    ),
    ?assertError(function_clause, avm_cbor_partial:measure_array(-1, <<>>, State, 0)),
    ?assertError(function_clause, avm_cbor_partial:measure_map(-1, <<>>, State, 0)),
    ?assertEqual({error, reserved_additional_info}, avm_cbor:arg(31, <<>>)),
    ?assertEqual(
        {error, {unsupported_simple_value, 28}},
        avm_cbor:simple(28, 0, <<>>, Opts)
    ),
    ?assertEqual({error, truncated}, avm_cbor:definite_bstr_chunk_header(<<>>)),
    ?assertEqual({error, truncated}, avm_cbor:definite_tstr_chunk_header(<<>>)),
    ?assertEqual(undefined, avm_cbor:float_to_half_finite(0, -20, 1)),
    ?assertEqual(16#7C00, avm_cbor:float_bits_to_half_bits(16#7FF0000000000000)),
    ?assertEqual(16#FC00, avm_cbor:float_bits_to_half_bits(16#FFF0000000000000)),
    ?assertEqual(16#7E00, avm_cbor:float_bits_to_half_bits(16#7FF8000000000001)),
    ?assertEqual(
        {error, {unsupported_major_type, 8}},
        avm_cbor_partial:parse_definite(8, 0, 0, 1, <<>>, State)
    ),
    ?assertEqual(
        {error, {unsupported_major_type, 8}},
        avm_cbor_partial:measure_value(8, 0, 0, <<>>, State, 0)
    ).

-endif.
