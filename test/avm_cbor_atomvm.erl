-module(avm_cbor_atomvm).
-export([start/0]).

start() ->
    try run_tests() of
        ok -> io:format("~n=== all atomvm tests passed ===~n", [])
    catch
        error:{assert_failed, Exp, Got} ->
            io:format("FAIL: expected ~p got ~p~n", [Exp, Got]),
            erlang:halt(1);
        Class:Reason ->
            io:format("CRASH: ~p:~p~n", [Class, Reason]),
            erlang:halt(1)
    end.

run_tests() ->
    io:format("~n=== avm_cbor atomvm tests ===~n~n", []),
    %% Decode unsigned integers
    test("decode uint 0",          avm_cbor:decode(<<16#00>>),                {ok, 0, <<>>}),
    test("decode uint 1",          avm_cbor:decode(<<16#01>>),                {ok, 1, <<>>}),
    test("decode uint 100",        avm_cbor:decode(<<16#18, 16#64>>),         {ok, 100, <<>>}),
    test("decode uint 1000",       avm_cbor:decode(<<16#19, 16#03, 16#E8>>),  {ok, 1000, <<>>}),
    %% Decode negative integers
    test("decode negint -1",       avm_cbor:decode(<<16#20>>),                {ok, -1, <<>>}),
    test("decode negint -10",      avm_cbor:decode(<<16#29>>),                {ok, -10, <<>>}),
    test("decode negint -100",     avm_cbor:decode(<<16#38, 16#63>>),         {ok, -100, <<>>}),
    %% Decode byte strings
    test("decode bstr empty",      avm_cbor:decode(<<16#40>>),                {ok, <<>>, <<>>}),
    test("decode bstr data",       avm_cbor:decode(<<16#44, 16#01, 16#02, 16#03, 16#04>>), {ok, <<16#01, 16#02, 16#03, 16#04>>, <<>>}),
    %% Decode text strings
    test("decode tstr empty",      avm_cbor:decode(<<16#60>>),                {ok, {text, <<>>}, <<>>}),
    test("decode tstr a",          avm_cbor:decode(<<16#61, 16#61>>),         {ok, {text, <<"a">>}, <<>>}),
    %% Decode arrays
    test("decode array empty",     avm_cbor:decode(<<16#80>>),                {ok, [], <<>>}),
    test("decode array 1,2,3",     avm_cbor:decode(<<16#83, 16#01, 16#02, 16#03>>), {ok, [1, 2, 3], <<>>}),
    %% Decode maps
    test("decode map empty",       avm_cbor:decode(<<16#A0>>),                {ok, {map, []}, <<>>}),
    test("decode map 1:2,3:4",     avm_cbor:decode(<<16#A2, 16#01, 16#02, 16#03, 16#04>>), {ok, {map, [{1, 2}, {3, 4}]}, <<>>}),
    %% Decode simple values
    test("decode true",            avm_cbor:decode(<<16#F5>>),                {ok, true, <<>>}),
    test("decode false",           avm_cbor:decode(<<16#F4>>),                {ok, false, <<>>}),
    test("decode null",            avm_cbor:decode(<<16#F6>>),                {ok, null, <<>>}),
    test("decode undefined",       avm_cbor:decode(<<16#F7>>),                {ok, undefined, <<>>}),
    %% Decode truncated
    test("decode truncated arr",   avm_cbor:decode(<<16#81>>),                {error, truncated}),
    test("decode truncated map",   avm_cbor:decode(<<16#A1, 16#01>>),         {error, truncated}),
    test("decode empty",           avm_cbor:decode(<<>>),                     {error, empty}),
    %% Encode integers
    test("encode uint 0",          avm_cbor:encode(0),                        {ok, <<16#00>>}),
    test("encode uint 1",          avm_cbor:encode(1),                        {ok, <<16#01>>}),
    test("encode uint 100",        avm_cbor:encode(100),                      {ok, <<16#18, 16#64>>}),
    test("encode negint -1",       avm_cbor:encode(-1),                       {ok, <<16#20>>}),
    test("encode negint -10",      avm_cbor:encode(-10),                      {ok, <<16#29>>}),
    test("encode negint -100",     avm_cbor:encode(-100),                     {ok, <<16#38, 16#63>>}),
    %% Encode strings
    test("encode bstr empty",      avm_cbor:encode(<<>>),                     {ok, <<16#40>>}),
    test("encode tstr empty",      avm_cbor:encode({text, <<>>}),             {ok, <<16#60>>}),
    test("encode tstr hello",      avm_cbor:encode({text, <<"hello">>}),      {ok, <<16#65, 16#68, 16#65, 16#6C, 16#6C, 16#6F>>}),
    %% Encode arrays and maps
    test("encode array empty",     avm_cbor:encode([]),                       {ok, <<16#80>>}),
    test("encode array 1,2",       avm_cbor:encode([1, 2]),                   {ok, <<16#82, 16#01, 16#02>>}),
    test("encode map empty",       avm_cbor:encode({map, []}),                {ok, <<16#A0>>}),
    test("encode map 1:a",         avm_cbor:encode({map, [{1, 2}]}),          {ok, <<16#A1, 16#01, 16#02>>}),
    %% Encode simple values
    test("encode true",            avm_cbor:encode(true),                     {ok, <<16#F5>>}),
    test("encode false",           avm_cbor:encode(false),                    {ok, <<16#F4>>}),
    test("encode null",            avm_cbor:encode(null),                     {ok, <<16#F6>>}),
    test("encode undefined",       avm_cbor:encode(undefined),                {ok, <<16#F7>>}),
    %% Encode simple values
    test("encode simple 0",          avm_cbor:encode({simple, 0}),              {ok, <<16#E0>>}),
    test("encode simple 24",         avm_cbor:encode({simple, 24}),             {ok, <<16#F8, 16#18>>}),
    test("encode simple 31",         avm_cbor:encode({simple, 31}),             {ok, <<16#F8, 16#1F>>}),
    test("encode simple 255",        avm_cbor:encode({simple, 255}),            {ok, <<16#F8, 16#FF>>}),
    %% Encode/decode roundtrip
    test("encode decode roundtrip",  roundtrip({map, [{1, {text, <<"hello">>}}, {2, 42}]}), ok),
    test("roundtrip simple 24",      roundtrip({simple, 24}),                   ok),
    test("roundtrip simple 31",      roundtrip({simple, 31}),                   ok),
    %% Tags
    test("decode tag 1 uint",        avm_cbor:decode(<<16#C1, 16#01>>),         {ok, {tag, 1, 1}, <<>>}),
    test("decode tag 32 uint",       avm_cbor:decode(<<16#D8, 16#20, 16#01>>),  {ok, {tag, 32, 1}, <<>>}),
    test("decode tag 1 array",       avm_cbor:decode(<<16#C1, 16#81, 16#01>>),  {ok, {tag, 1, [1]}, <<>>}),
    test("decode tag with opts",     avm_cbor:decode(<<16#C1, 16#01>>, [{allow_tags, false}]), {error, {unsupported_tag, 1}}),
    test("encode tag 1",             avm_cbor:encode({tag, 1, 2}),              {ok, <<16#C1, 16#02>>}),
    test("encode tag 32",            avm_cbor:encode({tag, 32, 1}),             {ok, <<16#D8, 16#20, 16#01>>}),
    test("encode tag tstr",          avm_cbor:encode({tag, 1, {text, <<"a">>}}), {ok, <<16#C1, 16#61, 16#61>>}),
    %% Half-precision float
    test("decode half 0.0",          avm_cbor:decode(<<16#F9, 16#00, 16#00>>),  {ok, 0.0, <<>>}),
    test("decode half -0.0",         avm_cbor:decode(<<16#F9, 16#80, 16#00>>),  {ok, -0.0, <<>>}),
    test("decode half 1.0",          avm_cbor:decode(<<16#F9, 16#3C, 16#00>>),  {ok, 1.0, <<>>}),
    test("decode half 1.5",          avm_cbor:decode(<<16#F9, 16#3E, 16#00>>),  {ok, 1.5, <<>>}),
    test("decode half 65504",        avm_cbor:decode(<<16#F9, 16#7B, 16#FF>>),  {ok, 65504.0, <<>>}),
    test("decode half subnormal",    avm_cbor:decode(<<16#F9, 16#00, 16#01>>),  {ok, 5.960464477539063e-8, <<>>}),
    test("decode half nofloats",     avm_cbor:decode(<<16#F9, 16#3C, 16#00>>, [{allow_floats, false}]), {error, floats_not_allowed}),
    test("encode min half subnormal", avm_cbor:encode(5.960464477539063e-8, [{preferred, true}]), {ok, <<16#F9, 16#00, 16#01>>}),
    test("preferred rejects f32 half", avm_cbor:decode(<<16#FA, 16#3F, 16#80, 0, 0>>, [{preferred, true}]), {error, {non_preferred_float, half}}),
    test("preferred rejects f64 half", avm_cbor:decode(<<16#FB, 16#3F, 16#F0, 0, 0, 0, 0, 0, 0>>, [{preferred, true}]), {error, {non_preferred_float, half}}),
    test("deterministic rejects noncanonical nan", avm_cbor:decode(<<16#F9, 16#7E, 16#01>>, [{deterministic, true}]), {error, {non_deterministic_nan, 16#7E00}}),
    test("deterministic sorted map", avm_cbor:decode(<<16#A2, 1, 0, 2, 0>>, [{deterministic, true}]), {ok, {map, [{1, 0}, {2, 0}]}, <<>>}),
    test("deterministic unsorted map", avm_cbor:decode(<<16#A2, 2, 0, 1, 0>>, [{deterministic, true}]), {error, non_deterministic_map_order}),
    test("deterministic duplicate map key", avm_cbor:decode(<<16#A2, 1, 0, 1, 1>>, [{deterministic, true}]), {error, duplicate_map_key}),
    test("deterministic rejects indef", avm_cbor:decode(<<16#9F, 1, 16#FF>>, [{deterministic, true}]), {error, non_deterministic_indefinite}),
    %% Indefinite-length
    test("decode indef bstr",        avm_cbor:decode(<<16#5F, 16#41, 16#01, 16#41, 16#02, 16#FF>>), {ok, <<16#01, 16#02>>, <<>>}),
    test("decode indef empty arr",   avm_cbor:decode(<<16#9F, 16#FF>>),          {ok, [], <<>>}),
    test("decode indef arr 1,2",     avm_cbor:decode(<<16#9F, 16#01, 16#02, 16#FF>>), {ok, [1, 2], <<>>}),
    test("decode indef empty map",   avm_cbor:decode(<<16#BF, 16#FF>>),          {ok, {map, []}, <<>>}),
    test("decode indef map 1:2",     avm_cbor:decode(<<16#BF, 16#01, 16#02, 16#FF>>), {ok, {map, [{1, 2}]}, <<>>}),
    test("decode indef disallowed",  avm_cbor:decode(<<16#9F, 16#01, 16#FF>>, [{allow_indefinite, false}]), {error, indefinite_length_unsupported}),
    test("decode indef bstr chunk cap", avm_cbor:decode(<<16#5F, 16#40, 16#40, 16#40, 16#FF>>, [{max_items, 2}]), {error, {max_items_exceeded, 2}}),
    test("decode indef tstr chunk cap", avm_cbor:decode(<<16#7F, 16#60, 16#60, 16#60, 16#FF>>, [{max_items, 2}]), {error, {max_items_exceeded, 2}}),
    %% CBOR sequence
    test("decode all empty",         avm_cbor:decode_all(<<>>),                 {ok, []}),
    test("decode all three",         avm_cbor:decode_all(<<16#01, 16#02, 16#03>>), {ok, [1, 2, 3]}),
    test("decode all item cap",      avm_cbor:decode_all(<<16#01, 16#02, 16#03>>, [{max_items, 2}]), {error, {max_items_exceeded, 2}}),
    test("decode seq empty",         avm_cbor:decode_sequence(<<>>),            {ok, [], <<>>}),
    test("decode seq one",           avm_cbor:decode_sequence(<<16#01>>),       {ok, [1], <<>>}),
    test("decode seq trailing",      avm_cbor:decode_sequence(<<1, 2, 16#82, 3>>), {ok, [1, 2], <<16#82, 3>>}),
    test("decode seq item cap",      avm_cbor:decode_sequence(<<1, 2, 3>>, [{max_items, 2}]), {error, {max_items_exceeded, 2}}),
    test("decode global nested cap", avm_cbor:decode(<<16#82, 16#82, 1, 2, 16#82, 3, 4>>, [{max_items, 6}]), {error, {max_items_exceeded, 6}}),
    test("decode global nested exact", avm_cbor:decode(<<16#82, 16#82, 1, 2, 16#82, 3, 4>>, [{max_items, 7}]), {ok, [[1, 2], [3, 4]], <<>>}),
    test("decode cumulative strings", avm_cbor:decode(<<16#83, 16#41, $a, 16#41, $b, 16#41, $c>>, [{max_items, 4}, {max_total_string_bytes, 2}]), {error, {max_total_string_bytes_exceeded, 2}}),
    %% UTF-8 validation
    test("utf8 valid ascii",         avm_cbor:decode(<<16#61, 16#61>>),          {ok, {text, <<"a">>}, <<>>}),
    test("utf8 valid 2byte",         avm_cbor:decode(<<16#62, 16#C2, 16#A9>>),   {ok, {text, <<16#C2, 16#A9>>}, <<>>}),
    test("utf8 invalid trail",       avm_cbor:decode(<<16#61, 16#80>>),          {error, invalid_utf8}),
    test("utf8 invalid overlong",    avm_cbor:decode(<<16#62, 16#C0, 16#80>>),   {error, invalid_utf8}),
    test("utf8 invalid surrogate",   avm_cbor:decode(<<16#63, 16#ED, 16#A0, 16#80>>), {error, invalid_utf8}),
    test("utf8 invalid 0xFF",        avm_cbor:decode(<<16#61, 16#FF>>),          {error, invalid_utf8}),
    %% Encode UTF-8 validation
    test("encode utf8 valid",        avm_cbor:encode({text, <<"hello">>}),       {ok, <<16#65, 16#68, 16#65, 16#6C, 16#6C, 16#6F>>}),
    test("encode utf8 invalid",      avm_cbor:encode({text, <<16#FF>>}),         {error, invalid_utf8}),
    test("encode utf8 overlong",     avm_cbor:encode({text, <<16#C0, 16#80>>}),  {error, invalid_utf8}),
    test("encode utf8 surrogate",    avm_cbor:encode({text, <<16#ED, 16#A0, 16#80>>}), {error, invalid_utf8}),
    %% Normalized option state and last-duplicate-wins behavior
    test("opts default decode",       avm_cbor:decode(<<16#82, 1, 2>>, []),       {ok, [1, 2], <<>>}),
    test("opts duplicate tags on",    avm_cbor:decode(<<16#C1, 1>>, [{allow_tags, false}, {allow_tags, true}]), {ok, {tag, 1, 1}, <<>>}),
    test("opts duplicate tags off",   avm_cbor:decode(<<16#C1, 1>>, [{allow_tags, true}, {allow_tags, false}]), {error, {unsupported_tag, 1}}),
    test("opts duplicate limit",      avm_cbor:decode(<<16#82, 1, 2>>, [{max_items, 1}, {max_items, 3}]), {ok, [1, 2], <<>>}),
    test("opts duplicate preferred",  avm_cbor:decode(<<16#18, 23>>, [{preferred, false}, {preferred, true}]), {error, {non_preferred_argument, 23}}),
    test("opts improper list",        avm_cbor:decode(<<1>>, [{max_depth, 8} | invalid_tail]), {error, invalid_options_list}),
    test("opts zero bytes rejected",  avm_cbor:decode(<<1>>, [{max_bytes, 0}]), {error, {invalid_option, {max_bytes, 0}}}),
    test("opts zero items rejected",  avm_cbor:decode(<<1>>, [{max_items, 0}]), {error, {invalid_option, {max_items, 0}}}),
    test("encode byte cap",           avm_cbor:encode([<<1, 2>>, <<3, 4>>], [{max_bytes, 5}]), {error, {max_bytes_exceeded, 5}}),
    %% Partial decode
    partial_tests(),
    ok.

partial_tests() ->
    test("partial uint type",        partial_type_of(<<16#18, 16#64>>),          unsigned),
    test("partial uint deep",        partial_deep_of(<<16#18, 16#64>>),          {ok, 100}),
    test("partial bstr type",        partial_type_of(<<16#44, 1, 2, 3, 4>>),     bytes),
    test("partial array type",       partial_type_of(<<16#83, 1, 2, 3>>),        array),
    test("partial array deep",       partial_deep_of(<<16#83, 1, 2, 3>>),        {ok, [1, 2, 3]}),
    test("partial map deep",         partial_deep_of(<<16#A1, 1, 2>>),           {ok, {map, [{1, 2}]}}),
    test("partial tag deep",         partial_deep_of(<<16#C1, 16#01>>),          {ok, {tag, 1, 1}}),
    test("partial indef array deep", partial_deep_of(<<16#9F, 1, 2, 16#FF>>),    {ok, [1, 2]}),
    test("partial empty",            avm_cbor:partial_decode(<<>>),              {error, empty}),
    test("partial truncated",        avm_cbor:partial_decode(<<16#82, 16#01>>),  {error, truncated}),
    test("partial duplicate limit",  partial_type_with_opts(<<16#82, 1, 2>>, [{max_items, 1}, {max_items, 3}]), array),
    test("partial bstr chunk cap",    avm_cbor:partial_decode(<<16#5F, 16#40, 16#40, 16#40, 16#FF>>, [{max_items, 2}]), {error, {max_items_exceeded, 2}}),
    test("partial zero bytes rejected", avm_cbor:partial_decode(<<1>>, [{max_bytes, 0}]), {error, {invalid_option, {max_bytes, 0}}}),
    test("partial deterministic unsorted map", avm_cbor:partial_decode(<<16#A2, 2, 0, 1, 0>>, [{deterministic, true}]), {error, non_deterministic_map_order}),
    test("partial deterministic rejects indef", avm_cbor:partial_decode(<<16#9F, 1, 16#FF>>, [{deterministic, true}]), {error, non_deterministic_indefinite}),
    partial_walk_test(),
    ok.

%% Walk a map, skip the middle value, decode the rest.
partial_walk_test() ->
    Bin = <<16#A2, 16#01, 16#42, 1, 2, 16#03, 16#04>>,
    {ok, P, <<>>} = avm_cbor:partial_decode(Bin),
    test("partial walk count",       avm_cbor:partial_count(P),                  2),
    test("partial walk length",      avm_cbor:partial_length(P),                 byte_size(Bin)),
    {ok, C} = avm_cbor:partial_contents(P),
    {ok, K1, R1} = avm_cbor:partial_decode(C),
    test("partial walk key1",        avm_cbor:partial_deep_decode(K1),           {ok, 1}),
    {ok, V1, R2} = avm_cbor:partial_decode(R1),
    test("partial walk skip",        avm_cbor:partial_skip(V1),                  ok),
    test("partial walk skip type",   avm_cbor:partial_type(V1),                  bytes),
    {ok, K2, R3} = avm_cbor:partial_decode(R2),
    test("partial walk key2",        avm_cbor:partial_deep_decode(K2),           {ok, 3}),
    {ok, V2, <<>>} = avm_cbor:partial_decode(R3),
    test("partial walk val2",        avm_cbor:partial_deep_decode(V2),           {ok, 4}),
    ok.

partial_type_of(Bin) ->
    case avm_cbor:partial_decode(Bin) of
        {ok, P, <<>>} -> avm_cbor:partial_type(P);
        Other -> Other
    end.

partial_type_with_opts(Bin, Opts) ->
    case avm_cbor:partial_decode(Bin, Opts) of
        {ok, P, <<>>} -> avm_cbor:partial_type(P);
        Other -> Other
    end.

partial_deep_of(Bin) ->
    case avm_cbor:partial_decode(Bin) of
        {ok, P, <<>>} -> avm_cbor:partial_deep_decode(P);
        Other -> Other
    end.

roundtrip(Val) ->
    case avm_cbor:encode(Val) of
        {ok, Bin} ->
            case avm_cbor:decode(Bin) of
                {ok, Val, <<>>} -> ok;
                {ok, Other, _} -> erlang:error({assert_failed, Val, Other});
                {error, Reason} -> erlang:error({roundtrip_error, Reason})
            end;
        {error, Reason} ->
            erlang:error({encode_error, Reason})
    end.

test(Name, Got, Expected) when Got =:= Expected ->
    io:format("  ~s ... ok~n", [Name]);
test(_Name, Got, Expected) ->
    erlang:error({assert_failed, Expected, Got}).
