-module(avm_cbor_rfc8949).
-export([run/0, run_coverage/0]).

run() ->
    run_coverage(),
    halt(0).

run_coverage() ->
    io:format("~n=== RFC 8949 vector tests ===~n~n", []),
    tests([
        {appendix_a_scalars, fun appendix_a_scalars/0},
        {appendix_a_strings_and_containers, fun appendix_a_strings_and_containers/0},
        {appendix_a_indefinite_items, fun appendix_a_indefinite_items/0},
        {appendix_a_tag_examples, fun appendix_a_tag_examples/0},
        {appendix_a_float_edges, fun appendix_a_float_edges/0},
        {appendix_a_preferred_float_encode, fun appendix_a_preferred_float_encode/0},
        {preferred_float_decode_boundaries, fun preferred_float_decode_boundaries/0},
        {core_deterministic_decode, fun core_deterministic_decode/0}
    ]),
    io:format("~n=== all RFC 8949 vector tests passed ===~n"),
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

decode_ok(Bin) ->
    case avm_cbor:decode(Bin) of
        {ok, Val, <<>>} -> Val;
        {ok, _, Rest} -> erlang:error({unexpected_rest, Rest});
        {error, Reason} -> erlang:error({decode_error, Reason})
    end.

encode_ok(Val) ->
    case avm_cbor:encode(Val) of
        {ok, Bin} -> Bin;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

encode_ok_with_opts(Val, Opts) ->
    case avm_cbor:encode(Val, Opts) of
        {ok, Bin} -> Bin;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

%%--------------------------------------------------------------------
%% Appendix A: scalars
%%--------------------------------------------------------------------

appendix_a_scalars() ->
    assert(0, decode_ok(<<16#00>>)),
    assert(1, decode_ok(<<16#01>>)),
    assert(10, decode_ok(<<16#0A>>)),
    assert(23, decode_ok(<<16#17>>)),
    assert(24, decode_ok(<<16#18, 16#18>>)),
    assert(25, decode_ok(<<16#18, 16#19>>)),
    assert(100, decode_ok(<<16#18, 16#64>>)),
    assert(1000, decode_ok(<<16#19, 16#03, 16#E8>>)),
    assert(1000000, decode_ok(<<16#1A, 16#00, 16#0F, 16#42, 16#40>>)),
    assert(1000000000000, decode_ok(<<16#1B, 16#00, 16#00, 16#00, 16#E8, 16#D4, 16#A5, 16#10, 16#00>>)),
    assert(-1, decode_ok(<<16#20>>)),
    assert(-10, decode_ok(<<16#29>>)),
    assert(-100, decode_ok(<<16#38, 16#63>>)),
    assert(-1000, decode_ok(<<16#39, 16#03, 16#E7>>)),
    assert(0.0, decode_ok(<<16#F9, 16#00, 16#00>>)),
    assert(-0.0, decode_ok(<<16#F9, 16#80, 16#00>>)),
    assert(1.0, decode_ok(<<16#F9, 16#3C, 16#00>>)),
    assert(1.1, decode_ok(<<16#FB, 16#3F, 16#F1, 16#99, 16#99, 16#99, 16#99, 16#99, 16#9A>>)),
    assert(1.5, decode_ok(<<16#F9, 16#3E, 16#00>>)),
    assert(65504.0, decode_ok(<<16#F9, 16#7B, 16#FF>>)),
    assert(false, decode_ok(<<16#F4>>)),
    assert(true, decode_ok(<<16#F5>>)),
    assert(null, decode_ok(<<16#F6>>)),
    assert(undefined, decode_ok(<<16#F7>>)),
    assert({simple, 16}, decode_ok(<<16#F0>>)),
    assert({simple, 255}, decode_ok(<<16#F8, 16#FF>>)),
    assert(<<16#00>>, encode_ok(0)),
    assert(<<16#18, 16#18>>, encode_ok(24)),
    assert(<<16#19, 16#03, 16#E8>>, encode_ok(1000)),
    assert(<<16#20>>, encode_ok(-1)),
    assert(<<16#FB, 16#3F, 16#F1, 16#99, 16#99, 16#99, 16#99, 16#99, 16#9A>>, encode_ok(1.1)),
    assert(<<16#F4>>, encode_ok(false)),
    assert(<<16#F8, 16#FF>>, encode_ok({simple, 255})),
    ok.

%%--------------------------------------------------------------------
%% Appendix A: strings and containers
%%--------------------------------------------------------------------

appendix_a_strings_and_containers() ->
    assert(<<>>, decode_ok(<<16#40>>)),
    assert(<<16#01, 16#02, 16#03, 16#04>>, decode_ok(<<16#44, 16#01, 16#02, 16#03, 16#04>>)),
    assert({text, <<>>}, decode_ok(<<16#60>>)),
    assert({text, <<"a">>}, decode_ok(<<16#61, 16#61>>)),
    assert({text, <<"IETF">>}, decode_ok(<<16#64, 16#49, 16#45, 16#54, 16#46>>)),
    assert({text, <<"\"\\">>}, decode_ok(<<16#62, 16#22, 16#5C>>)),
    assert({text, <<16#C3, 16#BC>>}, decode_ok(<<16#62, 16#C3, 16#BC>>)),
    assert({text, <<16#E6, 16#B0, 16#B4>>}, decode_ok(<<16#63, 16#E6, 16#B0, 16#B4>>)),
    assert({text, <<16#F0, 16#90, 16#85, 16#91>>}, decode_ok(<<16#64, 16#F0, 16#90, 16#85, 16#91>>)),
    assert([], decode_ok(<<16#80>>)),
    assert([1, 2, 3], decode_ok(<<16#83, 16#01, 16#02, 16#03>>)),
    assert([1, [2, 3], [4, 5]], decode_ok(<<16#83, 16#01, 16#82, 16#02, 16#03, 16#82, 16#04, 16#05>>)),
    assert({map, []}, decode_ok(<<16#A0>>)),
    assert({map, [{1, 2}, {3, 4}]}, decode_ok(<<16#A2, 16#01, 16#02, 16#03, 16#04>>)),
    assert({map, [{{text, <<"a">>}, 1}, {{text, <<"b">>}, [2, 3]}]},
           decode_ok(<<16#A2, 16#61, 16#61, 16#01, 16#61, 16#62, 16#82, 16#02, 16#03>>)),
    assert(<<16#40>>, encode_ok(<<>>)),
    assert(<<16#44, 16#01, 16#02, 16#03, 16#04>>, encode_ok(<<16#01, 16#02, 16#03, 16#04>>)),
    assert(<<16#60>>, encode_ok({text, <<>>})),
    assert(<<16#64, 16#49, 16#45, 16#54, 16#46>>, encode_ok({text, <<"IETF">>})),
    assert(<<16#62, 16#22, 16#5C>>, encode_ok({text, <<"\"\\">>})),
    assert(<<16#80>>, encode_ok([])),
    assert(<<16#83, 16#01, 16#02, 16#03>>, encode_ok([1, 2, 3])),
    assert(<<16#A2, 16#01, 16#02, 16#03, 16#04>>, encode_ok({map, [{1, 2}, {3, 4}]})),
    ok.

%%--------------------------------------------------------------------
%% Appendix A: indefinite-length items
%%--------------------------------------------------------------------

appendix_a_indefinite_items() ->
    assert(<<16#01, 16#02, 16#03, 16#04>>,
           decode_ok(<<16#5F, 16#42, 16#01, 16#02, 16#42, 16#03, 16#04, 16#FF>>)),
    assert({text, <<"streaming">>},
           decode_ok(<<16#7F, 16#65, 16#73, 16#74, 16#72, 16#65, 16#61, 16#64, 16#6D, 16#69, 16#6E, 16#67, 16#FF>>)),
    assert([], decode_ok(<<16#9F, 16#FF>>)),
    assert([1, [2, 3], [4, 5]],
           decode_ok(<<16#9F, 16#01, 16#82, 16#02, 16#03, 16#82, 16#04, 16#05, 16#FF>>)),
    assert([1, [2, 3], [4, 5]],
           decode_ok(<<16#83, 16#01, 16#9F, 16#02, 16#03, 16#FF, 16#82, 16#04, 16#05>>)),
    assert({map, []}, decode_ok(<<16#BF, 16#FF>>)),
    assert({map, [{1, 2}, {3, 4}]}, decode_ok(<<16#BF, 16#01, 16#02, 16#03, 16#04, 16#FF>>)),
    assert({map, [{{text, <<"a">>}, 1}, {{text, <<"b">>}, [2, 3]}]},
           decode_ok(<<16#BF, 16#61, 16#61, 16#01, 16#61, 16#62, 16#9F, 16#02, 16#03, 16#FF, 16#FF>>)),
    ok.

%%--------------------------------------------------------------------
%% Appendix A: tags
%%--------------------------------------------------------------------

appendix_a_tag_examples() ->
    assert({tag, 0, {text, <<"2013-03-21T20:04:00Z">>}},
           decode_ok(<<16#C0, 16#74, 16#32, 16#30, 16#31, 16#33, 16#2D, 16#30, 16#33, 16#2D,
                        16#32, 16#31, 16#54, 16#32, 16#30, 16#3A, 16#30, 16#34, 16#3A, 16#30, 16#30, 16#5A>>)),
    assert({tag, 1, 1363896240}, decode_ok(<<16#C1, 16#1A, 16#51, 16#4B, 16#67, 16#B0>>)),
    assert({tag, 1, 1363896240.5}, decode_ok(<<16#C1, 16#FB, 16#41, 16#D4, 16#52, 16#D9, 16#EC, 16#20, 16#00, 16#00>>)),
    assert({tag, 23, <<16#01, 16#02, 16#03, 16#04>>},
           decode_ok(<<16#D7, 16#44, 16#01, 16#02, 16#03, 16#04>>)),
    assert(<<16#C0, 16#74, 16#32, 16#30, 16#31, 16#33, 16#2D, 16#30, 16#33, 16#2D,
             16#32, 16#31, 16#54, 16#32, 16#30, 16#3A, 16#30, 16#34, 16#3A, 16#30, 16#30, 16#5A>>,
           encode_ok({tag, 0, {text, <<"2013-03-21T20:04:00Z">>}})),
    assert(<<16#C1, 16#1A, 16#51, 16#4B, 16#67, 16#B0>>, encode_ok({tag, 1, 1363896240})),
    ok.

%%--------------------------------------------------------------------
%% Appendix A: float edge behavior
%%--------------------------------------------------------------------

appendix_a_float_edges() ->
    {error, {unsupported_simple_value, invalid_float}} = avm_cbor:decode(<<16#F9, 16#7C, 16#00>>),
    {error, {unsupported_simple_value, invalid_float}} = avm_cbor:decode(<<16#F9, 16#FC, 16#00>>),
    {error, {unsupported_simple_value, invalid_float}} = avm_cbor:decode(<<16#F9, 16#7E, 16#00>>),
    assert(0.0, decode_ok(<<16#F9, 16#00, 16#00>>)),
    assert(-0.0, decode_ok(<<16#F9, 16#80, 16#00>>)),
    assert(5.960464477539063e-8, decode_ok(<<16#F9, 16#00, 16#01>>)),
    assert(1.0, decode_ok(<<16#FA, 16#3F, 16#80, 16#00, 16#00>>)),
    assert(1.0, decode_ok(<<16#FB, 16#3F, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>)),
    assert(1.1, decode_ok(<<16#FB, 16#3F, 16#F1, 16#99, 16#99, 16#99, 16#99, 16#99, 16#9A>>)),
    assert(65504.0, decode_ok(<<16#F9, 16#7B, 16#FF>>)),
    assert(<<16#FB, 16#80, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>, encode_ok(-0.0)),
    assert(<<16#FB, 16#3F, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>, encode_ok(1.0)),
    ok.

%%--------------------------------------------------------------------
%% Appendix A: preferred float encoding (RFC 8949 §3.4.1 / §4.2.1)
%%--------------------------------------------------------------------

appendix_a_preferred_float_encode() ->
    %% Minimum and maximum binary16 subnormals.
    assert(<<16#F9, 16#00, 16#01>>,
           encode_ok_with_opts(5.960464477539063e-8, [{preferred, true}])),
    assert(<<16#F9, 16#03, 16#FF>>,
           encode_ok_with_opts(6.097555160522461e-5, [{preferred, true}])),
    %% Minimum binary16 normal.
    assert(<<16#F9, 16#04, 16#00>>,
           encode_ok_with_opts(6.103515625e-5, [{preferred, true}])),
    %% Half-precision: 1.0 -> F9 3C00
    assert(<<16#F9, 16#3C, 16#00>>,
           encode_ok_with_opts(1.0, [{preferred, true}])),
    %% Half-precision: 0.0 -> F9 0000
    assert(<<16#F9, 16#00, 16#00>>,
           encode_ok_with_opts(0.0, [{preferred, true}])),
    %% Half-precision: -0.0 -> F9 8000
    assert(<<16#F9, 16#80, 16#00>>,
           encode_ok_with_opts(-0.0, [{preferred, true}])),
    %% Half-precision: 1.5 -> F9 3E00
    assert(<<16#F9, 16#3E, 16#00>>,
           encode_ok_with_opts(1.5, [{preferred, true}])),
    %% Half-precision: 65504.0 -> F9 7BFF
    assert(<<16#F9, 16#7B, 16#FF>>,
           encode_ok_with_opts(65504.0, [{preferred, true}])),
    %% Values just outside exact binary16 representation use binary32.
    <<16#FA, _/binary>> =
        encode_ok_with_opts(2.9802322387695312e-8, [{preferred, true}]),
    <<16#FA, _/binary>> =
        encode_ok_with_opts(65520.0, [{preferred, true}]),
    %% Single-precision: 16777216.0 (2^24, outside half range) -> FA 4B80 0000
    assert(<<16#FA, 16#4B, 16#80, 16#00, 16#00>>,
           encode_ok_with_opts(16777216.0, [{preferred, true}])),
    %% The adjacent integer is not exactly representable as binary32.
    <<16#FB, _/binary>> =
        encode_ok_with_opts(16777217.0, [{preferred, true}]),
    %% Double-precision: 1.1 needs double
    assert(<<16#FB, 16#3F, 16#F1, 16#99, 16#99, 16#99, 16#99, 16#99, 16#9A>>,
           encode_ok_with_opts(1.1, [{preferred, true}])),
    %% Double-precision: 1.0e300 needs double
    <<H:8, _/binary>> = encode_ok_with_opts(1.0e300, [{preferred, true}]),
    assert(16#FB, H),
    %% Preferred encode + decode roundtrip
    assert(1.0, decode_ok(<<16#F9, 16#3C, 16#00>>)),
    assert(1.5, decode_ok(<<16#F9, 16#3E, 16#00>>)),
    %% Binary32 subnormal boundary and immediately smaller binary64 value.
    <<16#FA, _/binary>> =
        encode_ok_with_opts(1.401298464324817e-45, [{preferred, true}]),
    <<16#FB, _/binary>> =
        encode_ok_with_opts(7.006492321624085e-46, [{preferred, true}]),
    %% Negative half-precision
    assert(<<16#F9, 16#BC, 16#00>>,
           encode_ok_with_opts(-1.0, [{preferred, true}])),
    assert(-1.0, decode_ok(encode_ok_with_opts(-1.0, [{preferred, true}]))),
    ok.

preferred_float_decode_boundaries() ->
    Preferred = [{preferred, true}],
    Deterministic = [{deterministic, true}],
    %% Wider 1.0 encodings are rejected because binary16 is exact.
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(<<16#FA, 16#3F, 16#80, 0, 0>>, Preferred)
    ),
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(
            <<16#FB, 16#3F, 16#F0, 0, 0, 0, 0, 0, 0>>, Preferred
        )
    ),
    %% A binary64 value exactly representable as binary32, but not binary16.
    assert(
        {error, {non_preferred_float, single}},
        avm_cbor:decode(
            <<16#FB, 16#41, 16#2E, 16#84, 16#81, 16#00, 16#00, 16#00, 16#00>>,
            Preferred
        )
    ),
    %% 1.1 is not exactly representable at either narrower width.
    assert(
        {ok, 1.1, <<>>},
        avm_cbor:decode(
            <<16#FB, 16#3F, 16#F1, 16#99, 16#99, 16#99, 16#99, 16#99, 16#9A>>,
            Preferred
        )
    ),
    %% Signed zero must use binary16 in preferred mode.
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(<<16#FA, 0, 0, 0, 0>>, Preferred)
    ),
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(<<16#FA, 16#80, 0, 0, 0>>, Preferred)
    ),
    %% Erlang cannot represent non-finite values.  Canonical-width infinities
    %% and NaN remain controlled errors, while wider forms fail preferred mode.
    assert(
        {error, {unsupported_simple_value, invalid_float}},
        avm_cbor:decode(<<16#F9, 16#7C, 0>>, Preferred)
    ),
    assert(
        {error, {unsupported_simple_value, invalid_float}},
        avm_cbor:decode(<<16#F9, 16#FC, 0>>, Preferred)
    ),
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(<<16#FA, 16#7F, 16#80, 0, 0>>, Preferred)
    ),
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(
            <<16#FB, 16#FF, 16#F0, 0, 0, 0, 0, 0, 0>>, Preferred
        )
    ),
    assert(
        {error, {unsupported_simple_value, invalid_float}},
        avm_cbor:decode(<<16#F9, 16#7E, 0>>, Deterministic)
    ),
    assert(
        {error, {unsupported_simple_value, invalid_float}},
        avm_cbor:decode(<<16#F9, 16#7E, 0>>, Preferred)
    ),
    assert(
        {error, {non_deterministic_nan, 16#7E00}},
        avm_cbor:decode(<<16#F9, 16#7E, 1>>, Deterministic)
    ),
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:decode(<<16#FA, 16#7F, 16#C0, 0, 0>>, Deterministic)
    ),
    %% Partial validation applies exactly the same preferred-width rules.
    assert(
        {error, {non_preferred_float, half}},
        avm_cbor:partial_decode(<<16#FA, 16#3F, 16#80, 0, 0>>, Preferred)
    ),
    %% Preferred checks also accept every already-shortest argument boundary.
    assert({ok, 24, <<>>}, avm_cbor:decode(<<16#18, 24>>, Preferred)),
    assert({ok, 256, <<>>}, avm_cbor:decode(<<16#19, 1, 0>>, Preferred)),
    assert({ok, 65536, <<>>}, avm_cbor:decode(<<16#1A, 0, 1, 0, 0>>, Preferred)),
    assert(
        {ok, 16#100000000, <<>>},
        avm_cbor:decode(<<16#1B, 0, 0, 0, 1, 0, 0, 0, 0>>, Preferred)
    ),
    assert({ok, 1.0, <<>>}, avm_cbor:decode(<<16#F9, 16#3C, 0>>, Preferred)),
    assert({ok, {simple, 24}, <<>>}, avm_cbor:decode(<<16#F8, 24>>, Preferred)),
    ok.

core_deterministic_decode() ->
    Deterministic = [{deterministic, true}],
    assert(
        {ok, {map, [{1, 0}, {2, 0}]}, <<>>},
        avm_cbor:decode(<<16#A2, 1, 0, 2, 0>>, Deterministic)
    ),
    assert(
        {error, non_deterministic_map_order},
        avm_cbor:decode(<<16#A2, 2, 0, 1, 0>>, Deterministic)
    ),
    assert(
        {error, duplicate_map_key},
        avm_cbor:decode(<<16#A2, 1, 0, 1, 1>>, Deterministic)
    ),
    assert(
        {error, non_deterministic_indefinite},
        avm_cbor:decode(<<16#9F, 1, 16#FF>>, Deterministic)
    ),
    ok.
