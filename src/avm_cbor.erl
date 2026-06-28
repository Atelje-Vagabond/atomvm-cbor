-module(avm_cbor).

-export([
    decode/1, decode/2,
    decode_all/1, decode_all/2,
    decode_sequence/1, decode_sequence/2,
    encode/1, encode/2,
    get/2, get/3, require/2,
    as_text/1, as_bytes/1, as_int/1, as_bool/1,
    ble_options/0
]).

-type decode_result() :: {ok, term(), binary()} | {error, term()}.
-type encode_result() :: {ok, binary()} | {error, term()}.

%% Decode one CBOR item.
-spec decode(binary()) -> decode_result().
decode(Bin) -> decode(Bin, default_opts()).

%% Decode one CBOR item with options.
-spec decode(binary(), list()) -> decode_result().
decode(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case validate_opts(Opts) of
        {error, _} = Err -> Err;
        ok ->
            Merged = merge_opts(default_opts(), Opts),
            case Bin of
                <<>> -> {error, empty};
                _ ->
                    Size = byte_size(Bin),
                    case check_max_bytes(Size, Merged) of
                        ok -> decode_item(Bin, Merged, 0);
                        {error, _} = Err -> Err
                    end
            end
    end.

%% Encode one supported value.
-spec encode(term()) -> encode_result().
encode(Val) -> encode(Val, default_opts()).

%% Encode one supported value with options.
-spec encode(term(), list()) -> encode_result().
encode(Val, Opts) when is_list(Opts) ->
    case validate_opts(Opts) of
        {error, _} = Err -> Err;
        ok ->
            Merged = merge_opts(default_opts(), Opts),
            try do_encode(Val, Merged, 0) of
                Bin when is_binary(Bin) ->
                    case check_max_bytes(byte_size(Bin), Merged) of
                        ok -> {ok, Bin};
                        {error, _} = Err -> Err
                    end
            catch
                error:{encode_error, Reason} -> {error, Reason};
                error:function_clause -> {error, {unsupported_value, Val}}
            end
    end.

%%--------------------------------------------------------------------
%% Options
%%--------------------------------------------------------------------

-spec ble_options() -> list().
ble_options() ->
    [
        {max_depth, 8},
        {max_items, 64},
        {max_bytes, 512},
        {max_string_bytes, 128},
        {allow_floats, false},
        {allow_simple, true},
        {allow_tags, false},
        {allow_indefinite, false}
    ].

default_opts() ->
    [
        {max_depth, 128},
        {max_items, 4096},
        {max_bytes, 0},
        {max_string_bytes, 65536},
        {allow_floats, true},
        {allow_simple, true},
        {allow_tags, true},
        {allow_indefinite, true}
    ].

validate_opts([]) -> ok;
validate_opts([{max_depth, V} | Rest]) when is_integer(V), V >= 0 -> validate_opts(Rest);
validate_opts([{max_items, V} | Rest]) when is_integer(V), V >= 0 -> validate_opts(Rest);
validate_opts([{max_bytes, V} | Rest]) when is_integer(V), V >= 0 -> validate_opts(Rest);
validate_opts([{max_string_bytes, V} | Rest]) when is_integer(V), V >= 0 -> validate_opts(Rest);
validate_opts([{allow_floats, V} | Rest]) when V =:= true; V =:= false -> validate_opts(Rest);
validate_opts([{allow_simple, V} | Rest]) when V =:= true; V =:= false -> validate_opts(Rest);
validate_opts([{allow_tags, V} | Rest]) when V =:= true; V =:= false -> validate_opts(Rest);
validate_opts([{allow_indefinite, V} | Rest]) when V =:= true; V =:= false -> validate_opts(Rest);
validate_opts([Bad | _]) -> {error, {invalid_option, Bad}}.

opt(_, []) -> undefined;
opt(Key, [{Key, Val} | _]) -> Val;
opt(Key, [_ | Rest]) -> opt(Key, Rest).

merge_opts(Defaults, Overrides) ->
    fold_merge(Defaults, Overrides).

check_max_bytes(_Size, Opts) ->
    case opt(max_bytes, Opts) of
        0 -> ok;
        Limit when _Size > Limit -> {error, {max_bytes_exceeded, Limit}};
        _ -> ok
    end.

%%--------------------------------------------------------------------
%% CBOR sequence helpers
%%--------------------------------------------------------------------

-spec decode_all(binary()) -> {ok, list()} | {error, term()}.
decode_all(Bin) -> decode_all(Bin, default_opts()).

-spec decode_all(binary(), list()) -> {ok, list()} | {error, term()}.
decode_all(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case validate_opts(Opts) of
        {error, _} = Err -> Err;
        ok ->
            Merged = merge_opts(default_opts(), Opts),
            case Bin of
                <<>> -> {ok, []};
                _ ->
                    Size = byte_size(Bin),
                    case check_max_bytes(Size, Merged) of
                        ok -> decode_all_items(Bin, Merged, []);
                        {error, _} = Err -> Err
                    end
            end
    end.

decode_all_items(<<>>, _, Acc) -> {ok, lists:reverse(Acc)};
decode_all_items(Bin, Opts, Acc) ->
    case decode_item(Bin, Opts, 0) of
        {ok, Item, Rest} -> decode_all_items(Rest, Opts, [Item | Acc]);
        {error, _} = Err -> Err
    end.

-spec decode_sequence(binary()) -> {ok, list(), binary()} | {error, term()}.
decode_sequence(Bin) -> decode_sequence(Bin, default_opts()).

-spec decode_sequence(binary(), list()) -> {ok, list(), binary()} | {error, term()}.
decode_sequence(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case validate_opts(Opts) of
        {error, _} = Err -> Err;
        ok ->
            Merged = merge_opts(default_opts(), Opts),
            case Bin of
                <<>> -> {ok, [], <<>>};
                _ ->
                    Size = byte_size(Bin),
                    case check_max_bytes(Size, Merged) of
                        ok -> decode_sequence_items(Bin, Merged, []);
                        {error, _} = Err -> Err
                    end
            end
    end.

decode_sequence_items(<<>>, _, Acc) ->
    {ok, lists:reverse(Acc), <<>>};
decode_sequence_items(Bin, Opts, Acc) ->
    case decode_item(Bin, Opts, 0) of
        {ok, Item, Rest} ->
            decode_sequence_items(Rest, Opts, [Item | Acc]);
        {error, truncated} ->
            {ok, lists:reverse(Acc), Bin};
        {error, _} = Err ->
            Err
    end.

%%--------------------------------------------------------------------
%% Decode internals
%%--------------------------------------------------------------------

decode_item(<<>>, _, _) -> {error, truncated};
decode_item(<<First:8, Rest/binary>>, Opts, Depth) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case AddInfo of
        31 ->
            case MajorType of
                2 -> indef_byte_string(Rest, Opts, Depth);
                3 -> indef_text_string(Rest, Opts, Depth);
                4 -> indef_array(Rest, Opts, Depth);
                5 -> indef_map(Rest, Opts, Depth);
                7 -> {error, unexpected_break};
                _ -> {error, indefinite_length_unsupported}
            end;
        _ ->
            case arg(AddInfo, Rest) of
                {ok, Arg, Rest2} ->
                    case MajorType of
                        0 -> {ok, Arg, Rest2};
                        1 -> {ok, -1 - Arg, Rest2};
                        2 -> byte_string(Arg, Rest2, Opts);
                        3 -> text_string(Arg, Rest2, Opts);
                        4 -> array(Arg, Rest2, Opts, Depth);
                        5 -> map(Arg, Rest2, Opts, Depth);
                        6 -> tag(Arg, Rest2, Opts, Depth);
                        7 -> simple(AddInfo, Arg, Rest2, Opts);
                        _ -> {error, {unsupported_major_type, MajorType}}
                    end;
                {error, _} = Err -> Err
            end
    end.

arg(AddInfo, Bin) when AddInfo < 24 ->
    {ok, AddInfo, Bin};
arg(24, <<N:8, Rest/binary>>) ->
    {ok, N, Rest};
arg(25, <<N:16, Rest/binary>>) ->
    {ok, N, Rest};
arg(26, <<N:32, Rest/binary>>) ->
    {ok, N, Rest};
arg(27, <<N:64, Rest/binary>>) ->
    {ok, N, Rest};
arg(28, _) -> {error, reserved_additional_info};
arg(29, _) -> {error, reserved_additional_info};
arg(30, _) -> {error, reserved_additional_info};
arg(31, _) -> {error, reserved_additional_info};
arg(_, _) -> {error, truncated}.

byte_string(N, Bin, Opts) when byte_size(Bin) >= N ->
    case check_string_byte_limit(N, Opts) of
        ok ->
            <<Chunk:N/binary, Rest/binary>> = Bin,
            {ok, Chunk, Rest};
        {error, _} = Err -> Err
    end;
byte_string(_, _, _) ->
    {error, truncated}.

text_string(N, Bin, Opts) when byte_size(Bin) >= N ->
    case check_string_byte_limit(N, Opts) of
        ok ->
            <<Chunk:N/binary, Rest/binary>> = Bin,
            case validate_utf8(Chunk) of
                ok -> {ok, {text, Chunk}, Rest};
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end;
text_string(_, _, _) ->
    {error, truncated}.

check_string_byte_limit(N, Opts) ->
    case opt(max_string_bytes, Opts) of
        0 -> ok;
        Limit when N > Limit -> {error, {max_string_bytes_exceeded, Limit}};
        _ -> ok
    end.

array(0, Bin, _, _) -> {ok, [], Bin};
array(N, Bin, Opts, Depth) when N > 0 ->
    case check_item_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> items(N, Bin, Opts, Depth + 1, [])
            end
    end.

items(0, Bin, _, _, Acc) -> {ok, lists:reverse(Acc), Bin};
items(N, Bin, Opts, Depth, Acc) ->
    case decode_item(Bin, Opts, Depth) of
        {ok, Item, Rest} -> items(N - 1, Rest, Opts, Depth, [Item | Acc]);
        {error, _} = Err -> Err
    end.

map(0, Bin, _, _) -> {ok, {map, []}, Bin};
map(N, Bin, Opts, Depth) when N > 0 ->
    case check_item_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> pairs(N, Bin, Opts, Depth + 1, [])
            end
    end.

pairs(0, Bin, _, _, Acc) -> {ok, {map, lists:reverse(Acc)}, Bin};
pairs(N, Bin, Opts, Depth, Acc) ->
    case decode_item(Bin, Opts, Depth) of
        {ok, Key, Rest1} ->
            case decode_item(Rest1, Opts, Depth) of
                {ok, Val, Rest2} ->
                    pairs(N - 1, Rest2, Opts, Depth, [{Key, Val} | Acc]);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

check_item_limit(N, Opts) ->
    case opt(max_items, Opts) of
        0 -> ok;
        Limit when N > Limit -> {error, {max_items_exceeded, Limit}};
        _ -> ok
    end.

check_depth(Depth, Opts) ->
    case opt(max_depth, Opts) of
        0 -> ok;
        Limit when Depth > Limit -> {error, {max_depth_exceeded, Limit}};
        _ -> ok
    end.

simple(AddInfo, _, Bin, Opts) when AddInfo >= 0, AddInfo =< 19 ->
    case opt(allow_simple, Opts) of
        false -> {error, {unsupported_simple_value, AddInfo}};
        _ -> {ok, {simple, AddInfo}, Bin}
    end;
simple(20, _, Bin, _) -> {ok, false, Bin};
simple(21, _, Bin, _) -> {ok, true, Bin};
simple(22, _, Bin, _) -> {ok, null, Bin};
simple(23, _, Bin, _) -> {ok, undefined, Bin};
simple(24, Val, Bin, Opts) ->
    case opt(allow_simple, Opts) of
        false -> {error, {unsupported_simple_value, Val}};
        _ -> {ok, {simple, Val}, Bin}
    end;
simple(25, Val, Bin, Opts) ->
    case opt(allow_floats, Opts) of
        false -> {error, floats_not_allowed};
        true -> decode_half(Val, Bin)
    end;
simple(26, Val, Bin, Opts) ->
    case opt(allow_floats, Opts) of
        false -> {error, floats_not_allowed};
        true ->
            <<F:32/float, _/binary>> = <<Val:32>>,
            {ok, F, Bin}
    end;
simple(27, Val, Bin, Opts) ->
    case opt(allow_floats, Opts) of
        false -> {error, floats_not_allowed};
        true ->
            <<F:64/float, _/binary>> = <<Val:64>>,
            {ok, F, Bin}
    end;
simple(AddInfo, _, _, _) ->
    {error, {unsupported_simple_value, AddInfo}}.

decode_half(Val, Bin) ->
    S = (Val bsr 15) band 1,
    Exp = (Val bsr 10) band 16#1F,
    Mant = Val band 16#3FF,
    if
        Exp == 0, Mant == 0 ->
            if S == 0 -> {ok, 0.0, Bin};
               true -> {ok, -0.0, Bin}
            end;
        Exp == 31, Mant == 0 ->
            {error, {unsupported_simple_value, infinity}};
        Exp == 31 ->
            {error, {unsupported_simple_value, nan}};
        true ->
            Num = case Exp of
                0 -> Mant;
                _ -> 1024 + Mant
            end,
            ExpBias = case Exp of
                0 -> -24;
                _ -> Exp - 25
            end,
            L = leading_bit_pos(Num),
            FExp = ExpBias + L + 127,
            FMant = (Num - (1 bsl L)) bsl (23 - L),
            F32 = (S bsl 31) bor (FExp bsl 23) bor FMant,
            <<F:32/float, _/binary>> = <<F32:32>>,
            {ok, F, Bin}
    end.

%% Tag passthrough

tag(Tag, Bin, Opts, Depth) ->
    case opt(allow_tags, Opts) of
        false -> {error, {unsupported_tag, Tag}};
        true ->
            case decode_item(Bin, Opts, Depth) of
                {ok, Val, Rest} -> {ok, {tag, Tag, Val}, Rest};
                {error, _} = Err -> Err
            end
    end.

%%--------------------------------------------------------------------
%% Indefinite-length items
%%--------------------------------------------------------------------

indef_byte_string(Bin, Opts, Depth) ->
    case opt(allow_indefinite, Opts) of
        false -> {error, indefinite_length_unsupported};
        true -> indef_bstr_chunks(Bin, Opts, Depth, <<>>)
    end.

indef_bstr_chunks(<<>>, _, _, _) -> {error, truncated};
indef_bstr_chunks(<<16#FF, Rest/binary>>, _Opts, _Depth, Acc) -> {ok, Acc, Rest};
indef_bstr_chunks(Bin, Opts, Depth, Acc) ->
    case definite_bstr_chunk(Bin, Opts) of
        {ok, Chunk, Rest} ->
            NewSize = byte_size(Acc) + byte_size(Chunk),
            case check_string_byte_limit(NewSize, Opts) of
                ok -> indef_bstr_chunks(Rest, Opts, Depth, <<Acc/binary, Chunk/binary>>);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

definite_bstr_chunk(<<First:8, Rest/binary>>, Opts) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case MajorType of
        2 when AddInfo < 24 ->
            definite_bstr_body(AddInfo, Rest, Opts);
        2 when AddInfo >= 24, AddInfo =< 27 ->
            case arg(AddInfo, Rest) of
                {ok, N, Rest2} -> definite_bstr_body(N, Rest2, Opts);
                {error, _} = Err -> Err
            end;
        _ ->
            {error, {invalid_indefinite_chunk, expected_byte_string}}
    end;
definite_bstr_chunk(<<>>, _) -> {error, truncated}.

definite_bstr_body(N, Bin, Opts) when byte_size(Bin) >= N ->
    case check_string_byte_limit(N, Opts) of
        ok ->
            <<Chunk:N/binary, Rest/binary>> = Bin,
            {ok, Chunk, Rest};
        {error, _} = Err -> Err
    end;
definite_bstr_body(_, _, _) -> {error, truncated}.

indef_text_string(Bin, Opts, Depth) ->
    case opt(allow_indefinite, Opts) of
        false -> {error, indefinite_length_unsupported};
        true -> indef_tstr_chunks(Bin, Opts, Depth, <<>>)
    end.

indef_tstr_chunks(<<>>, _, _, _) -> {error, truncated};
indef_tstr_chunks(<<16#FF, Rest/binary>>, _Opts, _Depth, Acc) ->
    case validate_utf8(Acc) of
        ok -> {ok, {text, Acc}, Rest};
        {error, _} = Err -> Err
    end;
indef_tstr_chunks(Bin, Opts, Depth, Acc) ->
    case definite_tstr_chunk(Bin, Opts) of
        {ok, Chunk, Rest} ->
            NewSize = byte_size(Acc) + byte_size(Chunk),
            case check_string_byte_limit(NewSize, Opts) of
                ok -> indef_tstr_chunks(Rest, Opts, Depth, <<Acc/binary, Chunk/binary>>);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

definite_tstr_chunk(<<First:8, Rest/binary>>, Opts) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case MajorType of
        3 when AddInfo < 24 ->
            definite_tstr_body(AddInfo, Rest, Opts);
        3 when AddInfo >= 24, AddInfo =< 27 ->
            case arg(AddInfo, Rest) of
                {ok, N, Rest2} -> definite_tstr_body(N, Rest2, Opts);
                {error, _} = Err -> Err
            end;
        _ ->
            {error, {invalid_indefinite_chunk, expected_text_string}}
    end;
definite_tstr_chunk(<<>>, _) -> {error, truncated}.

definite_tstr_body(N, Bin, Opts) when byte_size(Bin) >= N ->
    case check_string_byte_limit(N, Opts) of
        ok ->
            <<Chunk:N/binary, Rest/binary>> = Bin,
            {ok, Chunk, Rest};
        {error, _} = Err -> Err
    end;
definite_tstr_body(_, _, _) -> {error, truncated}.

indef_array(Bin, Opts, Depth) ->
    case opt(allow_indefinite, Opts) of
        false -> {error, indefinite_length_unsupported};
        true ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> indef_items(Bin, Opts, Depth + 1, 0, [])
            end
    end.

indef_items(<<>>, _, _, _, _) -> {error, truncated};
indef_items(<<16#FF, Rest/binary>>, _Opts, _Depth, _Count, Acc) ->
    {ok, lists:reverse(Acc), Rest};
indef_items(Bin, Opts, Depth, Count, Acc) ->
    case check_item_limit(Count + 1, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case decode_item(Bin, Opts, Depth) of
                {ok, Item, Rest} ->
                    indef_items(Rest, Opts, Depth, Count + 1, [Item | Acc]);
                {error, _} = Err -> Err
            end
    end.

indef_map(Bin, Opts, Depth) ->
    case opt(allow_indefinite, Opts) of
        false -> {error, indefinite_length_unsupported};
        true ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> indef_pairs(Bin, Opts, Depth + 1, 0, [])
            end
    end.

indef_pairs(<<>>, _, _, _, _) -> {error, truncated};
indef_pairs(<<16#FF, Rest/binary>>, _Opts, _Depth, _Count, Acc) ->
    {ok, {map, lists:reverse(Acc)}, Rest};
indef_pairs(Bin, Opts, Depth, Count, Acc) ->
    case check_item_limit(Count + 1, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case decode_item(Bin, Opts, Depth) of
                {ok, Key, Rest1} ->
                    case decode_item(Rest1, Opts, Depth) of
                        {ok, Val, Rest2} ->
                            indef_pairs(Rest2, Opts, Depth, Count + 1, [{Key, Val} | Acc]);
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end
    end.

%%--------------------------------------------------------------------
%% Encode internals
%%--------------------------------------------------------------------

do_encode(Val, _Opts, _Depth) when is_integer(Val), Val >= 0 ->
    case Val bsr 63 < 2 of
        true -> encode_header(0, Val);
        false -> erlang:error({encode_error, {integer_out_of_range, Val}})
    end;
do_encode(Val, _Opts, _Depth) when is_integer(Val), Val < 0 ->
    Arg = -1 - Val,
    case Arg bsr 63 < 2 of
        true -> encode_header(1, Arg);
        false -> erlang:error({encode_error, {integer_out_of_range, Val}})
    end;
do_encode(Val, Opts, _Depth) when is_float(Val) ->
    case opt(allow_floats, Opts) of
        false -> erlang:error({encode_error, floats_not_allowed});
        _ -> encode_float(Val)
    end;
do_encode(Val, Opts, _Depth) when is_binary(Val) ->
    Len = byte_size(Val),
    check_string_byte_limit_encode(Len, Opts),
    Hdr = encode_header(2, Len),
    <<Hdr/binary, Val/binary>>;
do_encode({text, Bin}, Opts, _Depth) when is_binary(Bin) ->
    Len = byte_size(Bin),
    check_string_byte_limit_encode(Len, Opts),
    case validate_utf8(Bin) of
        ok ->
            Hdr = encode_header(3, Len),
            <<Hdr/binary, Bin/binary>>;
        {error, invalid_utf8} ->
            erlang:error({encode_error, invalid_utf8})
    end;
do_encode(true, _Opts, _Depth) -> <<16#F5>>;
do_encode(false, _Opts, _Depth) -> <<16#F4>>;
do_encode(null, _Opts, _Depth) -> <<16#F6>>;
do_encode(undefined, _Opts, _Depth) -> <<16#F7>>;
do_encode({simple, N}, Opts, _Depth) when N >= 0, N =< 23 ->
    case opt(allow_simple, Opts) of
        false -> erlang:error({encode_error, simple_values_not_allowed});
        _ -> <<((7 bsl 5) bor N)>>
    end;
do_encode({simple, N}, Opts, _Depth) when N >= 24, N =< 255 ->
    case opt(allow_simple, Opts) of
        false -> erlang:error({encode_error, simple_values_not_allowed});
        _ -> <<((7 bsl 5) bor 24), N>>
    end;
do_encode({tag, Tag, Val}, Opts, Depth) when is_integer(Tag), Tag >= 0 ->
    case Tag bsr 63 < 2 of
        false -> erlang:error({encode_error, {tag_out_of_range, Tag}});
        true ->
            case opt(allow_tags, Opts) of
                false -> erlang:error({encode_error, tags_not_allowed});
                true ->
                    TagHdr = encode_header(6, Tag),
                    ValBin = do_encode(Val, Opts, Depth),
                    <<TagHdr/binary, ValBin/binary>>
            end
    end;
do_encode(Val, Opts, Depth) when is_list(Val) ->
    Len = length(Val),
    check_item_limit_encode(Len, Opts),
    check_depth_encode(Depth + 1, Opts),
    Hdr = encode_header(4, Len),
    Data = fold_encode(Val, Opts, Depth + 1, <<>>),
    <<Hdr/binary, Data/binary>>;
do_encode({map, Pairs}, Opts, Depth) when is_list(Pairs) ->
    Len = length(Pairs),
    check_item_limit_encode(Len, Opts),
    check_depth_encode(Depth + 1, Opts),
    Hdr = encode_header(5, Len),
    Data = fold_encode_pairs(Pairs, Opts, Depth + 1, <<>>),
    <<Hdr/binary, Data/binary>>;
do_encode(Val, _Opts, _Depth) ->
    erlang:error(function_clause, [Val]).

fold_encode([], _Opts, _Depth, Acc) -> Acc;
fold_encode([Item | Rest], Opts, Depth, Acc) ->
    Bin = do_encode(Item, Opts, Depth),
    fold_encode(Rest, Opts, Depth, <<Acc/binary, Bin/binary>>).

fold_encode_pairs([], _Opts, _Depth, Acc) -> Acc;
fold_encode_pairs([{K, V} | Rest], Opts, Depth, Acc) ->
    KBin = do_encode(K, Opts, Depth),
    VBin = do_encode(V, Opts, Depth),
    fold_encode_pairs(Rest, Opts, Depth, <<Acc/binary, KBin/binary, VBin/binary>>).

encode_float(Val) ->
    S = if Val < 0 -> 1;
            Val > 0 -> 0;
            is_float(Val), 1/Val < 0 -> 1;
            true -> 0
        end,
    Abs = abs(Val),
    if Abs == 0.0 ->
        Bits = S bsl 63,
        <<16#FB, Bits:64/integer-big>>;
       true ->
        {Mant, Exp} = norm(Abs, 0),
        BE = Exp + 1023,
        MBits = trunc((Mant - 1.0) * (1 bsl 52)),
        Bits = (S bsl 63) + (BE bsl 52) + MBits,
        <<16#FB, Bits:64/integer-big>>
    end.

norm(Val, Exp) when Val >= 2 -> norm(Val / 2, Exp + 1);
norm(Val, Exp) when Val < 1 -> norm(Val * 2, Exp - 1);
norm(Val, Exp) -> {Val, Exp}.

check_string_byte_limit_encode(N, Opts) ->
    case check_string_byte_limit(N, Opts) of
        ok -> ok;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

check_item_limit_encode(N, Opts) ->
    case check_item_limit(N, Opts) of
        ok -> ok;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

check_depth_encode(Depth, Opts) ->
    case check_depth(Depth, Opts) of
        ok -> ok;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

encode_header(Major, Arg) when Arg >= 0, Arg =< 23 ->
    <<((Major bsl 5) bor Arg)>>;
encode_header(Major, Arg) when Arg =< 255 ->
    <<((Major bsl 5) bor 24), Arg:8>>;
encode_header(Major, Arg) when Arg =< 65535 ->
    <<((Major bsl 5) bor 25), Arg:16>>;
encode_header(Major, Arg) when Arg =< 16#FFFFFFFF ->
    <<((Major bsl 5) bor 26), Arg:32>>;
encode_header(Major, Arg) ->
    <<((Major bsl 5) bor 27), Arg:64>>.

%%--------------------------------------------------------------------
%% UTF-8 validation
%%--------------------------------------------------------------------

validate_utf8(<<>>) -> ok;
validate_utf8(<<B, Rest/binary>>) when B < 16#80 -> validate_utf8(Rest);
validate_utf8(<<B, Rest/binary>>) when B >= 16#C2, B =< 16#DF ->
    case Rest of
        <<C, R2/binary>> when C >= 16#80, C =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<16#E0, Rest/binary>>) ->
    case Rest of
        <<C, D, R2/binary>> when C >= 16#A0, C =< 16#BF, D >= 16#80, D =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<B, Rest/binary>>) when B >= 16#E1, B =< 16#EC ->
    case Rest of
        <<C, D, R2/binary>> when C >= 16#80, C =< 16#BF, D >= 16#80, D =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<16#ED, Rest/binary>>) ->
    case Rest of
        <<C, D, R2/binary>> when C >= 16#80, C =< 16#9F, D >= 16#80, D =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<B, Rest/binary>>) when B >= 16#EE, B =< 16#EF ->
    case Rest of
        <<C, D, R2/binary>> when C >= 16#80, C =< 16#BF, D >= 16#80, D =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<16#F0, Rest/binary>>) ->
    case Rest of
        <<C, D, E, R2/binary>> when C >= 16#90, C =< 16#BF, D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<B, Rest/binary>>) when B >= 16#F1, B =< 16#F3 ->
    case Rest of
        <<C, D, E, R2/binary>> when C >= 16#80, C =< 16#BF, D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(<<16#F4, Rest/binary>>) ->
    case Rest of
        <<C, D, E, R2/binary>> when C >= 16#80, C =< 16#8F, D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF -> validate_utf8(R2);
        _ -> {error, invalid_utf8}
    end;
validate_utf8(_) -> {error, invalid_utf8}.

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

leading_bit_pos(N) -> leading_bit_pos(N, 0).
leading_bit_pos(0, Acc) -> Acc;
leading_bit_pos(N, Acc) when N >= 2 -> leading_bit_pos(N bsr 1, Acc + 1);
leading_bit_pos(_, Acc) -> Acc.

-spec get(term(), {map, list()}) -> {ok, term()} | error.
get(Key, {map, Pairs}) ->
    case keyfind(Key, 1, Pairs) of
        {Key, Val} -> {ok, Val};
        false -> error
    end.

-spec get(term(), {map, list()}, term()) -> term().
get(Key, {map, Pairs}, Default) ->
    case get(Key, {map, Pairs}) of
        {ok, Val} -> Val;
        error -> Default
    end.

-spec require(term(), {map, list()}) -> {ok, term()} | {error, {missing_key, term()}}.
require(Key, {map, Pairs}) ->
    case keyfind(Key, 1, Pairs) of
        {Key, Val} -> {ok, Val};
        false -> {error, {missing_key, Key}}
    end.

-spec as_text(term()) -> {ok, binary()} | {error, bad_type}.
as_text({text, Bin}) when is_binary(Bin) -> {ok, Bin};
as_text(_) -> {error, bad_type}.

-spec as_bytes(term()) -> {ok, binary()} | {error, bad_type}.
as_bytes(Bin) when is_binary(Bin) -> {ok, Bin};
as_bytes(_) -> {error, bad_type}.

-spec as_int(term()) -> {ok, integer()} | {error, bad_type}.
as_int(N) when is_integer(N) -> {ok, N};
as_int(_) -> {error, bad_type}.

-spec as_bool(term()) -> {ok, boolean()} | {error, bad_type}.
as_bool(true) -> {ok, true};
as_bool(false) -> {ok, false};
as_bool(_) -> {error, bad_type}.

%% Private helpers (AtomVM-safe replacements for unavailable lists functions)

fold_merge(Acc, []) -> Acc;
fold_merge(Acc, [{K, _}=Pair | Rest]) ->
    fold_merge(keydelete(K, 1, Acc) ++ [Pair], Rest).

keydelete(_Key, _N, []) -> [];
keydelete(Key, _N, [{Key, _Val} | T]) -> T;
keydelete(Key, N, [H | T]) -> [H | keydelete(Key, N, T)].

keyfind(_Key, _N, []) -> false;
keyfind(Key, N, [H | _T]) when element(N, H) =:= Key -> H;
keyfind(Key, N, [_ | T]) -> keyfind(Key, N, T).
