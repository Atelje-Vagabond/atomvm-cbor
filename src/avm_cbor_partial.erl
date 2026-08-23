%% Internal helper module for avm_cbor partial/deferred decode.
%%
%% Do not call this module directly; use the avm_cbor:partial_* API.
%% The #cbor_partial{} record is opaque. Callers must use the accessor
%% functions and must not match on the record shape.
-module(avm_cbor_partial).

-include("avm_cbor_opts.hrl").

-export([
    decode/1, decode/2,
    value_bytes/1,
    deep_decode/1,
    skip/1,
    type/1,
    count/1,
    tag_number/1,
    string_size/1,
    item_offset/1,
    item_length/1,
    contents/1,
    map_fold/3,
    array_fold/3,
    select/2,
    map_find/2,
    array_nth/2
]).

%% Opaque partial-decode descriptor.
%%
%% type    - unsigned | negative | bytes | text | array | map | tag |
%%           float | simple
%% offset  - start position of the item in the binary given to decode
%% length  - encoded byte length of the complete item from offset
%% count   - array/map element (pair) count, undefined otherwise
%% tag     - tag number for tags, undefined otherwise
%% size    - content byte length for bytes/text, undefined otherwise
%% hdr_len - encoded header length, used to locate nested contents
%% indef   - true when the item uses indefinite-length encoding
%% bytes   - raw encoded CBOR bytes of the complete item (sub-binary)
%% opts    - merged decode options, reused by deep_decode
%% value   - {some, Term} for scalar types, none for compound types
-record(cbor_partial, {
    type :: atom(),
    offset = 0 :: non_neg_integer(),
    length = 0 :: non_neg_integer(),
    count = undefined :: non_neg_integer() | undefined,
    tag = undefined :: non_neg_integer() | undefined,
    size = undefined :: non_neg_integer() | undefined,
    hdr_len = 1 :: non_neg_integer(),
    indef = false :: boolean(),
    bytes = <<>> :: binary(),
    opts = ?CBOR_PARTIAL_DEFAULT_OPTS :: #cbor_opts{},
    value = none :: none | {some, term()}
}).

%% Dialyzer assumes every record-shaped value satisfies the field types.  This
%% validator deliberately also rejects forged tuples whose fields violate them.
-dialyzer({nowarn_function, valid_partial/1}).
%% Three-bit major types make these fallbacks unreachable through parse/measure,
%% but they remain defensive boundaries for test-only internal calls.
-dialyzer({nowarn_function, parse_definite/6}).
-dialyzer({nowarn_function, measure_value/6}).

%%--------------------------------------------------------------------
%% Public entry points (called through avm_cbor)
%%--------------------------------------------------------------------

decode(Bin) when is_binary(Bin) ->
    decode_normalized(Bin, avm_cbor:new_decode_state(?CBOR_PARTIAL_DEFAULT_OPTS));
decode(_Bin) -> {error, invalid_input}.

decode(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case avm_cbor:normalize_partial_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, OptState} ->
            decode_normalized(Bin, avm_cbor:new_decode_state(OptState))
    end;
decode(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
decode(_Bin, _Opts) ->
    {error, invalid_input}.

decode_normalized(<<>>, _State) ->
    {error, empty};
decode_normalized(Bin, State) ->
    case avm_cbor:check_max_bytes(byte_size(Bin), avm_cbor:decode_opts(State)) of
        ok -> parse(Bin, State);
        {error, _} = Err -> Err
    end.

%%--------------------------------------------------------------------
%% Accessors
%%--------------------------------------------------------------------

value_bytes(Partial = #cbor_partial{bytes = Bytes}) ->
    case valid_partial(Partial) of
        true -> Bytes;
        false -> {error, not_a_partial}
    end;
value_bytes(_) -> {error, not_a_partial}.

deep_decode(Partial = #cbor_partial{value = {some, Val}}) ->
    case valid_partial(Partial) of
        true -> {ok, Val};
        false -> {error, not_a_partial}
    end;
deep_decode(Partial = #cbor_partial{bytes = Bytes, opts = Opts}) ->
    case valid_partial(Partial) of
        false -> {error, not_a_partial};
        true ->
            State = avm_cbor:new_decode_state(Opts),
            case avm_cbor:decode_item(Bytes, State, 0) of
                {ok, Term, <<>>, _State1} -> {ok, Term};
                {ok, _, Rest, _State1} -> {error, {trailing_bytes, byte_size(Rest)}};
                {error, _} = Err -> Err
            end
    end;
deep_decode(_) -> {error, not_a_partial}.

skip(Partial = #cbor_partial{}) ->
    case valid_partial(Partial) of true -> ok; false -> {error, not_a_partial} end;
skip(_) -> {error, not_a_partial}.

type(Partial = #cbor_partial{type = Type}) ->
    case valid_partial(Partial) of true -> Type; false -> {error, not_a_partial} end;
type(_) -> {error, not_a_partial}.

count(Partial = #cbor_partial{count = Count}) ->
    case valid_partial(Partial) of true -> Count; false -> {error, not_a_partial} end;
count(_) -> {error, not_a_partial}.

tag_number(Partial = #cbor_partial{tag = Tag}) ->
    case valid_partial(Partial) of true -> Tag; false -> {error, not_a_partial} end;
tag_number(_) -> {error, not_a_partial}.

string_size(Partial = #cbor_partial{size = Size}) ->
    case valid_partial(Partial) of true -> Size; false -> {error, not_a_partial} end;
string_size(_) -> {error, not_a_partial}.

item_offset(Partial = #cbor_partial{offset = Offset}) ->
    case valid_partial(Partial) of true -> Offset; false -> {error, not_a_partial} end;
item_offset(_) -> {error, not_a_partial}.

item_length(Partial = #cbor_partial{length = Length}) ->
    case valid_partial(Partial) of true -> Length; false -> {error, not_a_partial} end;
item_length(_) -> {error, not_a_partial}.

%% Raw encoded bytes of the elements inside an array, map, or tag.
%% The caller can walk them with repeated decode/1,2 calls.
contents(Partial = #cbor_partial{type = Type, bytes = Bytes, hdr_len = HdrLen, indef = Indef})
  when Type =:= array; Type =:= map; Type =:= tag ->
    case valid_partial(Partial) of
        false -> {error, not_a_partial};
        true ->
            CLen = case Indef of
                false -> byte_size(Bytes) - HdrLen;
                true -> byte_size(Bytes) - HdrLen - 1
            end,
            <<_:HdrLen/binary, Contents:CLen/binary, _/binary>> = Bytes,
            {ok, Contents}
    end;
contents(Partial = #cbor_partial{}) ->
    case valid_partial(Partial) of
        true -> {error, no_contents};
        false -> {error, not_a_partial}
    end;
contents(_) -> {error, not_a_partial}.

%%--------------------------------------------------------------------
%% Single-pass container traversal
%%--------------------------------------------------------------------

map_fold(Partial, Fun, Acc) when is_function(Fun, 3) ->
    case traversal_start(Partial, map) of
        {ok, Count, Bin, State, Offset, Opts} ->
            fold_map(Count, Bin, State, Offset, Opts, Fun, Acc);
        {error, _} = Err -> Err
    end;
map_fold(Partial, _Fun, _Acc) ->
    case valid_partial(Partial) of
        true -> {error, invalid_callback};
        false -> {error, not_a_partial}
    end.

array_fold(Partial, Fun, Acc) when is_function(Fun, 2) ->
    case traversal_start(Partial, array) of
        {ok, Count, Bin, State, Offset, Opts} ->
            fold_array(Count, Bin, State, Offset, Opts, Fun, Acc);
        {error, _} = Err -> Err
    end;
array_fold(Partial, _Fun, _Acc) ->
    case valid_partial(Partial) of
        true -> {error, invalid_callback};
        false -> {error, not_a_partial}
    end.

select(Partial, Keys) when is_list(Keys) ->
    case type(Partial) of
        map -> select_keys(Partial, Keys);
        {error, _} = Err -> Err;
        _OtherType -> {error, {expected_partial_type, map}}
    end;
select(Partial, _Keys) ->
    case valid_partial(Partial) of
        true -> {error, invalid_key_list};
        false -> {error, not_a_partial}
    end.

select_keys(_Partial, []) -> {ok, [], []};
select_keys(Partial, Keys) ->
    case unique_requested(Keys, []) of
        {error, _} = Err -> Err;
        Requested ->
            SelectFun = fun(KeyPartial, ValuePartial, {Pending, Found}) ->
                case deep_decode(KeyPartial) of
                    {ok, Key} ->
                        case take_requested(Key, Pending, []) of
                            not_found -> {cont, {Pending, Found}};
                            {found, RequestedKey, Rest} ->
                                NewFound = [{RequestedKey, ValuePartial} | Found],
                                case Rest of
                                    [] -> {halt, {[], NewFound}};
                                    _ -> {cont, {Rest, NewFound}}
                                end
                        end;
                    {error, Reason} ->
                        {halt, {select_error, Reason}}
                end
            end,
            case map_fold(Partial, SelectFun, {Requested, []}) of
                {ok, {select_error, Reason}} -> {error, Reason};
                {ok, {Missing, Found}} -> {ok, lists:reverse(Found), Missing};
                {error, _} = Err -> Err
            end
    end.

map_find(Partial, WantedKey) ->
    FindFun = fun(KeyPartial, ValuePartial, not_found) ->
        case deep_decode(KeyPartial) of
            {ok, Key} when Key =:= WantedKey -> {halt, {found, ValuePartial}};
            {ok, _Key} -> {cont, not_found};
            {error, Reason} -> {halt, {find_error, Reason}}
        end
    end,
    case map_fold(Partial, FindFun, not_found) of
        {ok, {found, ValuePartial}} -> {ok, ValuePartial};
        {ok, not_found} -> {error, not_found};
        {ok, {find_error, Reason}} -> {error, Reason};
        {error, _} = Err -> Err
    end.

array_nth(Partial, Index) when is_integer(Index), Index >= 0 ->
    NthFun = fun(ElementPartial, Current) when Current =:= Index ->
                     {halt, {found, ElementPartial}};
                (_ElementPartial, Current) ->
                     {cont, Current + 1}
             end,
    case array_fold(Partial, NthFun, 0) of
        {ok, {found, ElementPartial}} -> {ok, ElementPartial};
        {ok, _Count} -> {error, {index_out_of_range, Index}};
        {error, _} = Err -> Err
    end;
array_nth(Partial, _Index) ->
    case valid_partial(Partial) of
        true -> {error, invalid_index};
        false -> {error, not_a_partial}
    end.

traversal_start(Partial = #cbor_partial{
    type = Type,
    count = Count,
    bytes = Bytes,
    hdr_len = HdrLen,
    indef = Indef,
    offset = ItemOffset,
    opts = Opts
}, ExpectedType) ->
    case valid_partial(Partial) of
        false -> {error, not_a_partial};
        true when Type =/= ExpectedType ->
            {error, {expected_partial_type, ExpectedType}};
        true ->
            ContentLen = case Indef of
                false -> byte_size(Bytes) - HdrLen;
                true -> byte_size(Bytes) - HdrLen - 1
            end,
            <<_:HdrLen/binary, Content:ContentLen/binary, _/binary>> = Bytes,
            State0 = avm_cbor:new_decode_state(Opts),
            case avm_cbor:consume_node(State0) of
                {ok, State1} ->
                    {ok, Count, Content, State1, ItemOffset + HdrLen, Opts};
                {error, _} = Err -> Err
            end
    end;
traversal_start(_, _ExpectedType) ->
    {error, not_a_partial}.

fold_map(0, <<>>, _State, _Offset, _Opts, _Fun, Acc) -> {ok, Acc};
fold_map(0, _Rest, _State, _Offset, _Opts, _Fun, _Acc) ->
    {error, invalid_partial_contents};
fold_map(Count, Bin, State, Offset, Opts, Fun, Acc) ->
    case parse_at(Bin, State, Offset, Opts) of
        {ok, KeyPartial, Rest1, State1} ->
            ValueOffset = Offset + (byte_size(Bin) - byte_size(Rest1)),
            case parse_at(Rest1, State1, ValueOffset, Opts) of
                {ok, ValuePartial, Rest2, State2} ->
                    case Fun(KeyPartial, ValuePartial, Acc) of
                        {cont, NewAcc} ->
                            NextOffset = ValueOffset +
                                (byte_size(Rest1) - byte_size(Rest2)),
                            fold_map(Count - 1, Rest2, State2, NextOffset,
                                     Opts, Fun, NewAcc);
                        {halt, Result} -> {ok, Result};
                        _ -> {error, invalid_fold_result}
                    end;
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

fold_array(0, <<>>, _State, _Offset, _Opts, _Fun, Acc) -> {ok, Acc};
fold_array(0, _Rest, _State, _Offset, _Opts, _Fun, _Acc) ->
    {error, invalid_partial_contents};
fold_array(Count, Bin, State, Offset, Opts, Fun, Acc) ->
    case parse_at(Bin, State, Offset, Opts) of
        {ok, ElementPartial, Rest, State1} ->
            case Fun(ElementPartial, Acc) of
                {cont, NewAcc} ->
                    NextOffset = Offset + (byte_size(Bin) - byte_size(Rest)),
                    fold_array(Count - 1, Rest, State1, NextOffset,
                               Opts, Fun, NewAcc);
                {halt, Result} -> {ok, Result};
                _ -> {error, invalid_fold_result}
            end;
        {error, _} = Err -> Err
    end.

unique_requested([], Acc) -> lists:reverse(Acc);
unique_requested([Key | Rest], Acc) ->
    case exact_member(Key, Acc) of
        true -> {error, duplicate_requested_key};
        false -> unique_requested(Rest, [Key | Acc])
    end;
unique_requested(_, _Acc) -> {error, invalid_key_list}.

exact_member(_Key, []) -> false;
exact_member(Key, [Key1 | _]) when Key =:= Key1 -> true;
exact_member(Key, [_ | Rest]) -> exact_member(Key, Rest).

take_requested(_Key, [], _Prefix) -> not_found;
take_requested(Key, [RequestedKey | Rest], Prefix) when Key =:= RequestedKey ->
    {found, RequestedKey, reverse_append(Prefix, Rest)};
take_requested(Key, [RequestedKey | Rest], Prefix) ->
    take_requested(Key, Rest, [RequestedKey | Prefix]).

reverse_append([], Tail) -> Tail;
reverse_append([Item | Rest], Tail) -> reverse_append(Rest, [Item | Tail]).

valid_partial(#cbor_partial{
    type = Type,
    offset = Offset,
    length = Length,
    count = Count,
    tag = Tag,
    size = Size,
    hdr_len = HdrLen,
    indef = Indef,
    bytes = Bytes,
    opts = Opts,
    value = Value
}) ->
    valid_type(Type) andalso
    is_integer(Offset) andalso Offset >= 0 andalso
    is_integer(Length) andalso Length >= 1 andalso
    valid_count(Type, Count) andalso
    valid_optional_non_neg(Tag) andalso
    valid_optional_non_neg(Size) andalso
    is_integer(HdrLen) andalso HdrLen >= 1 andalso HdrLen =< Length andalso
    (Indef =:= true orelse Indef =:= false) andalso
    is_binary(Bytes) andalso byte_size(Bytes) =:= Length andalso
    (Indef =:= false orelse Length > HdrLen) andalso
    is_record(Opts, cbor_opts) andalso
    (Value =:= none orelse (is_tuple(Value) andalso tuple_size(Value) =:= 2 andalso
                            element(1, Value) =:= some));
valid_partial(_) -> false.

valid_type(unsigned) -> true;
valid_type(negative) -> true;
valid_type(bytes) -> true;
valid_type(text) -> true;
valid_type(array) -> true;
valid_type(map) -> true;
valid_type(tag) -> true;
valid_type(float) -> true;
valid_type(simple) -> true;
valid_type(_) -> false.

valid_count(array, Count) -> is_integer(Count) andalso Count >= 0;
valid_count(map, Count) -> is_integer(Count) andalso Count >= 0;
valid_count(_Type, Count) -> Count =:= undefined.

valid_optional_non_neg(undefined) -> true;
valid_optional_non_neg(Value) -> is_integer(Value) andalso Value >= 0.

%%--------------------------------------------------------------------
%% Options
%%--------------------------------------------------------------------

%% Enforce both the shared max_string_bytes limit and the
%% partial-specific max_string_size limit.
check_string_limits(N, Opts) ->
    case avm_cbor:check_string_byte_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case Opts#cbor_opts.max_string_size of
                Limit when N > Limit -> {error, {max_string_size_exceeded, Limit}};
                _ -> ok
            end
    end.

%%--------------------------------------------------------------------
%% Top-level parse: build a descriptor for the first item
%%--------------------------------------------------------------------

parse(Bin, State) ->
    Opts = avm_cbor:decode_opts(State),
    case parse_item(Bin, State) of
        {ok, Desc, Rest, _State1} ->
            Len = byte_size(Bin) - byte_size(Rest),
            <<Bytes:Len/binary, _/binary>> = Bin,
            {ok, Desc#cbor_partial{
                offset = 0,
                length = Len,
                bytes = Bytes,
                opts = Opts
            }, Rest};
        {error, _} = Err -> Err
    end.

parse_at(Bin, State, Offset, Opts) ->
    case parse_item(Bin, State) of
        {ok, Desc, Rest, State1} ->
            Len = byte_size(Bin) - byte_size(Rest),
            <<Bytes:Len/binary, _/binary>> = Bin,
            {ok, Desc#cbor_partial{
                offset = Offset,
                length = Len,
                bytes = Bytes,
                opts = Opts
            }, Rest, State1};
        {error, _} = Err -> Err
    end.

parse_item(<<>>, _State) -> {error, truncated};
parse_item(Bin, State) ->
    case avm_cbor:consume_node(State) of
        {ok, State1} -> parse_charged_item(Bin, State1);
        {error, _} = Err -> Err
    end.

parse_charged_item(<<First:8, Rest/binary>>, State) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    Opts = avm_cbor:decode_opts(State),
    case AddInfo of
        31 ->
            case MajorType of
                Type when Type >= 2, Type =< 5 ->
                    case avm_cbor:requires_deterministic_decode(Opts) of
                        true -> {error, non_deterministic_indefinite};
                        false -> parse_indefinite(Type, Rest, State)
                    end;
                7 -> {error, unexpected_break};
                _ -> {error, indefinite_length_unsupported}
            end;
        _ ->
            case avm_cbor:arg(AddInfo, Rest) of
                {ok, Arg, Rest2} ->
                    PreferredResult = case AddInfo < 24 of
                        true -> ok;
                        false -> avm_cbor:check_preferred(MajorType, AddInfo, Arg, Opts)
                    end,
                    case PreferredResult of
                        ok ->
                            HdrLen = 1 + (byte_size(Rest) - byte_size(Rest2)),
                            parse_definite(MajorType, AddInfo, Arg, HdrLen, Rest2, State);
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end
    end.

parse_definite(0, _AddInfo, Arg, HdrLen, Rest, State) ->
    {ok, #cbor_partial{type = unsigned, hdr_len = HdrLen, value = {some, Arg}},
     Rest, State};
parse_definite(1, _AddInfo, Arg, HdrLen, Rest, State) ->
    {ok, #cbor_partial{type = negative, hdr_len = HdrLen, value = {some, -1 - Arg}},
     Rest, State};
parse_definite(2, _AddInfo, N, HdrLen, Rest, State) ->
    case skip_string(N, Rest, State) of
        {ok, Rest2, State1} ->
            {ok, #cbor_partial{type = bytes, size = N, hdr_len = HdrLen}, Rest2, State1};
        {error, _} = Err -> Err
    end;
parse_definite(3, _AddInfo, N, HdrLen, Rest, State) ->
    case skip_text(N, Rest, State) of
        {ok, Rest2, State1} ->
            {ok, #cbor_partial{type = text, size = N, hdr_len = HdrLen}, Rest2, State1};
        {error, _} = Err -> Err
    end;
parse_definite(4, _AddInfo, N, HdrLen, Rest, State) ->
    case measure_array(N, Rest, State, 0) of
        {ok, Rest2, State1} ->
            {ok, #cbor_partial{type = array, count = N, hdr_len = HdrLen}, Rest2, State1};
        {error, _} = Err -> Err
    end;
parse_definite(5, _AddInfo, N, HdrLen, Rest, State) ->
    case measure_map(N, Rest, State, 0) of
        {ok, Rest2, State1} ->
            {ok, #cbor_partial{type = map, count = N, hdr_len = HdrLen}, Rest2, State1};
        {error, _} = Err -> Err
    end;
parse_definite(6, _AddInfo, Tag, HdrLen, Rest, State) ->
    case measure_tag(Tag, Rest, State, 0) of
        {ok, Rest2, State1} ->
            {ok, #cbor_partial{type = tag, tag = Tag, hdr_len = HdrLen}, Rest2, State1};
        {error, _} = Err -> Err
    end;
parse_definite(7, AddInfo, Arg, HdrLen, Rest, State) ->
    Opts = avm_cbor:decode_opts(State),
    case avm_cbor:simple(AddInfo, Arg, Rest, Opts) of
        {ok, Val, Rest2} ->
            Type = case AddInfo of
                25 -> float;
                26 -> float;
                27 -> float;
                _ -> simple
            end,
            {ok, #cbor_partial{type = Type, hdr_len = HdrLen, value = {some, Val}},
             Rest2, State};
        {error, _} = Err -> Err
    end;
parse_definite(MajorType, _AddInfo, _Arg, _HdrLen, _Rest, _State) ->
    {error, {unsupported_major_type, MajorType}}.

parse_indefinite(2, Rest, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_bstr_chunks(Rest, State, 0) of
                {ok, Size, Rest2, State1} ->
                    {ok, #cbor_partial{type = bytes, size = Size, hdr_len = 1, indef = true},
                     Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
parse_indefinite(3, Rest, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_tstr_chunks(Rest, State, 0) of
                {ok, Size, Rest2, State1} ->
                    {ok, #cbor_partial{type = text, size = Size, hdr_len = 1, indef = true},
                     Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
parse_indefinite(4, Rest, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_indefinite_depth(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_indef_items(Rest, State, 1, 0) of
                {ok, Count, Rest2, State1} ->
                    {ok, #cbor_partial{type = array, count = Count, hdr_len = 1, indef = true},
                     Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
parse_indefinite(5, Rest, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_indefinite_depth(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_indef_pairs(Rest, State, 1, 0) of
                {ok, Count, Rest2, State1} ->
                    {ok, #cbor_partial{type = map, count = Count, hdr_len = 1, indef = true},
                     Rest2, State1};
                {error, _} = Err -> Err
            end
    end.
check_indefinite(Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
        false -> {error, indefinite_length_unsupported};
        true -> ok
    end.

check_indefinite_depth(Opts) ->
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok -> avm_cbor:check_depth(1, Opts)
    end.

%%--------------------------------------------------------------------
%% Measuring walker: skip one encoded item without allocating values
%%--------------------------------------------------------------------

measure(<<>>, _State, _Depth) -> {error, truncated};
measure(Bin, State, Depth) ->
    case avm_cbor:consume_node(State) of
        {ok, State1} -> measure_charged(Bin, State1, Depth);
        {error, _} = Err -> Err
    end.

measure_charged(<<First:8, Rest/binary>>, State, Depth) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    Opts = avm_cbor:decode_opts(State),
    case AddInfo of
        31 ->
            case MajorType of
                Type when Type >= 2, Type =< 5 ->
                    case avm_cbor:requires_deterministic_decode(Opts) of
                        true -> {error, non_deterministic_indefinite};
                        false -> measure_indefinite(Type, Rest, State, Depth, Opts)
                    end;
                7 -> {error, unexpected_break};
                _ -> {error, indefinite_length_unsupported}
            end;
        _ ->
            case avm_cbor:arg(AddInfo, Rest) of
                {ok, Arg, Rest2} ->
                    PreferredResult = case AddInfo < 24 of
                        true -> ok;
                        false -> avm_cbor:check_preferred(MajorType, AddInfo, Arg, Opts)
                    end,
                    case PreferredResult of
                        ok -> measure_value(MajorType, AddInfo, Arg, Rest2, State, Depth);
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end
    end.

measure_indefinite(2, Rest, State, _Depth, Opts) ->
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_bstr_chunks(Rest, State, 0) of
                {ok, _Size, Rest2, State1} -> {ok, Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
measure_indefinite(3, Rest, State, _Depth, Opts) ->
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok ->
            case measure_tstr_chunks(Rest, State, 0) of
                {ok, _Size, Rest2, State1} -> {ok, Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
measure_indefinite(4, Rest, State, Depth, Opts) ->
    case measure_indef_container(Rest, Opts, Depth) of
        {error, _} = Err -> Err;
        ok ->
            case measure_indef_items(Rest, State, Depth + 1, 0) of
                {ok, _Count, Rest2, State1} -> {ok, Rest2, State1};
                {error, _} = Err -> Err
            end
    end;
measure_indefinite(5, Rest, State, Depth, Opts) ->
    case measure_indef_container(Rest, Opts, Depth) of
        {error, _} = Err -> Err;
        ok ->
            case measure_indef_pairs(Rest, State, Depth + 1, 0) of
                {ok, _Count, Rest2, State1} -> {ok, Rest2, State1};
                {error, _} = Err -> Err
            end
    end.

measure_indef_container(_Rest, Opts, Depth) ->
    case check_indefinite(Opts) of
        {error, _} = Err -> Err;
        ok -> avm_cbor:check_depth(Depth + 1, Opts)
    end.

measure_value(0, _AddInfo, _Arg, Rest, State, _Depth) -> {ok, Rest, State};
measure_value(1, _AddInfo, _Arg, Rest, State, _Depth) -> {ok, Rest, State};
measure_value(2, _AddInfo, N, Rest, State, _Depth) -> skip_string(N, Rest, State);
measure_value(3, _AddInfo, N, Rest, State, _Depth) -> skip_text(N, Rest, State);
measure_value(4, _AddInfo, N, Rest, State, Depth) -> measure_array(N, Rest, State, Depth);
measure_value(5, _AddInfo, N, Rest, State, Depth) -> measure_map(N, Rest, State, Depth);
measure_value(6, _AddInfo, Tag, Rest, State, Depth) -> measure_tag(Tag, Rest, State, Depth);
measure_value(7, AddInfo, Arg, Rest, State, _Depth) ->
    Opts = avm_cbor:decode_opts(State),
    case avm_cbor:simple(AddInfo, Arg, Rest, Opts) of
        {ok, _Val, Rest2} -> {ok, Rest2, State};
        {error, _} = Err -> Err
    end;
measure_value(MajorType, _AddInfo, _Arg, _Rest, _State, _Depth) ->
    {error, {unsupported_major_type, MajorType}}.

skip_string(N, Bin, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_string_limits(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<_:N/binary, Rest/binary>> = Bin,
                    {ok, Rest, State1};
                {ok, _State1} ->
                    {error, truncated}
            end
    end.

skip_text(N, Bin, State) ->
    Opts = avm_cbor:decode_opts(State),
    case check_string_limits(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<Chunk:N/binary, Rest/binary>> = Bin,
                    case avm_cbor:validate_utf8(Chunk) of
                        ok -> {ok, Rest, State1};
                        {error, _} = Err -> Err
                    end;
                {ok, _State1} ->
                    {error, truncated}
            end
    end.

measure_array(0, Bin, State, _Depth) -> {ok, Bin, State};
measure_array(N, Bin, State, Depth) when N > 0 ->
    Opts = avm_cbor:decode_opts(State),
    case ensure_declared_items(N, Bin, State) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> measure_n_items(N, Bin, State, Depth + 1)
            end
    end.

measure_n_items(0, Bin, State, _Depth) -> {ok, Bin, State};
measure_n_items(N, Bin, State, Depth) ->
    case measure(Bin, State, Depth) of
        {ok, Rest, State1} -> measure_n_items(N - 1, Rest, State1, Depth);
        {error, _} = Err -> Err
    end.

measure_map(0, Bin, State, _Depth) -> {ok, Bin, State};
measure_map(N, Bin, State, Depth) when N > 0 ->
    Opts = avm_cbor:decode_opts(State),
    case ensure_declared_items(N * 2, Bin, State) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok ->
                    case avm_cbor:requires_deterministic_decode(Opts) of
                        true ->
                            measure_n_deterministic_pairs(
                                N, Bin, State, Depth + 1, none);
                        false -> measure_n_pairs(N, Bin, State, Depth + 1)
                    end
            end
    end.

measure_n_pairs(0, Bin, State, _Depth) -> {ok, Bin, State};
measure_n_pairs(N, Bin, State, Depth) ->
    case measure(Bin, State, Depth) of
        {ok, Rest1, State1} ->
            case measure(Rest1, State1, Depth) of
                {ok, Rest2, State2} -> measure_n_pairs(N - 1, Rest2, State2, Depth);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

measure_n_deterministic_pairs(0, Bin, State, _Depth, _PreviousKeyBytes) ->
    {ok, Bin, State};
measure_n_deterministic_pairs(N, Bin, State, Depth, PreviousKeyBytes) ->
    KeyInput = Bin,
    case measure(Bin, State, Depth) of
        {ok, Rest1, State1} ->
            KeyLength = byte_size(KeyInput) - byte_size(Rest1),
            <<KeyBytes:KeyLength/binary, _/binary>> = KeyInput,
            case avm_cbor:check_deterministic_map_key(PreviousKeyBytes, KeyBytes) of
                ok ->
                    case measure(Rest1, State1, Depth) of
                        {ok, Rest2, State2} ->
                            measure_n_deterministic_pairs(
                                N - 1, Rest2, State2, Depth, KeyBytes);
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

measure_tag(Tag, Bin, State, Depth) ->
    Opts = avm_cbor:decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_TAGS) of
        false -> {error, {unsupported_tag, Tag}};
        true ->
            case ensure_declared_items(1, Bin, State) of
                {error, _} = Err -> Err;
                ok ->
                    case avm_cbor:check_depth(Depth + 1, Opts) of
                        {error, _} = Err -> Err;
                        ok -> measure(Bin, State, Depth + 1)
                    end
            end
    end.

ensure_declared_items(Needed, Bin, State) ->
    case avm_cbor:ensure_node_budget(Needed, State) of
        {error, _} = Err -> Err;
        ok ->
            declared_input_check(Needed, Bin)
    end.

declared_input_check(Needed, Bin) when Needed =< byte_size(Bin) -> ok;
declared_input_check(_Needed, <<First:8, _/binary>>) ->
    AddInfo = First band 16#1F,
    case {First bsr 5, AddInfo} of
        {7, 31} -> ok;
        {_, Value} when Value >= 28, Value =< 30 -> ok;
        _ -> {error, truncated}
    end;
declared_input_check(_Needed, <<>>) -> {error, truncated}.

%%--------------------------------------------------------------------
%% Indefinite-length measuring
%%--------------------------------------------------------------------

measure_bstr_chunks(<<>>, _State, _Size) -> {error, truncated};
measure_bstr_chunks(<<16#FF, Rest/binary>>, State, Size) -> {ok, Size, Rest, State};
measure_bstr_chunks(<<First:8, Rest/binary>>, State, Size) ->
    case avm_cbor:consume_node(State) of
        {error, _} = Err -> Err;
        {ok, State1} ->
            Opts = avm_cbor:decode_opts(State1),
            MajorType = First bsr 5,
            AddInfo = First band 16#1F,
            case MajorType of
                2 when AddInfo =< 27 ->
                    case avm_cbor:arg(AddInfo, Rest) of
                        {ok, N, Rest2} ->
                            NewSize = Size + N,
                            case check_string_limits(NewSize, Opts) of
                                {error, _} = Err -> Err;
                                ok ->
                                    case avm_cbor:consume_string_bytes(N, State1) of
                                        {error, _} = Err -> Err;
                                        {ok, State2} when byte_size(Rest2) >= N ->
                                            <<_:N/binary, Rest3/binary>> = Rest2,
                                            measure_bstr_chunks(Rest3, State2, NewSize);
                                        {ok, _State2} ->
                                            {error, truncated}
                                    end
                            end;
                        {error, _} = Err -> Err
                    end;
                _ ->
                    {error, {invalid_indefinite_chunk, expected_byte_string}}
            end
    end.

measure_tstr_chunks(<<>>, _State, _Size) -> {error, truncated};
measure_tstr_chunks(<<16#FF, Rest/binary>>, State, Size) -> {ok, Size, Rest, State};
measure_tstr_chunks(<<First:8, Rest/binary>>, State, Size) ->
    case avm_cbor:consume_node(State) of
        {error, _} = Err -> Err;
        {ok, State1} ->
            Opts = avm_cbor:decode_opts(State1),
            MajorType = First bsr 5,
            AddInfo = First band 16#1F,
            case MajorType of
                3 when AddInfo =< 27 ->
                    case avm_cbor:arg(AddInfo, Rest) of
                        {ok, N, Rest2} ->
                            NewSize = Size + N,
                            case check_string_limits(NewSize, Opts) of
                                {error, _} = Err -> Err;
                                ok ->
                                    case avm_cbor:consume_string_bytes(N, State1) of
                                        {error, _} = Err -> Err;
                                        {ok, State2} when byte_size(Rest2) >= N ->
                                            <<Chunk:N/binary, Rest3/binary>> = Rest2,
                                            case avm_cbor:validate_utf8(Chunk) of
                                                ok ->
                                                    measure_tstr_chunks(
                                                        Rest3, State2, NewSize);
                                                {error, _} = Err -> Err
                                            end;
                                        {ok, _State2} ->
                                            {error, truncated}
                                    end
                            end;
                        {error, _} = Err -> Err
                    end;
                _ ->
                    {error, {invalid_indefinite_chunk, expected_text_string}}
            end
    end.

measure_indef_items(<<>>, _State, _Depth, _Count) -> {error, truncated};
measure_indef_items(<<16#FF, Rest/binary>>, State, _Depth, Count) ->
    {ok, Count, Rest, State};
measure_indef_items(Bin, State, Depth, Count) ->
    case measure(Bin, State, Depth) of
        {ok, Rest, State1} -> measure_indef_items(Rest, State1, Depth, Count + 1);
        {error, _} = Err -> Err
    end.

measure_indef_pairs(<<>>, _State, _Depth, _Count) -> {error, truncated};
measure_indef_pairs(<<16#FF, Rest/binary>>, State, _Depth, Count) ->
    {ok, Count, Rest, State};
measure_indef_pairs(Bin, State, Depth, Count) ->
    case measure(Bin, State, Depth) of
        {ok, Rest1, State1} ->
            case measure(Rest1, State1, Depth) of
                {ok, Rest2, State2} ->
                    measure_indef_pairs(Rest2, State2, Depth, Count + 1);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.
