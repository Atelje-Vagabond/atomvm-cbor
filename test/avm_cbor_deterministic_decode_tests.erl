-module(avm_cbor_deterministic_decode_tests).

-include_lib("eunit/include/eunit.hrl").

-define(DETERMINISTIC, [{deterministic, true}]).

indefinite_forms_test() ->
    Cases = [
        <<16#5F, 16#40, 16#FF>>,
        <<16#7F, 16#60, 16#FF>>,
        <<16#9F, 1, 16#FF>>,
        <<16#BF, 1, 0, 16#FF>>,
        <<16#81, 16#9F, 1, 16#FF>>
    ],
    lists:foreach(
        fun(Bin) ->
            ?assertEqual(
                {error, non_deterministic_indefinite},
                avm_cbor:decode(Bin, ?DETERMINISTIC)
            ),
            ?assertEqual(
                {error, non_deterministic_indefinite},
                avm_cbor:partial_decode(Bin, ?DETERMINISTIC)
            )
        end,
        Cases
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:decode(
            <<16#9F, 1, 16#FF>>,
            [{deterministic, true}, {allow_indefinite, true}]
        )
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:decode(
            <<16#9F, 1, 16#FF>>,
            [{allow_indefinite, true}, {deterministic, true}]
        )
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:partial_decode(
            <<16#9F, 1, 16#FF>>,
            [{deterministic, true}, {allow_indefinite, true}]
        )
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:partial_decode(
            <<16#9F, 1, 16#FF>>,
            [{allow_indefinite, true}, {deterministic, true}]
        )
    ),
    ?assertEqual(
        {ok, [1], <<>>},
        avm_cbor:decode(<<16#9F, 1, 16#FF>>, [{preferred, true}])
    ).

deterministic_map_order_test() ->
    SortedIntegers = <<16#A2, 1, 0, 2, 0>>,
    UnsortedIntegers = <<16#A2, 2, 0, 1, 0>>,
    ?assertEqual(
        {ok, {map, [{1, 0}, {2, 0}]}, <<>>},
        avm_cbor:decode(SortedIntegers, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:decode(UnsortedIntegers, ?DETERMINISTIC)
    ),
    %% Original non-deterministic decode behavior remains unchanged.
    ?assertEqual(
        {ok, {map, [{2, 0}, {1, 0}]}, <<>>},
        avm_cbor:decode(UnsortedIntegers)
    ),

    SortedTypes = <<16#A3, 0, 0, 16#40, 1, 16#60, 2>>,
    UnsortedTypes = <<16#A2, 16#60, 0, 16#40, 1>>,
    ?assertMatch({ok, {map, _}, <<>>}, avm_cbor:decode(SortedTypes, ?DETERMINISTIC)),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:decode(UnsortedTypes, ?DETERMINISTIC)
    ),

    %% Encoded-key length is part of ordinary bytewise lexicographic comparison.
    SortedLengths = <<16#A2, 16#61, $b, 0, 16#62, $a, $a, 1>>,
    UnsortedLengths = <<16#A2, 16#62, $a, $a, 0, 16#61, $b, 1>>,
    ?assertMatch({ok, {map, _}, <<>>}, avm_cbor:decode(SortedLengths, ?DETERMINISTIC)),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:decode(UnsortedLengths, ?DETERMINISTIC)
    ),

    NestedSorted = <<16#A1, 1, 16#A2, 1, 0, 2, 0>>,
    NestedUnsorted = <<16#A1, 1, 16#A2, 2, 0, 1, 0>>,
    ?assertMatch({ok, {map, _}, <<>>}, avm_cbor:decode(NestedSorted, ?DETERMINISTIC)),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:decode(NestedUnsorted, ?DETERMINISTIC)
    ),

    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:decode(<<16#A2, 1, 0, 1, 1>>, ?DETERMINISTIC)
    ),
    %% Integer 1 and binary16 1.0 compare as different encoded keys even though
    %% callers may regard the decoded values as numerically equivalent.
    EquivalentLooking = <<16#A2, 1, 0, 16#F9, 16#3C, 0, 1>>,
    ?assertMatch(
        {ok, {map, [{1, 0}, {1.0, 1}]}, <<>>},
        avm_cbor:decode(EquivalentLooking, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, {non_preferred_argument, 23}},
        avm_cbor:decode(<<16#A1, 16#18, 23, 0>>, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:decode(<<16#A1, 16#5F, 16#40, 16#FF, 0>>, ?DETERMINISTIC)
    ).

partial_deterministic_map_order_test() ->
    Sorted = <<16#A2, 1, 0, 2, 0>>,
    Unsorted = <<16#A2, 2, 0, 1, 0>>,
    {ok, Partial, <<>>} = avm_cbor:partial_decode(Sorted, ?DETERMINISTIC),
    ?assertEqual({ok, {map, [{1, 0}, {2, 0}]}}, avm_cbor:partial_deep_decode(Partial)),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:partial_decode(Unsorted, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:partial_decode(<<16#A2, 1, 0, 1, 1>>, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:partial_decode(
            <<16#A1, 1, 16#A2, 2, 0, 1, 0>>, ?DETERMINISTIC
        )
    ),
    ?assertEqual(
        {error, {non_preferred_argument, 23}},
        avm_cbor:partial_decode(<<16#A1, 16#18, 23, 0>>, ?DETERMINISTIC)
    ),
    ?assertEqual(
        {error, non_deterministic_indefinite},
        avm_cbor:partial_decode(
            <<16#A1, 16#5F, 16#40, 16#FF, 0>>, ?DETERMINISTIC
        )
    ).

deterministic_map_malformed_test() ->
    Cases = [
        {<<16#A1, 16#18, 24>>, {error, truncated}},
        {<<16#A1, 1, 16#1C>>, {error, reserved_additional_info}},
        {<<16#A1, 16#1C, 0>>, {error, reserved_additional_info}}
    ],
    lists:foreach(
        fun({Bin, Expected}) ->
            ?assertEqual(Expected, avm_cbor:decode(Bin, ?DETERMINISTIC)),
            ?assertEqual(Expected, avm_cbor:partial_decode(Bin, ?DETERMINISTIC))
        end,
        Cases
    ).

atomvm_safe_key_comparator_boundaries_test() ->
    ?assertEqual(ok, avm_cbor:check_deterministic_map_key(none, <<1>>)),
    ?assertEqual(ok, avm_cbor:check_deterministic_map_key(<<>>, <<1>>)),
    ?assertEqual(ok, avm_cbor:check_deterministic_map_key(<<1>>, <<1, 0>>)),
    ?assertEqual(ok, avm_cbor:check_deterministic_map_key(<<1>>, <<2>>)),
    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:check_deterministic_map_key(<<1>>, <<1>>)
    ),
    ?assertEqual(
        {error, duplicate_map_key},
        avm_cbor:check_deterministic_map_key(<<>>, <<>>)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:check_deterministic_map_key(<<2>>, <<1>>)
    ),
    ?assertEqual(
        {error, non_deterministic_map_order},
        avm_cbor:check_deterministic_map_key(<<1, 0>>, <<1>>)
    ).
