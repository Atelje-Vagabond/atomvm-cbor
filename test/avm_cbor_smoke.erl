-module(avm_cbor_smoke).
-export([run/0]).

run() ->
    io:format("~n=== avm_cbor smoke tests ===~n~n", []),
    tests([
        {decode_unsigned_integers, fun test_decode_unsigned_integers/0},
        {decode_negative_integers, fun test_decode_negative_integers/0},
        {decode_byte_strings, fun test_decode_byte_strings/0},
        {decode_text_strings, fun test_decode_text_strings/0},
        {decode_arrays, fun test_decode_arrays/0},
        {decode_maps, fun test_decode_maps/0},
        {decode_nested, fun test_decode_nested/0},
        {decode_simple, fun test_decode_simple/0},
        {decode_floats, fun test_decode_floats/0},
        {decode_rest_bytes, fun test_decode_rest_bytes/0},
        {decode_max_depth, fun test_decode_max_depth/0},
        {decode_max_items, fun test_decode_max_items/0},
        {decode_max_bytes, fun test_decode_max_bytes/0},
        {decode_max_string_bytes, fun test_decode_max_string_bytes/0},
        {decode_errors, fun test_decode_errors/0},
        {decode_indefinite, fun test_decode_indefinite/0},
        {decode_sequence, fun test_decode_sequence/0},
        {encode_unsigned_integers, fun test_encode_unsigned_integers/0},
        {encode_negative_integers, fun test_encode_negative_integers/0},
        {encode_byte_strings, fun test_encode_byte_strings/0},
        {encode_text_strings, fun test_encode_text_strings/0},
        {encode_arrays, fun test_encode_arrays/0},
        {encode_maps, fun test_encode_maps/0},
        {encode_simple_values, fun test_encode_simple_values/0},
        {encode_roundtrip, fun test_encode_roundtrip/0},
        {helpers, fun test_helpers/0},
        {option_validation, fun test_option_validation/0},
        {tags, fun test_tags/0},
        {encode_limits, fun test_encode_limits/0},
        {utf8_validation, fun test_utf8_validation/0}
    ]),
    io:format("~n=== all smoke tests passed ===~n"),
    halt(0).

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

decode_ok(Bin) ->
    case avm_cbor:decode(Bin) of
        {ok, Val, <<>>} -> Val;
        {ok, _, Rest} -> erlang:error({unexpected_rest, Rest});
        {error, Reason} -> erlang:error({decode_error, Reason})
    end.

decode_ok_with_rest(Bin) ->
    case avm_cbor:decode(Bin) of
        {ok, Val, Rest} -> {Val, Rest};
        {error, Reason} -> erlang:error({decode_error, Reason})
    end.

decode_error(Bin) ->
    case avm_cbor:decode(Bin) of
        {error, _} -> ok;
        Other -> erlang:error({expected_error, got, Other})
    end.

decode_error_with_opts(Bin, Opts) ->
    case avm_cbor:decode(Bin, Opts) of
        {error, _} -> ok;
        Other -> erlang:error({expected_error, got, Other})
    end.

decode_ok_with_opts(Bin, Opts) ->
    case avm_cbor:decode(Bin, Opts) of
        {ok, Val, <<>>} -> Val;
        {ok, _, Rest} -> erlang:error({unexpected_rest, Rest});
        {error, Reason} -> erlang:error({decode_error, Reason})
    end.

encode_ok(Val) ->
    case avm_cbor:encode(Val) of
        {ok, Bin} -> Bin;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

%%--------------------------------------------------------------------
%% Decode unsigned integers
%%--------------------------------------------------------------------

test_decode_unsigned_integers() ->
    assert(0, decode_ok(<<16#00>>)),
    assert(1, decode_ok(<<16#01>>)),
    assert(10, decode_ok(<<16#0A>>)),
    assert(23, decode_ok(<<16#17>>)),
    assert(24, decode_ok(<<16#18, 16#18>>)),
    assert(100, decode_ok(<<16#18, 16#64>>)),
    assert(1000, decode_ok(<<16#19, 16#03, 16#E8>>)),
    assert(1000000, decode_ok(<<16#1A, 16#00, 16#0F, 16#42, 16#40>>)),
    assert(16#FFFFFFFF, decode_ok(<<16#1A, 16#FF, 16#FF, 16#FF, 16#FF>>)),
    assert(16#FFFFFFFFFFFFFFFF, decode_ok(<<16#1B, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode negative integers
%%--------------------------------------------------------------------

test_decode_negative_integers() ->
    assert(-1, decode_ok(<<16#20>>)),
    assert(-10, decode_ok(<<16#29>>)),
    assert(-24, decode_ok(<<16#37>>)),
    assert(-25, decode_ok(<<16#38, 16#18>>)),
    assert(-100, decode_ok(<<16#38, 16#63>>)),
    assert(-1000, decode_ok(<<16#39, 16#03, 16#E7>>)),
    assert(-1000000, decode_ok(<<16#3A, 16#00, 16#0F, 16#42, 16#3F>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode byte strings
%%--------------------------------------------------------------------

test_decode_byte_strings() ->
    assert(<<>>, decode_ok(<<16#40>>)),
    assert(<<16#01, 16#02, 16#03, 16#04>>,
           decode_ok(<<16#44, 16#01, 16#02, 16#03, 16#04>>)),
    assert(<<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24>>,
           decode_ok(<<16#58, 16#19, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode text strings
%%--------------------------------------------------------------------

test_decode_text_strings() ->
    assert({text, <<>>}, decode_ok(<<16#60>>)),
    assert({text, <<"a">>}, decode_ok(<<16#61, 16#61>>)),
    assert({text, <<"IETF">>}, decode_ok(<<16#64, 16#49, 16#45, 16#54, 16#46>>)),
    assert({text, <<"\"\\">>}, decode_ok(<<16#62, 16#22, 16#5C>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode arrays
%%--------------------------------------------------------------------

test_decode_arrays() ->
    assert([], decode_ok(<<16#80>>)),
    assert([1, 2, 3], decode_ok(<<16#83, 16#01, 16#02, 16#03>>)),
    assert([1, [2, 3], [4, [5]]],
           decode_ok(<<16#83, 16#01, 16#82, 16#02, 16#03,
                       16#82, 16#04, 16#81, 16#05>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode maps
%%--------------------------------------------------------------------

test_decode_maps() ->
    assert({map, []}, decode_ok(<<16#A0>>)),
    assert({map, [{1, 2}, {3, 4}]},
           decode_ok(<<16#A2, 16#01, 16#02, 16#03, 16#04>>)),
    assert({map, [{{text, <<"a">>}, {text, <<"A">>}}]},
           decode_ok(<<16#A1, 16#61, 16#61, 16#61, 16#41>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode nested maps/arrays
%%--------------------------------------------------------------------

test_decode_nested() ->
    Bin = <<16#A2,
            16#01, 16#82, 16#02, 16#03,
            16#04, 16#A1,
              16#61, 16#61, 16#19, 16#03, 16#E8>>,
    Expected = {map, [{1, [2, 3]},
                      {4, {map, [{{text, <<"a">>}, 1000}]}}]},
    assert(Expected, decode_ok(Bin)),
    ok.

%%--------------------------------------------------------------------
%% Decode booleans/null/undefined/simple
%%--------------------------------------------------------------------

test_decode_simple() ->
    assert(false, decode_ok(<<16#F4>>)),
    assert(true, decode_ok(<<16#F5>>)),
    assert(null, decode_ok(<<16#F6>>)),
    assert(undefined, decode_ok(<<16#F7>>)),
    assert({simple, 0}, decode_ok(<<16#E0>>)),
    assert({simple, 16}, decode_ok(<<16#F0>>)),
    assert({simple, 255}, decode_ok(<<16#F8, 16#FF>>)),
    ok.

%%--------------------------------------------------------------------
%% Decode floats
%%--------------------------------------------------------------------

test_decode_floats() ->
    assert(1.0, decode_ok(<<16#FA, 16#3F, 16#80, 16#00, 16#00>>)),
    assert(3.4028234663852886e38, decode_ok(<<16#FA, 16#7F, 16#7F, 16#FF, 16#FF>>)),
    assert(1.0, decode_ok(<<16#FB, 16#3F, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>)),
    assert(1.0e300, decode_ok(<<16#FB, 16#7E, 16#37, 16#E4, 16#3C, 16#88, 16#00, 16#75,
                                16#9C>>)),
    %% Half-precision float: 0.0
    assert(0.0, decode_ok(<<16#F9, 16#00, 16#00>>)),
    %% Half-precision float: -0.0
    assert(-0.0, decode_ok(<<16#F9, 16#80, 16#00>>)),
    %% Half-precision float: 1.0
    assert(1.0, decode_ok(<<16#F9, 16#3C, 16#00>>)),
    %% Half-precision float: 1.5
    assert(1.5, decode_ok(<<16#F9, 16#3E, 16#00>>)),
    %% Half-precision float: 65504.0 (max finite)
    assert(65504.0, decode_ok(<<16#F9, 16#7B, 16#FF>>)),
    %% Half-precision float: 0.000000059604645 (min positive subnormal)
    assert(5.960464477539063e-8, decode_ok(<<16#F9, 16#00, 16#01>>)),
    %% Half-precision float: +inf returns controlled error
    {error, {unsupported_simple_value, infinity}} = avm_cbor:decode(<<16#F9, 16#7C, 16#00>>),
    %% Half-precision float: -inf returns controlled error
    {error, {unsupported_simple_value, infinity}} = avm_cbor:decode(<<16#F9, 16#FC, 16#00>>),
    %% Half-precision float: NaN returns controlled error
    {error, {unsupported_simple_value, nan}} = avm_cbor:decode(<<16#F9, 16#7E, 16#00>>),
    %% Half-precision float with allow_floats=false
    {error, floats_not_allowed} = avm_cbor:decode(<<16#F9, 16#3C, 16#00>>, [{allow_floats, false}]),
    %% Partial options: floats still work by default
    assert(1.0, decode_ok_with_opts(<<16#FA, 16#3F, 16#80, 16#00, 16#00>>, [{max_depth, 8}])),
    ok.

%%--------------------------------------------------------------------
%% Decode rest bytes
%%--------------------------------------------------------------------

test_decode_rest_bytes() ->
    {1, <<16#02>>} = decode_ok_with_rest(<<16#01, 16#02>>),
    {2, <<16#03, 16#04>>} = decode_ok_with_rest(<<16#02, 16#03, 16#04>>),
    {[1], <<16#02>>} = decode_ok_with_rest(<<16#81, 16#01, 16#02>>),
    ok.

%%--------------------------------------------------------------------
%% Decode limits: max_depth
%%--------------------------------------------------------------------

test_decode_max_depth() ->
    %% Depth-9 array with max_depth=8 should fail
    D9 = lists:foldl(fun(_, Acc) -> <<16#81, Acc/binary>> end, <<16#01>>, lists:seq(1, 9)),
    decode_error_with_opts(D9, [{max_depth, 8}]),
    %% Depth-8 array with max_depth=8 should succeed
    D8 = lists:foldl(fun(_, Acc) -> <<16#81, Acc/binary>> end, <<16#01>>, lists:seq(1, 8)),
    Nested = lists:foldl(fun(_, Acc) -> [Acc] end, 1, lists:seq(1, 8)),
    assert(Nested, decode_ok(D8)),
    ok.

%%--------------------------------------------------------------------
%% Decode limits: max_items
%%--------------------------------------------------------------------

test_decode_max_items() ->
    %% Array with 3 items with max_items=2 should fail
    decode_error_with_opts(<<16#83, 16#01, 16#02, 16#03>>, [{max_items, 2}]),
    %% Array with 3 items with max_items=3 should succeed
    decode_ok(<<16#83, 16#01, 16#02, 16#03>>),
    %% Map with 3 pairs with max_items=2 should fail
    decode_error_with_opts(<<16#A3, 16#01, 16#0A, 16#02, 16#14, 16#03, 16#1E>>, [{max_items, 2}]),
    ok.

%%--------------------------------------------------------------------
%% Decode limits: max_bytes
%%--------------------------------------------------------------------

test_decode_max_bytes() ->
    %% 100-byte payload with max_bytes=50 should fail
    Big = <<16#58, 16#19, (<<0:200/unit:8>>)/binary>>,
    decode_error_with_opts(Big, [{max_bytes, 10}]),
    %% Small payload with max_bytes=0 (unlimited) should work
    decode_ok(<<16#01>>),
    ok.

%%--------------------------------------------------------------------
%% Decode limits: max_string_bytes
%%--------------------------------------------------------------------

test_decode_max_string_bytes() ->
    %% 30-byte string with max_string_bytes=10 should fail
    Str = <<16#58, 16#1E, (<<16#41:30/unit:8>>)/binary>>,
    decode_error_with_opts(Str, [{max_string_bytes, 10}]),
    %% 30-byte string with max_string_bytes=30 should succeed
    decode_ok(<<16#58, 16#1E, (<<16#41:30/unit:8>>)/binary>>),
    ok.

%%--------------------------------------------------------------------
%% Decode errors
%%--------------------------------------------------------------------

test_decode_errors() ->
    decode_error(<<>>),
    decode_error(<<16#1C>>),
    decode_error(<<16#1D>>),
    decode_error(<<16#1E>>),
    decode_error(<<16#FF>>),
    decode_error(<<16#59>>),
    decode_error(<<16#5A>>),
    decode_error(<<16#F9>>),
    decode_error(<<16#C0>>),
    decode_error(<<16#D0>>),
    ok.

%%--------------------------------------------------------------------
%% Encode unsigned integers
%%--------------------------------------------------------------------

test_encode_unsigned_integers() ->
    assert(<<16#00>>, encode_ok(0)),
    assert(<<16#01>>, encode_ok(1)),
    assert(<<16#17>>, encode_ok(23)),
    assert(<<16#18, 16#18>>, encode_ok(24)),
    assert(<<16#18, 16#64>>, encode_ok(100)),
    assert(<<16#19, 16#03, 16#E8>>, encode_ok(1000)),
    assert(<<16#1A, 16#00, 16#0F, 16#42, 16#40>>, encode_ok(1000000)),
    assert(<<16#1B, 16#00, 16#00, 16#00, 16#01, 16#00, 16#00, 16#00, 16#00>>,
           encode_ok(4294967296)),
    ok.

%%--------------------------------------------------------------------
%% Encode negative integers
%%--------------------------------------------------------------------

test_encode_negative_integers() ->
    assert(<<16#20>>, encode_ok(-1)),
    assert(<<16#29>>, encode_ok(-10)),
    assert(<<16#38, 16#18>>, encode_ok(-25)),
    assert(<<16#38, 16#63>>, encode_ok(-100)),
    assert(<<16#39, 16#03, 16#E7>>, encode_ok(-1000)),
    ok.

%%--------------------------------------------------------------------
%% Encode byte strings
%%--------------------------------------------------------------------

test_encode_byte_strings() ->
    assert(<<16#40>>, encode_ok(<<>>)),
    assert(<<16#44, 16#01, 16#02, 16#03, 16#04>>, encode_ok(<<16#01, 16#02, 16#03, 16#04>>)),
    assert(<<16#48, 16#00, 16#01, 16#02, 16#03, 16#04, 16#05, 16#06, 16#07>>,
           encode_ok(<<0, 1, 2, 3, 4, 5, 6, 7>>)),
    ok.

%%--------------------------------------------------------------------
%% Encode text strings
%%--------------------------------------------------------------------

test_encode_text_strings() ->
    assert(<<16#60>>, encode_ok({text, <<>>})),
    assert(<<16#61, 16#61>>, encode_ok({text, <<"a">>})),
    assert(<<16#64, 16#49, 16#45, 16#54, 16#46>>, encode_ok({text, <<"IETF">>})),
    %% Valid UTF-8 multibyte
    assert(<<16#62, 16#C2, 16#A9>>, encode_ok({text, <<16#C2, 16#A9>>})),
    %% Invalid UTF-8 rejected on encode
    {error, invalid_utf8} = avm_cbor:encode({text, <<16#FF>>}),
    {error, invalid_utf8} = avm_cbor:encode({text, <<16#C0, 16#80>>}),
    {error, invalid_utf8} = avm_cbor:encode({text, <<16#ED, 16#A0, 16#80>>}),
    %% Valid 4-byte UTF-8
    {ok, _} = avm_cbor:encode({text, <<16#F0, 16#9F, 16#98, 16#80>>}),
    ok.

%%--------------------------------------------------------------------
%% Encode arrays
%%--------------------------------------------------------------------

test_encode_arrays() ->
    assert(<<16#80>>, encode_ok([])),
    assert(<<16#83, 16#01, 16#02, 16#03>>, encode_ok([1, 2, 3])),
    assert(<<16#83, 16#01, 16#82, 16#02, 16#03, 16#81, 16#04>>,
           encode_ok([1, [2, 3], [4]])),
    ok.

%%--------------------------------------------------------------------
%% Encode maps
%%--------------------------------------------------------------------

test_encode_maps() ->
    assert(<<16#A0>>, encode_ok({map, []})),
    assert(<<16#A2, 16#01, 16#02, 16#03, 16#04>>,
           encode_ok({map, [{1, 2}, {3, 4}]})),
    assert(<<16#A1, 16#61, 16#61, 16#61, 16#41>>,
           encode_ok({map, [{{text, <<"a">>}, {text, <<"A">>}}]})),
    ok.

%%--------------------------------------------------------------------
%% Encode booleans/null/undefined
%%--------------------------------------------------------------------

test_encode_simple_values() ->
    assert(<<16#F4>>, encode_ok(false)),
    assert(<<16#F5>>, encode_ok(true)),
    assert(<<16#F6>>, encode_ok(null)),
    assert(<<16#F7>>, encode_ok(undefined)),
    %% Floats encode as 64-bit double
    assert(<<16#FB, 16#3F, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>, encode_ok(1.0)),
    assert(<<16#FB, 16#7E, 16#37, 16#E4, 16#3C,
             16#88, 16#00, 16#75, 16#9C>>, encode_ok(1.0e300)),
    assert(<<16#E0>>, encode_ok({simple, 0})),
    assert(<<16#F0>>, encode_ok({simple, 16})),
    assert(<<16#F8, 16#18>>, encode_ok({simple, 24})),
    assert(<<16#F8, 16#1F>>, encode_ok({simple, 31})),
    assert(<<16#F8, 16#FF>>, encode_ok({simple, 255})),
    %% Roundtrip simple values
    assert({simple, 24}, decode_ok(encode_ok({simple, 24}))),
    assert({simple, 31}, decode_ok(encode_ok({simple, 31}))),
    ok.

%%--------------------------------------------------------------------
%% Encode/decode roundtrip
%%--------------------------------------------------------------------

test_encode_roundtrip() ->
    %% Roundtrip an integer
    Bin1 = encode_ok(42),
    assert(42, decode_ok(Bin1)),
    %% Roundtrip a nested structure
    Val = {map, [
        {1, {text, <<"set_wifi">>}},
        {2, {text, <<"MySSID">>}},
        {3, <<"secret-bytes">>}
    ]},
    Bin2 = encode_ok(Val),
    assert(Val, decode_ok(Bin2)),
    %% BLE-style integer-keyed map
    BleVal = {map, [
        {1, {text, <<"set_wifi">>}},
        {2, {text, <<"MySSID">>}},
        {3, <<"secret">>}
    ]},
    BleBin = encode_ok(BleVal),
    assert(BleVal, decode_ok(BleBin)),
    %% Mixed types
    Mixed = {map, [
        {1, 100},
        {2, {text, <<"hello">>}},
        {3, [1, 2, 3]},
        {4, true},
        {5, null}
    ]},
    MBin = encode_ok(Mixed),
    assert(Mixed, decode_ok(MBin)),
    %% Float roundtrip
    FBits = encode_ok(3.14),
    assert(3.14, decode_ok(FBits)),
    %% Zero float roundtrip
    ZBits = encode_ok(0.0),
    assert(0.0, decode_ok(ZBits)),
    ok.

%%--------------------------------------------------------------------
%% Option validation
%%--------------------------------------------------------------------

test_option_validation() ->
    %% Invalid options return error tuple
    {error, {invalid_option, _}} = avm_cbor:decode(<<16#01>>, [bad_option]),
    {error, {invalid_option, _}} = avm_cbor:decode(<<16#01>>, [{max_depth, bad}]),
    {error, {invalid_option, _}} = avm_cbor:decode(<<16#01>>, [{max_depth, -1}]),
    {error, {invalid_option, _}} = avm_cbor:encode(1, [bad_option]),
    {error, {invalid_option, _}} = avm_cbor:encode(1, [{allow_floats, perhaps}]),
    %% Valid options with decode/2
    {ok, 1, <<>>} = avm_cbor:decode(<<16#01>>, [{max_depth, 8}]),
    {ok, 1, <<>>} = avm_cbor:decode(<<16#01>>, []),
    %% Valid options with encode/2
    {ok, _} = avm_cbor:encode(1, [{max_items, 1}]),
    {ok, _} = avm_cbor:encode(1, []),
    ok.

%%--------------------------------------------------------------------
%% Tag errors
%%--------------------------------------------------------------------

test_tags() ->
    %% Tags decode as {tag, Tag, Value} by default
    assert({tag, 1, 1}, decode_ok(<<16#C1, 16#01>>)),
    assert({tag, 32, 1}, decode_ok(<<16#D8, 16#20, 16#01>>)),
    assert({tag, 65535, 1}, decode_ok(<<16#D9, 16#FF, 16#FF, 16#01>>)),
    %% Nested tags
    assert({tag, 1, {tag, 2, 3}}, decode_ok(<<16#C1, 16#C2, 16#03>>)),
    %% Tag with list content
    assert({tag, 1, [2, 3]}, decode_ok(<<16#C1, 16#82, 16#02, 16#03>>)),
    %% Tag with map content
    assert({tag, 1, {map, [{2, 3}]}},
           decode_ok(<<16#C1, 16#A1, 16#02, 16#03>>)),
    %% allow_tags=false returns error
    {error, {unsupported_tag, 1}} = avm_cbor:decode(<<16#C1, 16#01>>, [{allow_tags, false}]),
    {error, {unsupported_tag, 32}} = avm_cbor:decode(<<16#D8, 16#20, 16#01>>, [{allow_tags, false}]),
    %% Tag encode/decode roundtrip
    assert({tag, 1, 42}, decode_ok(encode_ok({tag, 1, 42}))),
    assert({tag, 100, {text, <<"hello">>}},
           decode_ok(encode_ok({tag, 100, {text, <<"hello">>}}))),
    %% Tag encode with allow_tags=false
    {error, tags_not_allowed} = avm_cbor:encode({tag, 1, 2}, [{allow_tags, false}]),
    ok.

%%--------------------------------------------------------------------
%% Encode limit enforcement
%%--------------------------------------------------------------------

test_encode_limits() ->
    %% max_depth enforcement
    Deep = [1, [2, [3]]],
    {ok, _} = avm_cbor:encode(Deep, [{max_depth, 3}]),
    {error, {max_depth_exceeded, 2}} = avm_cbor:encode(Deep, [{max_depth, 2}]),
    %% max_items enforcement
    Many = lists:seq(1, 10),
    {ok, _} = avm_cbor:encode(Many, [{max_items, 10}]),
    {error, {max_items_exceeded, 5}} = avm_cbor:encode(Many, [{max_items, 5}]),
    %% max_string_bytes enforcement
    Big = binary:copy(<<0>>, 100),
    {ok, _} = avm_cbor:encode(<<>>, [{max_string_bytes, 100}]),
    {error, {max_string_bytes_exceeded, 50}} = avm_cbor:encode(Big, [{max_string_bytes, 50}]),
    {error, {max_string_bytes_exceeded, 50}} =
        avm_cbor:encode({text, Big}, [{max_string_bytes, 50}]),
    %% allow_floats enforcement
    {error, floats_not_allowed} = avm_cbor:encode(1.5, [{allow_floats, false}]),
    {ok, _} = avm_cbor:encode(1.5, [{allow_floats, true}]),
    %% Zero float encode
    {ok, <<16#FB, 0, 0, 0, 0, 0, 0, 0, 0>>} = avm_cbor:encode(0.0, []),
    {ok, _} = avm_cbor:encode(-0.0, []),
    %% allow_simple enforcement
    {error, simple_values_not_allowed} = avm_cbor:encode({simple, 0}, [{allow_simple, false}]),
    {ok, _} = avm_cbor:encode({simple, 0}, [{allow_simple, true}]),
    %% max_bytes enforcement
    {error, {max_bytes_exceeded, 1}} = avm_cbor:encode(1000, [{max_bytes, 1}]),
    {ok, _} = avm_cbor:encode(1000, [{max_bytes, 3}]),
    %% integer out of range
    {error, {integer_out_of_range, _}} = avm_cbor:encode(16#10000000000000000, []),
    {error, {integer_out_of_range, _}} = avm_cbor:encode(-18446744073709551617, []),
    %% tag out of range
    {error, {tag_out_of_range, _}} = avm_cbor:encode({tag, 16#10000000000000000, 1}, []),
    ok.

%%--------------------------------------------------------------------
%% Helper functions
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Decode indefinite-length items
%%--------------------------------------------------------------------

test_decode_indefinite() ->
    %% Indefinite-length byte string
    assert(<<16#01, 16#02, 16#03, 16#04>>,
           decode_ok(<<16#5F, 16#42, 16#01, 16#02, 16#42, 16#03, 16#04, 16#FF>>)),
    %% Indefinite-length byte string single chunk
    assert(<<16#01, 16#02>>,
           decode_ok(<<16#5F, 16#42, 16#01, 16#02, 16#FF>>)),
    %% Indefinite-length text string
    assert({text, <<"hello">>},
           decode_ok(<<16#7F, 16#63, 16#68, 16#65, 16#6C, 16#62, 16#6C, 16#6F, 16#FF>>)),
    %% Indefinite-length array
    assert([1, 2, 3],
           decode_ok(<<16#9F, 16#01, 16#02, 16#03, 16#FF>>)),
    %% Indefinite-length empty array
    assert([], decode_ok(<<16#9F, 16#FF>>)),
    %% Indefinite-length array with nested
    assert([1, [2, 3]],
           decode_ok(<<16#9F, 16#01, 16#82, 16#02, 16#03, 16#FF>>)),
    %% Indefinite-length map
    assert({map, [{1, 2}, {3, 4}]},
           decode_ok(<<16#BF, 16#01, 16#02, 16#03, 16#04, 16#FF>>)),
    %% Indefinite-length empty map
    assert({map, []}, decode_ok(<<16#BF, 16#FF>>)),
    %% allow_indefinite=false returns error
    {error, indefinite_length_unsupported} =
        avm_cbor:decode(<<16#9F, 16#01, 16#FF>>, [{allow_indefinite, false}]),
    {error, indefinite_length_unsupported} =
        avm_cbor:decode(<<16#BF, 16#FF>>, [{allow_indefinite, false}]),
    %% Break byte (0xFF) as top-level item is unexpected_break
    {error, unexpected_break} = avm_cbor:decode(<<16#FF>>),
    %% Indefinite byte string with definite-only chunks (nested indefinite rejected)
    {error, {invalid_indefinite_chunk, expected_byte_string}} =
        avm_cbor:decode(<<16#5F, 16#5F, 16#41, 1, 16#FF, 16#FF>>),
    %% Indefinite text string with definite-only chunks (nested indefinite rejected)
    {error, {invalid_indefinite_chunk, expected_text_string}} =
        avm_cbor:decode(<<16#7F, 16#7F, 16#61, $a, 16#FF, 16#FF>>),
    ok.

%%--------------------------------------------------------------------
%% Decode CBOR sequence (decode_all / decode_sequence)
%%--------------------------------------------------------------------

test_decode_sequence() ->
    %% Empty sequence
    {ok, []} = avm_cbor:decode_all(<<>>),
    %% Single item
    {ok, [1]} = avm_cbor:decode_all(<<16#01>>),
    %% Multiple items
    {ok, [1, 2, 3]} = avm_cbor:decode_all(<<16#01, 16#02, 16#03>>),
    %% Mixed types
    {ok, [1, {text, <<"a">>}, [2]]} =
        avm_cbor:decode_all(<<16#01, 16#61, 16#61, 16#81, 16#02>>),
    %% With options
    {error, {invalid_option, _}} = avm_cbor:decode_all(<<16#01>>, [bad_option]),
    %% max_bytes enforced
    {error, {max_bytes_exceeded, 1}} = avm_cbor:decode_all(<<16#01, 16#02>>, [{max_bytes, 1}]),
    %% decode_sequence returns {ok, Values, Rest} with trailing truncated data
    {ok, [], <<>>} = avm_cbor:decode_sequence(<<>>),
    {ok, [1], <<>>} = avm_cbor:decode_sequence(<<16#01>>),
    {ok, [1, 2], <<>>} = avm_cbor:decode_sequence(<<16#01, 16#02>>),
    {ok, [1, 2], <<16#82, 3>>} = avm_cbor:decode_sequence(<<16#01, 16#02, 16#82, 3>>),
    {error, unexpected_break} = avm_cbor:decode_sequence(<<16#01, 16#FF>>),
    %% decode_sequence with options
    {error, {invalid_option, _}} = avm_cbor:decode_sequence(<<16#01>>, [bad_option]),
    ok.

%%--------------------------------------------------------------------
%% UTF-8 validation
%%--------------------------------------------------------------------

test_utf8_validation() ->
    %% Valid UTF-8: ASCII-only
    assert({text, <<"hello">>}, decode_ok(<<16#65, 16#68, 16#65, 16#6C, 16#6C, 16#6F>>)),
    %% Valid UTF-8: 2-byte sequence (U+00A9 copyright)
    assert({text, <<16#C2, 16#A9>>}, decode_ok(<<16#62, 16#C2, 16#A9>>)),
    %% Valid UTF-8: 3-byte sequence (U+20AC euro)
    assert({text, <<16#E2, 16#82, 16#AC>>}, decode_ok(<<16#63, 16#E2, 16#82, 16#AC>>)),
    %% Valid UTF-8: 4-byte sequence (U+1F600 emoji)
    assert({text, <<16#F0, 16#9F, 16#98, 16#80>>}, decode_ok(<<16#64, 16#F0, 16#9F, 16#98, 16#80>>)),
    %% Valid UTF-8: empty
    assert({text, <<>>}, decode_ok(<<16#60>>)),
    %% Invalid UTF-8: continuation byte without leading byte
    {error, invalid_utf8} = avm_cbor:decode(<<16#61, 16#80>>),
    %% Invalid UTF-8: missing continuation byte
    {error, invalid_utf8} = avm_cbor:decode(<<16#61, 16#C2>>),
    %% Invalid UTF-8: overlong 2-byte encoding of ASCII (U+002F)
    {error, invalid_utf8} = avm_cbor:decode(<<16#62, 16#C0, 16#80>>),
    %% Invalid UTF-8: surrogate U+D800
    {error, invalid_utf8} = avm_cbor:decode(<<16#63, 16#ED, 16#A0, 16#80>>),
    %% Invalid UTF-8: codepoint above U+10FFFF (U+110000)
    {error, invalid_utf8} = avm_cbor:decode(<<16#64, 16#F4, 16#90, 16#80, 16#80>>),
    %% Invalid UTF-8: 0xFF byte
    {error, invalid_utf8} = avm_cbor:decode(<<16#61, 16#FF>>),
    %% Invalid UTF-8: 0xFE byte
    {error, invalid_utf8} = avm_cbor:decode(<<16#61, 16#FE>>),
    ok.

test_helpers() ->
    Map = {map, [{1, <<"bytes">>}, {2, {text, <<"text">>}}, {3, 42}, {4, true}, {5, null}]},
    %% get/2
    assert({ok, <<"bytes">>}, avm_cbor:get(1, Map)),
    assert(error, avm_cbor:get(99, Map)),
    %% get/3
    assert(<<"bytes">>, avm_cbor:get(1, Map, <<"default">>)),
    assert(<<"default">>, avm_cbor:get(99, Map, <<"default">>)),
    %% require/2
    assert({ok, <<"bytes">>}, avm_cbor:require(1, Map)),
    assert({error, {missing_key, 99}}, avm_cbor:require(99, Map)),
    %% as_text/1
    assert({ok, <<"text">>}, avm_cbor:as_text({text, <<"text">>})),
    assert({error, bad_type}, avm_cbor:as_text(<<"raw">>)),
    assert({error, bad_type}, avm_cbor:as_text(42)),
    %% as_bytes/1
    assert({ok, <<"raw">>}, avm_cbor:as_bytes(<<"raw">>)),
    assert({error, bad_type}, avm_cbor:as_bytes({text, <<"x">>})),
    %% as_int/1
    assert({ok, 42}, avm_cbor:as_int(42)),
    assert({error, bad_type}, avm_cbor:as_int(<<"x">>)),
    %% as_bool/1
    assert({ok, true}, avm_cbor:as_bool(true)),
    assert({ok, false}, avm_cbor:as_bool(false)),
    assert({error, bad_type}, avm_cbor:as_bool(null)),
    ok.
