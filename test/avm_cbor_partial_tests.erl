-module(avm_cbor_partial_tests).
-export([run/0, run_coverage/0]).

run() ->
    run_coverage(),
    halt(0).

run_coverage() ->
    io:format("~n=== avm_cbor partial decode tests ===~n~n", []),
    tests([
        {partial_unsigned, fun test_partial_unsigned/0},
        {partial_negative, fun test_partial_negative/0},
        {partial_simple_values, fun test_partial_simple_values/0},
        {partial_floats, fun test_partial_floats/0},
        {partial_byte_strings, fun test_partial_byte_strings/0},
        {partial_text_strings, fun test_partial_text_strings/0},
        {partial_arrays, fun test_partial_arrays/0},
        {partial_maps, fun test_partial_maps/0},
        {partial_tags, fun test_partial_tags/0},
        {partial_nested, fun test_partial_nested/0},
        {partial_deep_decode_nested, fun test_partial_deep_decode_nested/0},
        {partial_skip_known_struct, fun test_partial_skip_known_struct/0},
        {partial_roundtrip_bytes, fun test_partial_roundtrip_bytes/0},
        {partial_indefinite, fun test_partial_indefinite/0},
        {partial_deterministic_decode, fun test_partial_deterministic_decode/0},
        {partial_rest_bytes, fun test_partial_rest_bytes/0},
        {partial_matches_full_decode, fun test_partial_matches_full_decode/0},
        {partial_map_fold, fun test_partial_map_fold/0},
        {partial_array_fold, fun test_partial_array_fold/0},
        {partial_select_and_find, fun test_partial_select_and_find/0},
        {partial_array_nth, fun test_partial_array_nth/0},
        {partial_error_empty, fun test_partial_error_empty/0},
        {partial_error_truncated, fun test_partial_error_truncated/0},
        {partial_error_depth, fun test_partial_error_depth/0},
        {partial_error_items, fun test_partial_error_items/0},
        {partial_global_budgets, fun test_partial_global_budgets/0},
        {partial_error_string_size, fun test_partial_error_string_size/0},
        {partial_error_options, fun test_partial_error_options/0},
        {partial_error_malformed, fun test_partial_error_malformed/0},
        {partial_accessor_errors, fun test_partial_accessor_errors/0}
    ]),
    io:format("~n=== all partial decode tests passed ===~n"),
    ok.

tests([{Name, F} | Rest]) ->
    io:format("  ~s ... ", [Name]),
    try F() of
        ok -> io:format("ok~n")
    catch
        error:{assert_failed, Exp, Got} ->
            io:format("FAIL~n  expected: ~p~n  got:      ~p~n", [Exp, Got]),
            halt(1);
        Class:Reason:Stack ->
            io:format("CRASH: ~p:~p~n  stack: ~p~n", [Class, Reason, Stack]),
            halt(1)
    end,
    tests(Rest);
tests([]) -> ok.

assert(Expected, Got) when Expected =:= Got -> ok;
assert(Expected, Got) -> erlang:error({assert_failed, Expected, Got}).

partial_ok(Bin) ->
    case avm_cbor:partial_decode(Bin) of
        {ok, Partial, <<>>} -> Partial;
        {ok, _, Rest} -> erlang:error({unexpected_rest, Rest});
        {error, Reason} -> erlang:error({partial_decode_error, Reason})
    end.

partial_ok_with_opts(Bin, Opts) ->
    case avm_cbor:partial_decode(Bin, Opts) of
        {ok, Partial, <<>>} -> Partial;
        {ok, _, Rest} -> erlang:error({unexpected_rest, Rest});
        {error, Reason} -> erlang:error({partial_decode_error, Reason})
    end.

partial_error(Bin) ->
    case avm_cbor:partial_decode(Bin) of
        {error, Reason} -> Reason;
        Other -> erlang:error({expected_error, got, Other})
    end.

partial_error_with_opts(Bin, Opts) ->
    case avm_cbor:partial_decode(Bin, Opts) of
        {error, Reason} -> Reason;
        Other -> erlang:error({expected_error, got, Other})
    end.

deep_ok(Partial) ->
    case avm_cbor:partial_deep_decode(Partial) of
        {ok, Val} -> Val;
        {error, Reason} -> erlang:error({deep_decode_error, Reason})
    end.

encode_ok(Val) ->
    case avm_cbor:encode(Val) of
        {ok, Bin} -> Bin;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

%%--------------------------------------------------------------------
%% Scalar types
%%--------------------------------------------------------------------

test_partial_unsigned() ->
    P0 = partial_ok(<<16#00>>),
    assert(unsigned, avm_cbor:partial_type(P0)),
    assert(0, deep_ok(P0)),
    assert(0, avm_cbor:partial_offset(P0)),
    assert(1, avm_cbor:partial_length(P0)),
    assert(undefined, avm_cbor:partial_count(P0)),
    assert(undefined, avm_cbor:partial_tag(P0)),
    assert(undefined, avm_cbor:partial_size(P0)),
    P1 = partial_ok(<<16#18, 16#64>>),
    assert(unsigned, avm_cbor:partial_type(P1)),
    assert(100, deep_ok(P1)),
    assert(2, avm_cbor:partial_length(P1)),
    P2 = partial_ok(<<16#1B, 16#00, 16#00, 16#00, 16#01, 16#00, 16#00, 16#00, 16#00>>),
    assert(4294967296, deep_ok(P2)),
    assert(9, avm_cbor:partial_length(P2)),
    ok.

test_partial_negative() ->
    P0 = partial_ok(<<16#20>>),
    assert(negative, avm_cbor:partial_type(P0)),
    assert(-1, deep_ok(P0)),
    P1 = partial_ok(<<16#38, 16#63>>),
    assert(negative, avm_cbor:partial_type(P1)),
    assert(-100, deep_ok(P1)),
    ok.

test_partial_simple_values() ->
    assert(simple, avm_cbor:partial_type(partial_ok(<<16#F5>>))),
    assert(true, deep_ok(partial_ok(<<16#F5>>))),
    assert(false, deep_ok(partial_ok(<<16#F4>>))),
    assert(null, deep_ok(partial_ok(<<16#F6>>))),
    assert(undefined, deep_ok(partial_ok(<<16#F7>>))),
    P = partial_ok(<<16#F8, 16#20>>),
    assert(simple, avm_cbor:partial_type(P)),
    assert({simple, 32}, deep_ok(P)),
    ok.

test_partial_floats() ->
    PH = partial_ok(<<16#F9, 16#3E, 16#00>>),
    assert(float, avm_cbor:partial_type(PH)),
    assert(1.5, deep_ok(PH)),
    assert(3, avm_cbor:partial_length(PH)),
    PS = partial_ok(<<16#FA, 16#3F, 16#C0, 16#00, 16#00>>),
    assert(float, avm_cbor:partial_type(PS)),
    assert(1.5, deep_ok(PS)),
    PD = partial_ok(<<16#FB, 16#3F, 16#F8, 0, 0, 0, 0, 0, 0>>),
    assert(float, avm_cbor:partial_type(PD)),
    assert(1.5, deep_ok(PD)),
    %% Infinity/NaN rejected, floats disallowed by option
    assert({unsupported_simple_value, invalid_float}, partial_error(<<16#F9, 16#7C, 16#00>>)),
    assert(floats_not_allowed,
           partial_error_with_opts(<<16#F9, 16#3E, 16#00>>, [{allow_floats, false}])),
    ok.

%%--------------------------------------------------------------------
%% Strings
%%--------------------------------------------------------------------

test_partial_byte_strings() ->
    P0 = partial_ok(<<16#40>>),
    assert(bytes, avm_cbor:partial_type(P0)),
    assert(0, avm_cbor:partial_size(P0)),
    assert(<<>>, deep_ok(P0)),
    P1 = partial_ok(<<16#44, 1, 2, 3, 4>>),
    assert(bytes, avm_cbor:partial_type(P1)),
    assert(4, avm_cbor:partial_size(P1)),
    assert(5, avm_cbor:partial_length(P1)),
    assert(<<1, 2, 3, 4>>, deep_ok(P1)),
    assert(<<16#44, 1, 2, 3, 4>>, avm_cbor:partial_value_bytes(P1)),
    ok.

test_partial_text_strings() ->
    P0 = partial_ok(<<16#63, "abc">>),
    assert(text, avm_cbor:partial_type(P0)),
    assert(3, avm_cbor:partial_size(P0)),
    assert(4, avm_cbor:partial_length(P0)),
    assert({text, <<"abc">>}, deep_ok(P0)),
    %% invalid UTF-8 is rejected at partial-decode time
    assert(invalid_utf8, partial_error(<<16#61, 16#FF>>)),
    assert(invalid_utf8, partial_error(<<16#63, 16#ED, 16#A0, 16#80>>)),
    ok.

%%--------------------------------------------------------------------
%% Containers and tags
%%--------------------------------------------------------------------

test_partial_arrays() ->
    P0 = partial_ok(<<16#80>>),
    assert(array, avm_cbor:partial_type(P0)),
    assert(0, avm_cbor:partial_count(P0)),
    assert([], deep_ok(P0)),
    P1 = partial_ok(<<16#83, 1, 2, 3>>),
    assert(array, avm_cbor:partial_type(P1)),
    assert(3, avm_cbor:partial_count(P1)),
    assert(4, avm_cbor:partial_length(P1)),
    assert([1, 2, 3], deep_ok(P1)),
    {ok, Contents} = avm_cbor:partial_contents(P1),
    assert(<<1, 2, 3>>, Contents),
    %% walk elements one by one
    {ok, E1, R1} = avm_cbor:partial_decode(Contents),
    assert(1, deep_ok(E1)),
    {ok, E2, R2} = avm_cbor:partial_decode(R1),
    assert(2, deep_ok(E2)),
    {ok, E3, <<>>} = avm_cbor:partial_decode(R2),
    assert(3, deep_ok(E3)),
    ok.

test_partial_maps() ->
    P0 = partial_ok(<<16#A0>>),
    assert(map, avm_cbor:partial_type(P0)),
    assert(0, avm_cbor:partial_count(P0)),
    assert({map, []}, deep_ok(P0)),
    P1 = partial_ok(<<16#A2, 1, 2, 3, 4>>),
    assert(map, avm_cbor:partial_type(P1)),
    assert(2, avm_cbor:partial_count(P1)),
    assert({map, [{1, 2}, {3, 4}]}, deep_ok(P1)),
    {ok, Contents} = avm_cbor:partial_contents(P1),
    {ok, K1, R1} = avm_cbor:partial_decode(Contents),
    assert(1, deep_ok(K1)),
    {ok, V1, R2} = avm_cbor:partial_decode(R1),
    assert(2, deep_ok(V1)),
    {ok, K2, R3} = avm_cbor:partial_decode(R2),
    assert(3, deep_ok(K2)),
    {ok, V2, <<>>} = avm_cbor:partial_decode(R3),
    assert(4, deep_ok(V2)),
    ok.

test_partial_tags() ->
    P0 = partial_ok(<<16#C1, 16#1A, 16#51, 16#4B, 16#67, 16#B0>>),
    assert(tag, avm_cbor:partial_type(P0)),
    assert(1, avm_cbor:partial_tag(P0)),
    assert(6, avm_cbor:partial_length(P0)),
    assert({tag, 1, 1363896240}, deep_ok(P0)),
    %% payload can be reached through partial_contents
    {ok, Payload} = avm_cbor:partial_contents(P0),
    {ok, Inner, <<>>} = avm_cbor:partial_decode(Payload),
    assert(unsigned, avm_cbor:partial_type(Inner)),
    assert(1363896240, deep_ok(Inner)),
    %% multi-byte tag numbers
    P1 = partial_ok(<<16#D8, 16#20, 16#61, 16#61>>),
    assert(32, avm_cbor:partial_tag(P1)),
    %% tags disallowed by option
    assert({unsupported_tag, 1},
           partial_error_with_opts(<<16#C1, 16#01>>, [{allow_tags, false}])),
    ok.

%%--------------------------------------------------------------------
%% Nesting
%%--------------------------------------------------------------------

test_partial_nested() ->
    %% {map, [{1, [1, {map, [{2, <<"x">>}]}]}]} -- three levels deep
    Term = {map, [{1, [1, {map, [{2, {text, <<"x">>}}]}]}]},
    Bin = encode_ok(Term),
    P = partial_ok(Bin),
    assert(map, avm_cbor:partial_type(P)),
    assert(1, avm_cbor:partial_count(P)),
    assert(byte_size(Bin), avm_cbor:partial_length(P)),
    assert(Bin, avm_cbor:partial_value_bytes(P)),
    assert(Term, deep_ok(P)),
    ok.

test_partial_deep_decode_nested() ->
    %% walk to a nested value, then deep-decode only that branch
    Inner = {map, [{{text, <<"k">>}, [10, 20, 30]}]},
    Bin = encode_ok([1, Inner, 2]),
    P = partial_ok(Bin),
    assert(3, avm_cbor:partial_count(P)),
    {ok, C} = avm_cbor:partial_contents(P),
    {ok, _First, R1} = avm_cbor:partial_decode(C),
    {ok, Mid, R2} = avm_cbor:partial_decode(R1),
    assert(map, avm_cbor:partial_type(Mid)),
    assert(Inner, deep_ok(Mid)),
    {ok, Last, <<>>} = avm_cbor:partial_decode(R2),
    assert(2, deep_ok(Last)),
    ok.

test_partial_skip_known_struct() ->
    %% map with 3 known keys; skip the large value at key 2 in O(1)
    Big = big_binary(100),
    Bin = encode_ok({map, [{1, {text, <<"abc">>}}, {2, Big}, {3, 42}]}),
    P = partial_ok(Bin),
    assert(map, avm_cbor:partial_type(P)),
    assert(3, avm_cbor:partial_count(P)),
    {ok, C} = avm_cbor:partial_contents(P),
    {ok, K1, R1} = avm_cbor:partial_decode(C),
    assert(1, deep_ok(K1)),
    {ok, V1, R2} = avm_cbor:partial_decode(R1),
    assert({text, <<"abc">>}, deep_ok(V1)),
    {ok, K2, R3} = avm_cbor:partial_decode(R2),
    assert(2, deep_ok(K2)),
    %% the large value is measured but never decoded
    {ok, V2, R4} = avm_cbor:partial_decode(R3),
    assert(bytes, avm_cbor:partial_type(V2)),
    assert(100, avm_cbor:partial_size(V2)),
    assert(ok, avm_cbor:partial_skip(V2)),
    {ok, K3, R5} = avm_cbor:partial_decode(R4),
    assert(3, deep_ok(K3)),
    {ok, V3, <<>>} = avm_cbor:partial_decode(R5),
    assert(42, deep_ok(V3)),
    ok.

test_partial_roundtrip_bytes() ->
    %% extract a nested value's raw bytes, then run the normal decoder
    Inner = {map, [{1, [true, null]}]},
    Bin = encode_ok([Inner]),
    P = partial_ok(Bin),
    {ok, C} = avm_cbor:partial_contents(P),
    {ok, InnerP, <<>>} = avm_cbor:partial_decode(C),
    Raw = avm_cbor:partial_value_bytes(InnerP),
    assert({ok, Inner, <<>>}, avm_cbor:decode(Raw)),
    assert(Inner, deep_ok(InnerP)),
    ok.

%%--------------------------------------------------------------------
%% Indefinite-length items
%%--------------------------------------------------------------------

test_partial_indefinite() ->
    %% byte string
    PB = partial_ok(<<16#5F, 16#41, 1, 16#41, 2, 16#FF>>),
    assert(bytes, avm_cbor:partial_type(PB)),
    assert(2, avm_cbor:partial_size(PB)),
    assert(6, avm_cbor:partial_length(PB)),
    assert(<<1, 2>>, deep_ok(PB)),
    %% text string
    PT = partial_ok(<<16#7F, 16#61, $a, 16#61, $b, 16#FF>>),
    assert(text, avm_cbor:partial_type(PT)),
    assert(2, avm_cbor:partial_size(PT)),
    assert({text, <<"ab">>}, deep_ok(PT)),
    %% array
    PA = partial_ok(<<16#9F, 1, 2, 3, 16#FF>>),
    assert(array, avm_cbor:partial_type(PA)),
    assert(3, avm_cbor:partial_count(PA)),
    assert([1, 2, 3], deep_ok(PA)),
    {ok, CA} = avm_cbor:partial_contents(PA),
    assert(<<1, 2, 3>>, CA),
    %% map
    PM = partial_ok(<<16#BF, 1, 2, 16#FF>>),
    assert(map, avm_cbor:partial_type(PM)),
    assert(1, avm_cbor:partial_count(PM)),
    assert({map, [{1, 2}]}, deep_ok(PM)),
    %% empty indefinite containers
    assert(0, avm_cbor:partial_count(partial_ok(<<16#9F, 16#FF>>))),
    assert(0, avm_cbor:partial_count(partial_ok(<<16#BF, 16#FF>>))),
    %% disallowed by option
    assert(indefinite_length_unsupported,
           partial_error_with_opts(<<16#9F, 1, 16#FF>>, [{allow_indefinite, false}])),
    assert(indefinite_length_unsupported,
           partial_error_with_opts(<<16#5F, 16#41, 1, 16#FF>>, [{allow_indefinite, false}])),
    %% invalid chunk type inside indefinite string
    assert({invalid_indefinite_chunk, expected_byte_string},
           partial_error(<<16#5F, 16#61, $a, 16#FF>>)),
    %% Empty byte/text chunks consume the same bounded work budget.
    assert({max_items_exceeded, 2},
           partial_error_with_opts(
               <<16#5F, 16#40, 16#40, 16#40, 16#FF>>, [{max_items, 2}])),
    assert({max_items_exceeded, 2},
           partial_error_with_opts(
               <<16#7F, 16#60, 16#60, 16#60, 16#FF>>, [{max_items, 2}])),
    ok.

test_partial_deterministic_decode() ->
    Deterministic = [{deterministic, true}],
    Sorted = <<16#A2, 1, 0, 2, 0>>,
    P = partial_ok_with_opts(Sorted, Deterministic),
    assert({map, [{1, 0}, {2, 0}]}, deep_ok(P)),
    assert(
        non_deterministic_map_order,
        partial_error_with_opts(<<16#A2, 2, 0, 1, 0>>, Deterministic)
    ),
    assert(
        duplicate_map_key,
        partial_error_with_opts(<<16#A2, 1, 0, 1, 1>>, Deterministic)
    ),
    assert(
        non_deterministic_indefinite,
        partial_error_with_opts(<<16#9F, 1, 16#FF>>, Deterministic)
    ),
    assert(
        non_deterministic_map_order,
        partial_error_with_opts(
            <<16#A1, 1, 16#A2, 2, 0, 1, 0>>, Deterministic
        )
    ),
    ok.

%%--------------------------------------------------------------------
%% Rest bytes and parity with full decode
%%--------------------------------------------------------------------

test_partial_rest_bytes() ->
    {ok, P, Rest} = avm_cbor:partial_decode(<<16#83, 1, 2, 3, 16#0A, 16#0B>>),
    assert(array, avm_cbor:partial_type(P)),
    assert(4, avm_cbor:partial_length(P)),
    assert(<<16#0A, 16#0B>>, Rest),
    ok.

test_partial_matches_full_decode() ->
    Payloads = [
        <<16#00>>,
        <<16#18, 16#64>>,
        <<16#20>>,
        <<16#44, 1, 2, 3, 4>>,
        <<16#63, "abc">>,
        <<16#83, 1, 2, 3>>,
        <<16#A2, 1, 2, 3, 4>>,
        <<16#C1, 16#01>>,
        <<16#F5>>,
        <<16#F6>>,
        <<16#F9, 16#3E, 16#00>>,
        <<16#9F, 1, 2, 16#FF>>,
        <<16#BF, 1, 2, 16#FF>>,
        <<16#5F, 16#41, 1, 16#FF>>
    ],
    check_parity(Payloads).

check_parity([]) -> ok;
check_parity([Bin | Rest]) ->
    {ok, Term, <<>>} = avm_cbor:decode(Bin),
    P = partial_ok(Bin),
    assert(Term, deep_ok(P)),
    assert(byte_size(Bin), avm_cbor:partial_length(P)),
    check_parity(Rest).

%%--------------------------------------------------------------------
%% Error cases
%%--------------------------------------------------------------------

test_partial_error_empty() ->
    assert(empty, partial_error(<<>>)),
    ok.

%%--------------------------------------------------------------------
%% Single-pass container traversal and lookup
%%--------------------------------------------------------------------

test_partial_map_fold() ->
    %% {"a": 1, "b": [2, 3], "c": 4}
    Partial = partial_ok(<<16#A3, 16#61, "a", 1,
                           16#61, "b", 16#82, 2, 3,
                           16#61, "c", 4>>),
    Fold = fun(KeyPartial, ValuePartial, Acc) ->
        {ok, Key} = avm_cbor:partial_deep_decode(KeyPartial),
        {cont, [{Key,
                 avm_cbor:partial_type(ValuePartial),
                 avm_cbor:partial_offset(KeyPartial),
                 avm_cbor:partial_offset(ValuePartial)} | Acc]}
    end,
    assert(
        {ok, [{{text, <<"c">>}, unsigned, 9, 11},
              {{text, <<"b">>}, array, 4, 6},
              {{text, <<"a">>}, unsigned, 1, 3}]},
        avm_cbor:partial_map_fold(Partial, Fold, [])
    ),
    %% The second pass stops after the first pair and does not deep-decode the
    %% later nested value.  The original descriptor already validated it.
    Halt = fun(_KeyPartial, ValuePartial, Count) ->
        {halt, {Count + 1, avm_cbor:partial_type(ValuePartial)}}
    end,
    assert({ok, {1, unsigned}}, avm_cbor:partial_map_fold(Partial, Halt, 0)),
    assert({error, {expected_partial_type, map}},
           avm_cbor:partial_map_fold(partial_ok(<<16#81, 1>>), Fold, [])),
    assert({error, invalid_callback},
           avm_cbor:partial_map_fold(Partial, not_a_function, [])),
    BadResult = fun(_K, _V, _Acc) -> invalid end,
    assert({error, invalid_fold_result},
           avm_cbor:partial_map_fold(Partial, BadResult, [])),
    %% Indefinite containers retain absolute child offsets and use their
    %% measured pair count; the break byte is never exposed as an item.
    Indef = partial_ok_with_opts(
        <<16#BF, 1, 2, 3, 4, 16#FF>>,
        [{allow_indefinite, true}]
    ),
    OffsetFold = fun(K, V, Acc) ->
        {cont, [{avm_cbor:partial_offset(K), avm_cbor:partial_offset(V)} | Acc]}
    end,
    assert({ok, [{3, 4}, {1, 2}]},
           avm_cbor:partial_map_fold(Indef, OffsetFold, [])),
    ok.

test_partial_array_fold() ->
    Partial = partial_ok(<<16#83, 1, 16#82, 2, 3, 4>>),
    Fold = fun(ElementPartial, Acc) ->
        {cont, [{avm_cbor:partial_type(ElementPartial),
                 avm_cbor:partial_offset(ElementPartial)} | Acc]}
    end,
    assert({ok, [{unsigned, 5}, {array, 2}, {unsigned, 1}]},
           avm_cbor:partial_array_fold(Partial, Fold, [])),
    Halt = fun(ElementPartial, Count) ->
        case avm_cbor:partial_type(ElementPartial) of
            array -> {halt, {Count + 1, array}};
            _ -> {cont, Count + 1}
        end
    end,
    assert({ok, {2, array}}, avm_cbor:partial_array_fold(Partial, Halt, 0)),
    assert({error, {expected_partial_type, array}},
           avm_cbor:partial_array_fold(partial_ok(<<16#A0>>), Fold, [])),
    assert({error, invalid_callback},
           avm_cbor:partial_array_fold(Partial, fun(_A, _B, _C) -> ok end, [])),
    BadResult = fun(_Element, _Acc) -> invalid end,
    assert({error, invalid_fold_result},
           avm_cbor:partial_array_fold(Partial, BadResult, [])),
    ok.

test_partial_select_and_find() ->
    %% Duplicate encoded keys are allowed outside deterministic mode.  Both
    %% select and find intentionally return the first matching occurrence.
    Partial = partial_ok(<<16#A3,
                           16#61, "a", 1,
                           16#61, "a", 2,
                           16#61, "b", 16#81, 3>>),
    %% Request order deliberately differs from map order.  Found stays in map
    %% encounter order while unmatched requests retain their original order.
    {ok, Found, Missing} =
        avm_cbor:partial_select(Partial, [{text, <<"b">>}, {text, <<"a">>}, 9]),
    assert([9], Missing),
    [{_, AValue}, {_, BValue}] = Found,
    assert(1, deep_ok(AValue)),
    assert(array, avm_cbor:partial_type(BValue)),
    assert({ok, [], []}, avm_cbor:partial_select(Partial, [])),
    assert({error, duplicate_requested_key},
           avm_cbor:partial_select(Partial, [{text, <<"a">>}, {text, <<"a">>}])),
    assert({error, invalid_key_list}, avm_cbor:partial_select(Partial, not_a_list)),
    assert({error, {expected_partial_type, map}},
           avm_cbor:partial_select(partial_ok(<<16#80>>), [])),
    {ok, FirstA} = avm_cbor:partial_map_find(Partial, {text, <<"a">>}),
    assert(1, deep_ok(FirstA)),
    assert({error, not_found}, avm_cbor:partial_map_find(Partial, {text, <<"z">>})),
    ok.

test_partial_array_nth() ->
    Partial = partial_ok(<<16#83, 1, 16#82, 2, 3, 4>>),
    {ok, First} = avm_cbor:partial_array_nth(Partial, 0),
    assert(1, deep_ok(First)),
    {ok, Nested} = avm_cbor:partial_array_nth(Partial, 1),
    assert(array, avm_cbor:partial_type(Nested)),
    assert({error, {index_out_of_range, 3}}, avm_cbor:partial_array_nth(Partial, 3)),
    assert({error, invalid_index}, avm_cbor:partial_array_nth(Partial, -1)),
    assert({error, {expected_partial_type, array}},
           avm_cbor:partial_array_nth(partial_ok(<<16#A0>>), 0)),
    ok.

test_partial_error_truncated() ->
    assert(truncated, partial_error(<<16#82, 16#01>>)),
    assert(truncated, partial_error(<<16#A1, 16#01>>)),
    assert(truncated, partial_error(<<16#44, 1, 2>>)),
    assert(truncated, partial_error(<<16#19, 16#03>>)),
    assert(truncated, partial_error(<<16#9F, 16#01>>)),
    assert(truncated, partial_error(<<16#BF, 16#01, 16#02>>)),
    assert(truncated, partial_error(<<16#5F, 16#41, 1>>)),
    assert(truncated, partial_error(<<16#C1>>)),
    ok.

test_partial_error_depth() ->
    %% [[[[1]]]] is four levels deep
    Deep = <<16#81, 16#81, 16#81, 16#81, 16#01>>,
    assert({max_depth_exceeded, 3}, partial_error_with_opts(Deep, [{max_depth, 3}])),
    %% same limit passes at allowed depth
    P = partial_ok_with_opts(<<16#81, 16#81, 16#01>>, [{max_depth, 3}]),
    assert(array, avm_cbor:partial_type(P)),
    %% tag nesting also counts against depth
    assert({max_depth_exceeded, 1},
           partial_error_with_opts(<<16#C1, 16#C1, 16#01>>, [{max_depth, 1}])),
    ok.

test_partial_error_items() ->
    %% the partial default max_items is 64, stricter than full decode
    Bin65 = encode_ok(make_seq(65)),
    assert({max_items_exceeded, 64}, partial_error(Bin65)),
    {ok, _, _} = avm_cbor:decode(Bin65),
    %% explicit option
    assert({max_items_exceeded, 2},
           partial_error_with_opts(<<16#83, 1, 2, 3>>, [{max_items, 2}])),
    %% indefinite containers count items too
    assert({max_items_exceeded, 2},
           partial_error_with_opts(<<16#9F, 1, 2, 3, 16#FF>>, [{max_items, 2}])),
    ok.

test_partial_global_budgets() ->
    Nested = <<16#82, 16#82, 1, 2, 16#82, 3, 4>>,
    assert(
        {max_items_exceeded, 6},
        partial_error_with_opts(Nested, [{max_items, 6}])
    ),
    P = partial_ok_with_opts(Nested, [{max_items, 7}]),
    assert([[1, 2], [3, 4]], deep_ok(P)),
    Strings = <<16#83, 16#41, $a, 16#41, $b, 16#41, $c>>,
    assert(
        {max_total_string_bytes_exceeded, 2},
        partial_error_with_opts(
            Strings,
            [{max_items, 4}, {max_string_bytes, 1}, {max_total_string_bytes, 2}]
        )
    ),
    P2 = partial_ok_with_opts(
        Strings,
        [{max_items, 4}, {max_string_bytes, 1}, {max_total_string_bytes, 3}]
    ),
    assert([<<"a">>, <<"b">>, <<"c">>], deep_ok(P2)),
    %% Chunk nodes and chunk bytes consume the same operation-wide state.
    assert(
        {max_total_string_bytes_exceeded, 2},
        partial_error_with_opts(
            <<16#5F, 16#41, 1, 16#41, 2, 16#41, 3, 16#FF>>,
            [{max_items, 4}, {max_total_string_bytes, 2}]
        )
    ),
    ok.

test_partial_error_string_size() ->
    %% the partial default max_string_size is 8192
    BigBin = encode_ok(big_binary(8193)),
    assert({max_string_size_exceeded, 8192}, partial_error(BigBin)),
    {ok, _, _} = avm_cbor:decode(BigBin),
    %% explicit option, definite and indefinite
    assert({max_string_size_exceeded, 2},
           partial_error_with_opts(<<16#44, 1, 2, 3, 4>>, [{max_string_size, 2}])),
    assert({max_string_size_exceeded, 2},
           partial_error_with_opts(<<16#5F, 16#41, 1, 16#42, 2, 3, 16#FF>>,
                                   [{max_string_size, 2}])),
    %% shared max_string_bytes option still applies
    assert({max_string_bytes_exceeded, 2},
           partial_error_with_opts(<<16#44, 1, 2, 3, 4>>, [{max_string_bytes, 2}])),
    ok.

test_partial_error_options() ->
    assert(invalid_options_list, element(2, avm_cbor:partial_decode(<<16#00>>, not_a_list))),
    assert({invalid_option, {bogus, 1}},
           partial_error_with_opts(<<16#00>>, [{bogus, 1}])),
    assert({invalid_option, {max_string_size, -1}},
           begin
               {error, R} = avm_cbor:partial_decode(<<16#00>>, [{max_string_size, -1}]),
               R
           end),
    assert({invalid_option, {max_bytes, 0}},
           begin
               {error, R2} = avm_cbor:partial_decode(<<16#00>>, [{max_bytes, 0}]),
               R2
           end),
    assert({invalid_option, {max_string_bytes, 0}},
           element(2, avm_cbor:partial_decode(<<16#40>>, [{max_string_bytes, 0}]))),
    assert({invalid_option, {max_total_string_bytes, 0}},
           element(2,
               avm_cbor:partial_decode(<<16#40>>, [{max_total_string_bytes, 0}]))),
    assert({invalid_option, {max_string_size, 0}},
           element(2, avm_cbor:partial_decode(<<16#40>>, [{max_string_size, 0}]))),
    assert(invalid_input, element(2, avm_cbor:partial_decode(not_a_binary, []))),
    %% The trusted partial default and normalized empty option list agree.
    Sample = <<16#82, 1, 16#A1, 2, 3>>,
    assert(avm_cbor:partial_decode(Sample), avm_cbor:partial_decode(Sample, [])),
    %% Preserve last-duplicate-wins behavior for shared and partial options.
    {ok, _, <<>>} =
        avm_cbor:partial_decode(<<16#82, 1, 2>>, [{max_items, 1}, {max_items, 3}]),
    assert({max_items_exceeded, 1},
           partial_error_with_opts(<<16#82, 1, 2>>, [{max_items, 3}, {max_items, 1}])),
    {ok, _, <<>>} = avm_cbor:partial_decode(
        <<16#43, 1, 2, 3>>,
        [{max_string_size, 2}, {max_string_size, 3}]
    ),
    assert({max_string_size_exceeded, 2},
           partial_error_with_opts(
               <<16#43, 1, 2, 3>>,
               [{max_string_size, 3}, {max_string_size, 2}]
           )),
    {ok, _, <<>>} = avm_cbor:partial_decode(
        <<16#C1, 1>>,
        [{allow_tags, false}, {allow_tags, true}]
    ),
    assert({unsupported_tag, 1},
           partial_error_with_opts(
               <<16#C1, 1>>,
               [{allow_tags, true}, {allow_tags, false}]
           )),
    assert(invalid_options_list,
           element(2, avm_cbor:partial_decode(<<1>>, [{max_depth, 8} | invalid_tail]))),
    ok.

test_partial_error_malformed() ->
    assert(unexpected_break, partial_error(<<16#FF>>)),
    assert(reserved_additional_info, partial_error(<<16#1C>>)),
    assert(indefinite_length_unsupported, partial_error(<<16#1F>>)),
    %% max_bytes limit from the shared options applies
    assert({max_bytes_exceeded, 2},
           partial_error_with_opts(<<16#83, 1, 2, 3>>, [{max_bytes, 2}])),
    ok.

test_partial_accessor_errors() ->
    assert({error, not_a_partial}, avm_cbor:partial_type(not_a_partial)),
    assert({error, not_a_partial}, avm_cbor:partial_value_bytes(42)),
    assert({error, not_a_partial}, avm_cbor:partial_deep_decode({foo, bar})),
    assert({error, not_a_partial}, avm_cbor:partial_skip([])),
    assert({error, not_a_partial}, avm_cbor:partial_count(<<>>)),
    assert({error, not_a_partial}, avm_cbor:partial_tag(1.5)),
    assert({error, not_a_partial}, avm_cbor:partial_size(#{})),
    assert({error, not_a_partial}, avm_cbor:partial_offset(ok)),
    assert({error, not_a_partial}, avm_cbor:partial_length(ok)),
    assert({error, not_a_partial}, avm_cbor:partial_contents(ok)),
    %% contents is only defined for containers and tags
    assert({error, no_contents}, avm_cbor:partial_contents(partial_ok(<<16#00>>))),
    assert({error, no_contents}, avm_cbor:partial_contents(partial_ok(<<16#41, 1>>))),
    ok.

%%--------------------------------------------------------------------
%% Test helpers
%%--------------------------------------------------------------------

big_binary(N) -> big_binary(N, <<>>).
big_binary(0, Acc) -> Acc;
big_binary(N, Acc) -> big_binary(N - 1, <<Acc/binary, 16#61>>).

make_seq(N) -> make_seq(N, []).
make_seq(0, Acc) -> Acc;
make_seq(N, Acc) -> make_seq(N - 1, [N | Acc]).
