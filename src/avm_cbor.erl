-module(avm_cbor).

-include("avm_cbor_opts.hrl").

-export([
    decode/1, decode/2,
    decode_start/2, decode_continue/2,
    decode_all/1, decode_all/2,
    decode_sequence/1, decode_sequence/2,
    sequence_fold/3,
    encode/1, encode/2,
    encode_with_size/1, encode_with_size/2,
    encode_sequence/1, encode_sequence/2,
    validate_all/1, validate_all/2,
    partial_decode/1, partial_decode/2,
    partial_value_bytes/1,
    partial_deep_decode/1,
    partial_skip/1,
    partial_type/1,
    partial_count/1,
    partial_tag/1,
    partial_size/1,
    partial_offset/1,
    partial_length/1,
    partial_contents/1,
    partial_map_fold/3,
    partial_array_fold/3,
    partial_select/2,
    partial_map_find/2,
    partial_array_nth/2,
    get/2, get/3, require/2,
    as_text/1, as_bytes/1, as_int/1, as_bool/1,
    ble_options/0
]).

%% Internal exports for avm_cbor_partial only. Not a public API;
%% do not call these from application code.
-export([
    normalize_partial_opts/1,
    new_decode_state/1,
    decode_opts/1,
    consume_node/1,
    ensure_node_budget/2,
    consume_string_bytes/2,
    requires_deterministic_decode/1,
    check_deterministic_map_key/2,
    check_max_bytes/2,
    check_depth/2,
    check_item_limit/2,
    check_string_byte_limit/2,
    check_preferred/4,
    arg/2,
    validate_utf8/1,
    decode_item/3,
    simple/4
]).

-type decode_result() :: {ok, term(), binary()} | {error, term()}.
-type encode_result() :: {ok, binary()} | {error, term()}.

%% Bound the speculative fixed-cost conversion independently of caller options.
%% The default maximum flat array uses exactly 4095 direct children; larger
%% caller-authorized containers retain the ordinary incremental decoder.
-define(FIXED_COST_BATCH_MAX_NODES, 4095).
-define(FIXED_COST_NATIVE_MIN_NODES, 64).

%% Decode one CBOR item.
-spec decode(term()) -> decode_result().
decode(Bin) when is_binary(Bin), byte_size(Bin) =< 4096 ->
    decode_normalized(Bin, ?CBOR_SMALL_INPUT_DEFAULT_DECODE_STATE);
decode(Bin) when is_binary(Bin) ->
    decode_normalized(Bin, ?CBOR_DEFAULT_DECODE_STATE);
decode(_Bin) ->
    {error, invalid_input}.

%% Decode one CBOR item with options.
-spec decode(term(), term()) -> decode_result().
decode(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, OptState} -> decode_normalized(Bin, new_decode_state(OptState))
    end;
decode(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
decode(_Bin, _Opts) ->
    {error, invalid_input}.

%% Start a pure pull-based decode.  The returned continuation is opaque and
%% performs no parsing work until decode_continue/2 is called.
-spec decode_start(term(), term()) -> {ok, term()} | {error, term()}.
decode_start(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, OptState} -> avm_cbor_cont:start(Bin, new_decode_state(OptState))
    end;
decode_start(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
decode_start(_Bin, _Opts) ->
    {error, invalid_input}.

%% Continue for at most Budget explicit parser transitions.  Scheduling and
%% pacing remain the caller's responsibility; the decoder never sleeps/yields.
-spec decode_continue(term(), term()) ->
    {done, term(), binary()} | {more, term()} | {error, term()}.
decode_continue(Continuation, Budget) ->
    avm_cbor_cont:continue(Continuation, Budget).

decode_normalized(<<>>, _State) ->
    {error, empty};
decode_normalized(Bin, State) ->
    case check_max_bytes(byte_size(Bin), decode_opts(State)) of
        ok ->
            case decode_item(Bin, State, 0) of
                {ok, Item, Rest, _State1} -> {ok, Item, Rest};
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

%% Encode one supported value.
-spec encode(term()) -> encode_result().
encode(Val) -> encode_normalized(Val, ?CBOR_DEFAULT_OPTS).

%% Encode one supported value with options.
-spec encode(term(), list()) -> encode_result().
encode(Val, Opts) when is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, State} -> encode_normalized(Val, State)
    end;
encode(_Val, _Opts) ->
    {error, invalid_options_list}.

%% Encode once and return both the bytes and their exact size.
-spec encode_with_size(term()) ->
    {ok, binary(), non_neg_integer()} | {error, term()}.
encode_with_size(Val) ->
    add_encoded_size(encode_normalized(Val, ?CBOR_DEFAULT_OPTS)).

-spec encode_with_size(term(), term()) ->
    {ok, binary(), non_neg_integer()} | {error, term()}.
encode_with_size(Val, Opts) when is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, State} -> add_encoded_size(encode_normalized(Val, State))
    end;
encode_with_size(_Val, _Opts) ->
    {error, invalid_options_list}.

add_encoded_size({ok, Bin}) -> {ok, Bin, byte_size(Bin)};
add_encoded_size({error, _} = Err) -> Err.

%% Encode an RFC 8742 CBOR sequence as concatenated data items. Each item is
%% encoded once, item binaries are accumulated in reverse order, and the final
%% output is constructed once so the sequence layer is not quadratic.
-spec encode_sequence(term()) -> {ok, binary()} | {error, term()}.
encode_sequence(Values) when is_list(Values) ->
    encode_sequence_normalized(Values, ?CBOR_DEFAULT_OPTS);
encode_sequence(_Values) ->
    {error, invalid_input}.

-spec encode_sequence(term(), term()) -> {ok, binary()} | {error, term()}.
encode_sequence(Values, Opts) when is_list(Values), is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, State} -> encode_sequence_normalized(Values, State)
    end;
encode_sequence(Values, _Opts) when is_list(Values) ->
    {error, invalid_options_list};
encode_sequence(_Values, _Opts) ->
    {error, invalid_input}.

encode_sequence_normalized(Values, Opts) ->
    encode_sequence_items(Values, Opts, 0, 0, []).

encode_sequence_items([], _Opts, _Count, _Size, Acc) ->
    {ok, list_to_binary(lists:reverse(Acc))};
encode_sequence_items([Value | Rest], Opts, Count, Size, Acc) ->
    NextCount = Count + 1,
    case check_item_limit(NextCount, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case encode_normalized(Value, Opts) of
                {error, _} = Err -> Err;
                {ok, Bin} ->
                    NextSize = Size + byte_size(Bin),
                    case check_max_bytes(NextSize, Opts) of
                        {error, _} = Err -> Err;
                        ok -> encode_sequence_items(
                            Rest, Opts, NextCount, NextSize, [Bin | Acc])
                    end
            end
    end;
encode_sequence_items(_ImproperTail, _Opts, _Count, _Size, _Acc) ->
    {error, invalid_input}.

encode_normalized(Val, State) ->
    try do_encode(Val, State, 0) of
        Bin when is_binary(Bin) ->
            case check_max_bytes(byte_size(Bin), State) of
                ok -> {ok, Bin};
                {error, _} = Err -> Err
            end
    catch
        error:function_clause ->
            {error, {unsupported_value, Val}};
        error:{encode_error, Reason} ->
            {error, Reason};
        error:Reason:Stacktrace ->
            {error, {Reason, Stacktrace}};
        exit:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% Partial (deferred) decode
%%
%% partial_decode/1,2 reads the outer structure of the next CBOR item
%% without recursively building nested Erlang terms. It returns an
%% opaque partial descriptor plus the remaining bytes. Scalar types
%% (unsigned, negative, float, simple) carry their decoded value and
%% partial_deep_decode/1 returns it directly; compound types (bytes,
%% text, array, map, tag) are validated and measured but not decoded
%% until partial_deep_decode/1 is called.
%%
%% Accepted options are the decode/2 options plus:
%%   {max_items, N}        - positive global node/work cap (partial default: 64)
%%   {max_total_string_bytes, N} - positive cumulative string-byte cap
%%   {max_string_size, N}  - cap on bytes/text content (default: 8192)
%%
%% The descriptor is opaque; use the partial_* accessors below.
%%--------------------------------------------------------------------

-spec partial_decode(term()) -> {ok, term(), binary()} | {error, term()}.
partial_decode(Bin) -> avm_cbor_partial:decode(Bin).

-spec partial_decode(term(), term()) -> {ok, term(), binary()} | {error, term()}.
partial_decode(Bin, Opts) -> avm_cbor_partial:decode(Bin, Opts).

%% Raw encoded CBOR bytes of the complete item behind the descriptor.
-spec partial_value_bytes(term()) -> binary() | {error, term()}.
partial_value_bytes(Partial) -> avm_cbor_partial:value_bytes(Partial).

%% Fully decode the item behind the descriptor.
-spec partial_deep_decode(term()) -> {ok, term()} | {error, term()}.
partial_deep_decode(Partial) -> avm_cbor_partial:deep_decode(Partial).

%% Discard the descriptor. No work is performed.
-spec partial_skip(term()) -> ok | {error, term()}.
partial_skip(Partial) -> avm_cbor_partial:skip(Partial).

%% unsigned | negative | bytes | text | array | map | tag | float | simple
-spec partial_type(term()) -> atom() | {error, term()}.
partial_type(Partial) -> avm_cbor_partial:type(Partial).

%% Element count for array (items) and map (pairs); undefined otherwise.
-spec partial_count(term()) -> non_neg_integer() | undefined | {error, term()}.
partial_count(Partial) -> avm_cbor_partial:count(Partial).

%% Tag number for tag items; undefined otherwise.
-spec partial_tag(term()) -> non_neg_integer() | undefined | {error, term()}.
partial_tag(Partial) -> avm_cbor_partial:tag_number(Partial).

%% Content byte length for bytes/text items; undefined otherwise.
-spec partial_size(term()) -> non_neg_integer() | undefined | {error, term()}.
partial_size(Partial) -> avm_cbor_partial:string_size(Partial).

%% Start offset of the item in the binary given to partial_decode.
-spec partial_offset(term()) -> non_neg_integer() | {error, term()}.
partial_offset(Partial) -> avm_cbor_partial:item_offset(Partial).

%% Encoded byte length of the complete item from its offset.
-spec partial_length(term()) -> non_neg_integer() | {error, term()}.
partial_length(Partial) -> avm_cbor_partial:item_length(Partial).

%% Raw bytes of the elements inside an array, map, or tag descriptor,
%% suitable for walking with repeated partial_decode calls.
-spec partial_contents(term()) -> {ok, binary()} | {error, term()}.
partial_contents(Partial) -> avm_cbor_partial:contents(Partial).

%% Traverse map pairs as opaque descriptors without deep-decoding their values.
%% Fun(KeyPartial, ValuePartial, Acc) must return {cont, NewAcc} or
%% {halt, Result}.  Callback exceptions are application errors and propagate.
-spec partial_map_fold(term(), fun((term(), term(), term()) ->
    {cont, term()} | {halt, term()}), term()) -> {ok, term()} | {error, term()}.
partial_map_fold(Partial, Fun, Acc) -> avm_cbor_partial:map_fold(Partial, Fun, Acc).

%% Traverse array elements as opaque descriptors.  The callback contract is
%% the same as partial_map_fold/3, without a key argument.
-spec partial_array_fold(term(), fun((term(), term()) ->
    {cont, term()} | {halt, term()}), term()) -> {ok, term()} | {error, term()}.
partial_array_fold(Partial, Fun, Acc) -> avm_cbor_partial:array_fold(Partial, Fun, Acc).

%% Select normal Erlang key terms in one map pass.  Found pairs are returned in
%% CBOR map order; missing keys retain request order.  First duplicate wins.
-spec partial_select(term(), term()) ->
    {ok, [{term(), term()}], [term()]} | {error, term()}.
partial_select(Partial, Keys) -> avm_cbor_partial:select(Partial, Keys).

%% Find the first matching normal Erlang key term without decoding its value.
-spec partial_map_find(term(), term()) -> {ok, term()} | {error, term()}.
partial_map_find(Partial, Key) -> avm_cbor_partial:map_find(Partial, Key).

%% Return an array element descriptor by zero-based index.
-spec partial_array_nth(term(), term()) -> {ok, term()} | {error, term()}.
partial_array_nth(Partial, Index) -> avm_cbor_partial:array_nth(Partial, Index).

%% Validate exactly one complete item without materializing its nested Erlang
%% value.  Defaults and accepted options intentionally match partial_decode.
-spec validate_all(term()) -> ok | {error, term()}.
validate_all(Bin) when is_binary(Bin) ->
    validate_partial_result(avm_cbor_partial:decode(Bin));
validate_all(_Bin) ->
    {error, invalid_input}.

-spec validate_all(term(), term()) -> ok | {error, term()}.
validate_all(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    validate_partial_result(avm_cbor_partial:decode(Bin, Opts));
validate_all(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
validate_all(_Bin, _Opts) ->
    {error, invalid_input}.

validate_partial_result({ok, _Partial, <<>>}) -> ok;
validate_partial_result({ok, _Partial, Rest}) ->
    {error, {trailing_bytes, byte_size(Rest)}};
validate_partial_result({error, _} = Err) -> Err.

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
        {max_total_string_bytes, 256},
        {allow_floats, false},
        {allow_simple, true},
        {allow_tags, false},
        {allow_indefinite, false},
        {preferred, true},
        {deterministic, true}
    ].

%% Convert the public option list to the private recursive state in one pass.
%% Scalar accumulator arguments make duplicate options naturally last-wins
%% without copying a tuple for every option.
normalize_opts(Opts) ->
    normalize_opts(
        Opts,
        128,
        4096,
        1048576,
        65536,
        1048576,
        0,
        ?CBOR_DEFAULT_FLAGS,
        full
    ).

normalize_partial_opts(Opts) ->
    normalize_opts(
        Opts,
        128,
        64,
        1048576,
        65536,
        1048576,
        8192,
        ?CBOR_DEFAULT_FLAGS,
        partial
    ).

normalize_opts([], MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
               MaxTotalStringBytes, MaxStringSize, Flags, _Mode) ->
    {ok, #cbor_opts{
        max_depth = MaxDepth,
        max_items = MaxItems,
        max_bytes = MaxBytes,
        max_string_bytes = MaxStringBytes,
        max_total_string_bytes = MaxTotalStringBytes,
        max_string_size = MaxStringSize,
        flags = Flags
    }};
normalize_opts([{max_depth, V} | Rest], _MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, V, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize, Flags, Mode);
normalize_opts([{max_items, V} | Rest], MaxDepth, _MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, MaxDepth, V, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize, Flags, Mode);
normalize_opts([{max_bytes, V} | Rest], MaxDepth, MaxItems, _MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, MaxDepth, MaxItems, V, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize, Flags, Mode);
normalize_opts([{max_string_bytes, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               _MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, V,
                   MaxTotalStringBytes, MaxStringSize, Flags, Mode);
normalize_opts([{max_total_string_bytes, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, _MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   V, MaxStringSize, Flags, Mode);
normalize_opts([{max_string_size, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, _MaxStringSize, Flags, partial)
  when is_integer(V), V > 0 ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, V, Flags, partial);
normalize_opts([{allow_floats, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_ALLOW_FLOATS, V), Mode);
normalize_opts([{allow_simple, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_ALLOW_SIMPLE, V), Mode);
normalize_opts([{allow_tags, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_ALLOW_TAGS, V), Mode);
normalize_opts([{allow_indefinite, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_ALLOW_INDEFINITE, V), Mode);
normalize_opts([{preferred, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_PREFERRED, V), Mode);
normalize_opts([{deterministic, V} | Rest], MaxDepth, MaxItems, MaxBytes,
               MaxStringBytes, MaxTotalStringBytes, MaxStringSize, Flags, Mode)
  when V =:= true; V =:= false ->
    normalize_opts(Rest, MaxDepth, MaxItems, MaxBytes, MaxStringBytes,
                   MaxTotalStringBytes, MaxStringSize,
                   set_option_flag(Flags, ?CBOR_FLAG_DETERMINISTIC, V), Mode);
normalize_opts([Bad | _], _MaxDepth, _MaxItems, _MaxBytes,
               _MaxStringBytes, _MaxTotalStringBytes, _MaxStringSize, _Flags, _Mode) ->
    {error, {invalid_option, Bad}};
normalize_opts(_, _MaxDepth, _MaxItems, _MaxBytes,
               _MaxStringBytes, _MaxTotalStringBytes, _MaxStringSize, _Flags, _Mode) ->
    {error, invalid_options_list}.

set_option_flag(Flags, Flag, true) -> Flags bor Flag;
set_option_flag(Flags, Flag, false) -> Flags band (?CBOR_ALL_FLAGS bxor Flag).

new_decode_state(Opts = #cbor_opts{}) ->
    #cbor_decode_state{
        opts = Opts,
        nodes_left = Opts#cbor_opts.max_items,
        string_bytes_left = Opts#cbor_opts.max_total_string_bytes
    }.

decode_opts(#cbor_decode_state{opts = Opts}) -> Opts.

consume_node(State) -> consume_nodes(1, State).

consume_nodes(_Needed,
              State = #cbor_decode_state{nodes_left = input_size_proven}) ->
    {ok, State};
consume_nodes(Needed, State = #cbor_decode_state{nodes_left = Left, opts = Opts})
  when is_integer(Needed), Needed >= 0 ->
    case Needed =< Left of
        true -> {ok, State#cbor_decode_state{nodes_left = Left - Needed}};
        false -> {error, {max_items_exceeded, Opts#cbor_opts.max_items}}
    end.

ensure_node_budget(_Needed,
                   #cbor_decode_state{nodes_left = input_size_proven}) ->
    ok;
ensure_node_budget(Needed, #cbor_decode_state{nodes_left = Left, opts = Opts})
  when is_integer(Needed), Needed >= 0 ->
    case Needed =< Left of
        true -> ok;
        false -> {error, {max_items_exceeded, Opts#cbor_opts.max_items}}
    end.

consume_string_bytes(Needed,
                     State = #cbor_decode_state{string_bytes_left = Left, opts = Opts})
  when is_integer(Needed), Needed >= 0 ->
    case Needed =< Left of
        true ->
            {ok, State#cbor_decode_state{string_bytes_left = Left - Needed}};
        false ->
            {error, {max_total_string_bytes_exceeded,
                     Opts#cbor_opts.max_total_string_bytes}}
    end.

check_max_bytes(Size, #cbor_opts{max_bytes = Limit}) ->
    case Limit of
        _ when Size > Limit -> {error, {max_bytes_exceeded, Limit}};
        _ -> ok
    end.

%%--------------------------------------------------------------------
%% CBOR sequence helpers
%%--------------------------------------------------------------------

-spec decode_all(term()) -> {ok, list()} | {error, term()}.
decode_all(Bin) when is_binary(Bin) ->
    decode_all_normalized(Bin, new_decode_state(?CBOR_DEFAULT_OPTS));
decode_all(_Bin) ->
    {error, invalid_input}.

-spec decode_all(term(), term()) -> {ok, list()} | {error, term()}.
decode_all(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, OptState} -> decode_all_normalized(Bin, new_decode_state(OptState))
    end;
decode_all(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
decode_all(_Bin, _Opts) ->
    {error, invalid_input}.

decode_all_normalized(<<>>, _State) ->
    {ok, []};
decode_all_normalized(Bin, State) ->
    case check_max_bytes(byte_size(Bin), decode_opts(State)) of
        ok -> decode_all_items(Bin, State, []);
        {error, _} = Err -> Err
    end.

decode_all_items(<<>>, _State, Acc) -> {ok, lists:reverse(Acc)};
decode_all_items(Bin, State, Acc) ->
    decode_all_small_items(Bin, State, Acc).

decode_all_small_items(<<>>, _State, Acc) ->
    {ok, lists:reverse(Acc)};
decode_all_small_items(<<First:8, Rest/binary>>,
                       State = #cbor_decode_state{nodes_left = Left}, Acc)
  when First < 24; First >= 16#20, First < 16#38 ->
    case Left > 0 of
        true ->
            Value = case First < 24 of
                true -> First;
                false -> -1 - (First band 16#1F)
            end,
            State1 = State#cbor_decode_state{nodes_left = Left - 1},
            decode_all_small_items(Rest, State1, [Value | Acc]);
        false ->
            #cbor_decode_state{opts = Opts} = State,
            {error, {max_items_exceeded, Opts#cbor_opts.max_items}}
    end;
decode_all_small_items(Bin, State, Acc) ->
    case decode_item(Bin, State, 0) of
        {ok, Item, Rest, NextState} -> decode_all_items(Rest, NextState, [Item | Acc]);
        {error, _} = Err -> Err
    end.

-spec decode_sequence(term()) -> {ok, list(), binary()} | {error, term()}.
decode_sequence(Bin) when is_binary(Bin) ->
    decode_sequence_normalized(Bin, new_decode_state(?CBOR_DEFAULT_OPTS));
decode_sequence(_Bin) ->
    {error, invalid_input}.

-spec decode_sequence(term(), term()) -> {ok, list(), binary()} | {error, term()}.
decode_sequence(Bin, Opts) when is_binary(Bin), is_list(Opts) ->
    case normalize_opts(Opts) of
        {error, _} = Err -> Err;
        {ok, OptState} -> decode_sequence_normalized(Bin, new_decode_state(OptState))
    end;
decode_sequence(Bin, _Opts) when is_binary(Bin) ->
    {error, invalid_options_list};
decode_sequence(_Bin, _Opts) ->
    {error, invalid_input}.

decode_sequence_normalized(<<>>, _State) ->
    {ok, [], <<>>};
decode_sequence_normalized(Bin, State) ->
    case check_max_bytes(byte_size(Bin), decode_opts(State)) of
        ok -> decode_sequence_items(Bin, State, []);
        {error, _} = Err -> Err
    end.

decode_sequence_items(<<>>, _State, Acc) ->
    {ok, lists:reverse(Acc), <<>>};
decode_sequence_items(Bin, State, Acc) ->
    decode_sequence_small_items(Bin, State, Acc).

decode_sequence_small_items(<<>>, _State, Acc) ->
    {ok, lists:reverse(Acc), <<>>};
decode_sequence_small_items(<<First:8, Rest/binary>>,
                            State = #cbor_decode_state{nodes_left = Left}, Acc)
  when First < 24; First >= 16#20, First < 16#38 ->
    case Left > 0 of
        true ->
            Value = case First < 24 of
                true -> First;
                false -> -1 - (First band 16#1F)
            end,
            State1 = State#cbor_decode_state{nodes_left = Left - 1},
            decode_sequence_small_items(Rest, State1, [Value | Acc]);
        false ->
            #cbor_decode_state{opts = Opts} = State,
            {error, {max_items_exceeded, Opts#cbor_opts.max_items}}
    end;
decode_sequence_small_items(Bin, State, Acc) ->
    case decode_item(Bin, State, 0) of
        {ok, Item, Rest, NextState} ->
            decode_sequence_items(Rest, NextState, [Item | Acc]);
        {error, truncated} ->
            {ok, lists:reverse(Acc), Bin};
        {error, _} = Err ->
            Err
    end.

%% Fold complete sequence items without building the decode_sequence/1 result
%% list.  The callback returns {cont, NewAcc} or {halt, Result}.  A truncated
%% final item is returned unchanged as Rest, matching decode_sequence/1.
-spec sequence_fold(term(), term(), term()) ->
    {ok, term(), binary()} | {error, term()}.
sequence_fold(Bin, Fun, Acc) when is_binary(Bin), is_function(Fun, 2) ->
    State = new_decode_state(?CBOR_DEFAULT_OPTS),
    case check_max_bytes(byte_size(Bin), decode_opts(State)) of
        ok -> sequence_fold_items(Bin, State, Fun, Acc);
        {error, _} = Err -> Err
    end;
sequence_fold(Bin, _Fun, _Acc) when is_binary(Bin) ->
    {error, invalid_callback};
sequence_fold(_Bin, _Fun, _Acc) ->
    {error, invalid_input}.

sequence_fold_items(<<>>, _State, _Fun, Acc) -> {ok, Acc, <<>>};
sequence_fold_items(Bin, State, Fun, Acc) ->
    case decode_item(Bin, State, 0) of
        {ok, Item, Rest, State1} ->
            case Fun(Item, Acc) of
                {cont, NewAcc} -> sequence_fold_items(Rest, State1, Fun, NewAcc);
                {halt, Result} -> {ok, Result, Rest};
                _ -> {error, invalid_fold_result}
            end;
        {error, truncated} -> {ok, Acc, Bin};
        {error, _} = Err -> Err
    end.

%%--------------------------------------------------------------------
%% Decode internals
%%--------------------------------------------------------------------

decode_item(<<>>, _, _) -> {error, truncated};
decode_item(Bin, State = #cbor_decode_state{nodes_left = input_size_proven},
            Depth) ->
    decode_charged_item(Bin, State, Depth);
decode_item(Bin, State = #cbor_decode_state{nodes_left = Left}, Depth)
  when Left > 0 ->
    decode_charged_item(
        Bin,
        State#cbor_decode_state{nodes_left = Left - 1},
        Depth
    );
decode_item(_Bin, #cbor_decode_state{opts = Opts}, _Depth) ->
    {error, {max_items_exceeded, Opts#cbor_opts.max_items}}.

decode_charged_item(<<First:8, Rest/binary>>, State, Depth) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    Opts = decode_opts(State),
    case AddInfo of
        31 ->
            case MajorType of
                Type when Type >= 2, Type =< 5 ->
                    case requires_deterministic_decode(Opts) of
                        true -> {error, non_deterministic_indefinite};
                        false -> decode_indefinite(Type, Rest, State, Depth)
                    end;
                7 -> {error, unexpected_break};
                _ -> {error, indefinite_length_unsupported}
            end;
        _ ->
            case arg(AddInfo, Rest) of
                {ok, Arg, Rest2} ->
                    PreferredResult = case AddInfo < 24 of
                        true -> ok;
                        false -> check_preferred(MajorType, AddInfo, Arg, Opts)
                    end,
                    case PreferredResult of
                        ok ->
                            case MajorType of
                                0 -> {ok, Arg, Rest2, State};
                                1 -> {ok, -1 - Arg, Rest2, State};
                                2 -> byte_string(Arg, Rest2, State);
                                3 -> text_string(Arg, Rest2, State);
                                4 -> array(Arg, Rest2, State, Depth);
                                5 -> map(Arg, Rest2, State, Depth);
                                6 -> tag(Arg, Rest2, State, Depth);
                                7 ->
                                    case simple(AddInfo, Arg, Rest2, Opts) of
                                        {ok, Value, Rest3} -> {ok, Value, Rest3, State};
                                        {error, _} = Err -> Err
                                    end
                            end;
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end
    end.

decode_indefinite(2, Rest, State, Depth) -> indef_byte_string(Rest, State, Depth);
decode_indefinite(3, Rest, State, Depth) -> indef_text_string(Rest, State, Depth);
decode_indefinite(4, Rest, State, Depth) -> indef_array(Rest, State, Depth);
decode_indefinite(5, Rest, State, Depth) -> indef_map(Rest, State, Depth).

check_preferred(MajorType, AddInfo, Arg, Opts) ->
    case requires_preferred_decode(Opts) of
        true -> preferred_arg(MajorType, AddInfo, Arg, Opts);
        false -> ok
    end.

requires_preferred_decode(Opts) ->
    ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_PREFERRED) orelse
    requires_deterministic_decode(Opts).

requires_deterministic_decode(Opts) ->
    ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_DETERMINISTIC).

preferred_arg(7, 24, Arg, _Opts) when Arg < 24 ->
    {error, {non_preferred_simple, Arg}};
preferred_arg(7, AddInfo, Arg, Opts) when AddInfo >= 25, AddInfo =< 27 ->
    preferred_float_arg(AddInfo, Arg, Opts);
preferred_arg(MajorType, 24, Arg, _Opts) when MajorType =/= 7, Arg < 24 ->
    {error, {non_preferred_argument, Arg}};
preferred_arg(MajorType, 25, Arg, _Opts) when MajorType =/= 7, Arg =< 255 ->
    {error, {non_preferred_argument, Arg}};
preferred_arg(MajorType, 26, Arg, _Opts) when MajorType =/= 7, Arg =< 65535 ->
    {error, {non_preferred_argument, Arg}};
preferred_arg(MajorType, 27, Arg, _Opts)
  when MajorType =/= 7, Arg =< 16#FFFFFFFF ->
    {error, {non_preferred_argument, Arg}};
preferred_arg(_, _, _, _) -> ok.

preferred_float_arg(25, Bits, Opts) ->
    case is_half_nan(Bits) andalso
         ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_DETERMINISTIC) andalso
         Bits =/= 16#7E00 of
        true -> {error, {non_deterministic_nan, 16#7E00}};
        false -> ok
    end;
preferred_float_arg(26, Bits, _Opts) ->
    Exp = (Bits bsr 23) band 16#FF,
    case Exp of
        16#FF -> {error, {non_preferred_float, half}};
        _ ->
            <<Value:32/float-big>> = <<Bits:32/integer-big>>,
            case float_to_half_bits(Value) of
                undefined -> ok;
                _ -> {error, {non_preferred_float, half}}
            end
    end;
preferred_float_arg(27, Bits, _Opts) ->
    Exp = (Bits bsr 52) band 16#7FF,
    case Exp of
        16#7FF -> {error, {non_preferred_float, half}};
        _ ->
            <<Value:64/float-big>> = <<Bits:64/integer-big>>,
            case float_to_half_bits(Value) of
                undefined ->
                    case try_single_encode(Value) of
                        undefined -> ok;
                        {single, _} -> {error, {non_preferred_float, single}}
                    end;
                _ -> {error, {non_preferred_float, half}}
            end
    end.

is_half_nan(Bits) ->
    ((Bits bsr 10) band 16#1F) =:= 16#1F andalso (Bits band 16#3FF) =/= 0.

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

byte_string(N, Bin, State) ->
    Opts = decode_opts(State),
    case check_string_byte_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<Chunk:N/binary, Rest/binary>> = Bin,
                    {ok, Chunk, Rest, State1};
                {ok, _State1} ->
                    {error, truncated}
            end
    end.

text_string(N, Bin, State) ->
    Opts = decode_opts(State),
    case check_string_byte_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<Chunk:N/binary, Rest/binary>> = Bin,
                    case validate_utf8(Chunk) of
                        ok -> {ok, {text, Chunk}, Rest, State1};
                        {error, _} = Err -> Err
                    end;
                {ok, _State1} ->
                    {error, truncated}
            end
    end.

check_string_byte_limit(N, #cbor_opts{max_string_bytes = Limit}) ->
    case Limit of
        0 -> ok;
        _ when N > Limit -> {error, {max_string_bytes_exceeded, Limit}};
        _ -> ok
    end.

array(0, Bin, State, _Depth) -> {ok, [], Bin, State};
array(N, Bin, State, Depth) when N > 0 ->
    Opts = decode_opts(State),
    case ensure_declared_items(N, Bin, State) of
        {error, _} = Err -> Err;
        ok ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> items(N, Bin, State, Depth + 1, [])
            end
    end.

items(N, Bin, State, Depth, []) ->
    case fixed_unsigned_items(N, Bin) of
        {ok, Values, Rest} ->
            case consume_nodes(N, State) of
                {ok, State1} -> {ok, Values, Rest, State1};
                {error, _} = Err -> Err
            end;
        fallback ->
            items_general(N, Bin, State, Depth, [])
    end.

%% erlang:binary_to_list/1 is a native BIF on the pinned AtomVM runtime.  The
%% declaration checks have already bounded N and proved N available bytes.
%% Convert only that bounded prefix, then prove every resulting byte represents
%% a complete preferred unsigned integer before accepting the list as decoded
%% values.  Any mismatch discards the bounded candidate and uses the full path.
fixed_unsigned_items(N, Bin)
  when N >= ?FIXED_COST_NATIVE_MIN_NODES,
       N =< ?FIXED_COST_BATCH_MAX_NODES,
       N =< byte_size(Bin) ->
    <<Candidate:N/binary, Rest/binary>> = Bin,
    Values = erlang:binary_to_list(Candidate),
    case all_fixed_unsigned(Values) of
        true -> {ok, Values, Rest};
        false -> fallback
    end;
fixed_unsigned_items(_N, _Bin) -> fallback.

all_fixed_unsigned([]) -> true;
all_fixed_unsigned([Value | Rest]) when Value < 24 ->
    all_fixed_unsigned(Rest);
all_fixed_unsigned(_Values) -> false.

items_general(0, Bin, State, _Depth, Acc) ->
    {ok, lists:reverse(Acc), Bin, State};
items_general(N, Bin, State, Depth, Acc) ->
    case decode_item(Bin, State, Depth) of
        {ok, Item, Rest, State1} ->
            items_general(N - 1, Rest, State1, Depth, [Item | Acc]);
        {error, _} = Err -> Err
    end.

map(0, Bin, State, _Depth) -> {ok, {map, []}, Bin, State};
map(N, Bin, State, Depth) when N > 0 ->
    Opts = decode_opts(State),
    case ensure_declared_items(N * 2, Bin, State) of
        {error, _} = Err -> Err;
        ok ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok ->
                    case requires_deterministic_decode(Opts) of
                        true -> deterministic_pairs(N, Bin, State, Depth + 1, [], none);
                        false -> pairs(N, Bin, State, Depth + 1, [])
                    end
            end
    end.

pairs(N, Bin, State, Depth, []) ->
    case fixed_unsigned_pairs(N, Bin) of
        {ok, Values, Rest} ->
            case consume_nodes(N * 2, State) of
                {ok, State1} -> {ok, {map, Values}, Rest, State1};
                {error, _} = Err -> Err
            end;
        fallback ->
            pairs_general(N, Bin, State, Depth, [])
    end.

fixed_unsigned_pairs(N, Bin)
  when N * 2 >= ?FIXED_COST_NATIVE_MIN_NODES,
       N * 2 =< ?FIXED_COST_BATCH_MAX_NODES,
       N * 2 =< byte_size(Bin) ->
    Needed = N * 2,
    <<Candidate:Needed/binary, Rest/binary>> = Bin,
    Bytes = erlang:binary_to_list(Candidate),
    case all_fixed_unsigned(Bytes) of
        true -> {ok, fixed_unsigned_pair_values(Bytes, []), Rest};
        false -> fallback
    end;
fixed_unsigned_pairs(_N, _Bin) -> fallback.

fixed_unsigned_pair_values([], Acc) -> lists:reverse(Acc);
fixed_unsigned_pair_values([Key, Value | Rest], Acc) ->
    fixed_unsigned_pair_values(Rest, [{Key, Value} | Acc]).

pairs_general(0, Bin, State, _Depth, Acc) ->
    {ok, {map, lists:reverse(Acc)}, Bin, State};
pairs_general(N, Bin, State, Depth, Acc) ->
    case decode_item(Bin, State, Depth) of
        {ok, Key, Rest1, State1} ->
            case decode_item(Rest1, State1, Depth) of
                {ok, Val, Rest2, State2} ->
                    pairs_general(N - 1, Rest2, State2, Depth,
                                  [{Key, Val} | Acc]);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

deterministic_pairs(0, Bin, State, _Depth, Acc, _PreviousKeyBytes) ->
    {ok, {map, lists:reverse(Acc)}, Bin, State};
deterministic_pairs(N, Bin, State, Depth, Acc, PreviousKeyBytes) ->
    KeyInput = Bin,
    case decode_item(Bin, State, Depth) of
        {ok, Key, Rest1, State1} ->
            KeyLength = byte_size(KeyInput) - byte_size(Rest1),
            <<KeyBytes:KeyLength/binary, _/binary>> = KeyInput,
            case check_deterministic_map_key(PreviousKeyBytes, KeyBytes) of
                ok ->
                    case decode_item(Rest1, State1, Depth) of
                        {ok, Val, Rest2, State2} ->
                            deterministic_pairs(
                                N - 1, Rest2, State2, Depth,
                                [{Key, Val} | Acc], KeyBytes);
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

check_deterministic_map_key(none, _CurrentKeyBytes) -> ok;
check_deterministic_map_key(PreviousKeyBytes, CurrentKeyBytes) ->
    case compare_key_bytes(PreviousKeyBytes, CurrentKeyBytes) of
        less -> ok;
        equal -> {error, duplicate_map_key};
        greater -> {error, non_deterministic_map_order}
    end.

compare_key_bytes(<<>>, <<>>) -> equal;
compare_key_bytes(<<>>, _Right) -> less;
compare_key_bytes(_Left, <<>>) -> greater;
compare_key_bytes(<<Left:8, LeftRest/binary>>, <<Right:8, RightRest/binary>>) ->
    case Left of
        _ when Left < Right -> less;
        _ when Left > Right -> greater;
        _ -> compare_key_bytes(LeftRest, RightRest)
    end.

ensure_declared_items(Needed, Bin, State) ->
    case ensure_node_budget(Needed, State) of
        {error, _} = Err -> Err;
        ok ->
            declared_input_check(Needed, Bin)
    end.

%% Each child needs at least one byte. Preserve a more specific malformed-header
%% error when the first available child is itself reserved or an unexpected break.
declared_input_check(Needed, Bin) when Needed =< byte_size(Bin) -> ok;
declared_input_check(_Needed, <<First:8, _/binary>>) ->
    AddInfo = First band 16#1F,
    case {First bsr 5, AddInfo} of
        {7, 31} -> ok;
        {_, Value} when Value >= 28, Value =< 30 -> ok;
        _ -> {error, truncated}
    end;
declared_input_check(_Needed, <<>>) -> {error, truncated}.

check_item_limit(N, #cbor_opts{max_items = Limit}) ->
    case N > Limit of
        true -> {error, {max_items_exceeded, Limit}};
        false -> ok
    end.

check_depth(Depth, #cbor_opts{max_depth = Limit}) ->
    case Depth > Limit of
        true -> {error, {max_depth_exceeded, Limit}};
        false -> ok
    end.

simple(AddInfo, _, Bin, Opts) when AddInfo >= 0, AddInfo =< 19 ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_SIMPLE) of
        true -> {ok, {simple, AddInfo}, Bin};
        false -> {error, {unsupported_simple_value, AddInfo}}
    end;
simple(20, _, Bin, _) -> {ok, false, Bin};
simple(21, _, Bin, _) -> {ok, true, Bin};
simple(22, _, Bin, _) -> {ok, null, Bin};
simple(23, _, Bin, _) -> {ok, undefined, Bin};
simple(24, Val, Bin, Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_SIMPLE) of
        true -> {ok, {simple, Val}, Bin};
        false -> {error, {unsupported_simple_value, Val}}
    end;
simple(25, Val, Bin, Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_FLOATS) of
        false -> {error, floats_not_allowed};
        true -> decode_half(Val, Bin)
    end;
simple(26, Val, Bin, Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_FLOATS) of
        false -> {error, floats_not_allowed};
        true ->
            try
                <<F:32/float, _/binary>> = <<Val:32>>,
                {ok, F, Bin}
            catch
                error:{badmatch, _} -> {error, {unsupported_simple_value, invalid_float}}
            end
    end;
simple(27, Val, Bin, Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_FLOATS) of
        false -> {error, floats_not_allowed};
        true ->
            try
                <<F:64/float, _/binary>> = <<Val:64>>,
                {ok, F, Bin}
            catch
                error:{badmatch, _} -> {error, {unsupported_simple_value, invalid_float}}
            end
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
            {error, {unsupported_simple_value, invalid_float}};
        Exp == 31 ->
            {error, {unsupported_simple_value, invalid_float}};
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

tag(Tag, Bin, State, Depth) ->
    Opts = decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_TAGS) of
        false -> {error, {unsupported_tag, Tag}};
        true ->
            case ensure_declared_items(1, Bin, State) of
                {error, _} = Err -> Err;
                ok ->
                    case check_depth(Depth + 1, Opts) of
                        {error, _} = Err -> Err;
                        ok ->
                            case decode_item(Bin, State, Depth + 1) of
                                {ok, Val, Rest, State1} ->
                                    {ok, {tag, Tag, Val}, Rest, State1};
                                {error, _} = Err -> Err
                            end
                    end
            end
    end.

%%--------------------------------------------------------------------
%% Indefinite-length items
%%--------------------------------------------------------------------

indef_byte_string(Bin, State, _Depth) ->
    Opts = decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
        false -> {error, indefinite_length_unsupported};
        true -> indef_bstr_chunks(Bin, State, 0, [])
    end.

indef_bstr_chunks(<<>>, _State, _Size, _Acc) -> {error, truncated};
indef_bstr_chunks(<<16#FF, Rest/binary>>, State, _Size, Acc) ->
    {ok, list_to_binary(lists:reverse(Acc)), Rest, State};
indef_bstr_chunks(Bin, State, Size, Acc) ->
    case consume_node(State) of
        {error, _} = Err -> Err;
        {ok, State1} ->
            Opts = decode_opts(State1),
            case definite_bstr_chunk_header(Bin) of
                {error, _} = Err -> Err;
                {ok, N, Body} ->
                    NewSize = Size + N,
                    case check_string_byte_limit(NewSize, Opts) of
                        {error, _} = Err -> Err;
                        ok ->
                            case consume_string_bytes(N, State1) of
                                {error, _} = Err -> Err;
                                {ok, State2} when byte_size(Body) >= N ->
                                    <<Chunk:N/binary, Rest/binary>> = Body,
                                    indef_bstr_chunks(Rest, State2, NewSize, [Chunk | Acc]);
                                {ok, _State2} ->
                                    {error, truncated}
                            end
                    end
            end
    end.

definite_bstr_chunk_header(<<First:8, Rest/binary>>) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case MajorType of
        2 when AddInfo < 24 ->
            {ok, AddInfo, Rest};
        2 when AddInfo >= 24, AddInfo =< 27 ->
            case arg(AddInfo, Rest) of
                {ok, N, Rest2} -> {ok, N, Rest2};
                {error, _} = Err -> Err
            end;
        _ ->
            {error, {invalid_indefinite_chunk, expected_byte_string}}
    end;
definite_bstr_chunk_header(<<>>) -> {error, truncated}.

indef_text_string(Bin, State, _Depth) ->
    Opts = decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
        false -> {error, indefinite_length_unsupported};
        true -> indef_tstr_chunks(Bin, State, 0, [])
    end.

indef_tstr_chunks(<<>>, _State, _Size, _Acc) -> {error, truncated};
indef_tstr_chunks(<<16#FF, Rest/binary>>, State, _Size, Acc) ->
    {ok, {text, list_to_binary(lists:reverse(Acc))}, Rest, State};
indef_tstr_chunks(Bin, State, Size, Acc) ->
    case consume_node(State) of
        {error, _} = Err -> Err;
        {ok, State1} ->
            Opts = decode_opts(State1),
            case definite_tstr_chunk_header(Bin) of
                {error, _} = Err -> Err;
                {ok, N, Body} ->
                    NewSize = Size + N,
                    case check_string_byte_limit(NewSize, Opts) of
                        {error, _} = Err -> Err;
                        ok ->
                            case consume_string_bytes(N, State1) of
                                {error, _} = Err -> Err;
                                {ok, State2} when byte_size(Body) >= N ->
                                    <<Chunk:N/binary, Rest/binary>> = Body,
                                    case validate_utf8(Chunk) of
                                        ok ->
                                            indef_tstr_chunks(
                                                Rest, State2, NewSize, [Chunk | Acc]);
                                        {error, _} = Err -> Err
                                    end;
                                {ok, _State2} ->
                                    {error, truncated}
                            end
                    end
            end
    end.

definite_tstr_chunk_header(<<First:8, Rest/binary>>) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case MajorType of
        3 when AddInfo < 24 ->
            {ok, AddInfo, Rest};
        3 when AddInfo >= 24, AddInfo =< 27 ->
            case arg(AddInfo, Rest) of
                {ok, N, Rest2} -> {ok, N, Rest2};
                {error, _} = Err -> Err
            end;
        _ ->
            {error, {invalid_indefinite_chunk, expected_text_string}}
    end;
definite_tstr_chunk_header(<<>>) -> {error, truncated}.

indef_array(Bin, State, Depth) ->
    Opts = decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
        false -> {error, indefinite_length_unsupported};
        true ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> indef_items(Bin, State, Depth + 1, [])
            end
    end.

indef_items(<<>>, _State, _Depth, _Acc) -> {error, truncated};
indef_items(<<16#FF, Rest/binary>>, State, _Depth, Acc) ->
    {ok, lists:reverse(Acc), Rest, State};
indef_items(Bin, State, Depth, Acc) ->
    case decode_item(Bin, State, Depth) of
        {ok, Item, Rest, State1} ->
            indef_items(Rest, State1, Depth, [Item | Acc]);
        {error, _} = Err -> Err
    end.

indef_map(Bin, State, Depth) ->
    Opts = decode_opts(State),
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
        false -> {error, indefinite_length_unsupported};
        true ->
            case check_depth(Depth + 1, Opts) of
                {error, _} = Err -> Err;
                ok -> indef_pairs(Bin, State, Depth + 1, [])
            end
    end.

indef_pairs(<<>>, _State, _Depth, _Acc) -> {error, truncated};
indef_pairs(<<16#FF, Rest/binary>>, State, _Depth, Acc) ->
    {ok, {map, lists:reverse(Acc)}, Rest, State};
indef_pairs(Bin, State, Depth, Acc) ->
    case decode_item(Bin, State, Depth) of
        {ok, Key, Rest1, State1} ->
            case decode_item(Rest1, State1, Depth) of
                {ok, Val, Rest2, State2} ->
                    indef_pairs(Rest2, State2, Depth, [{Key, Val} | Acc]);
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
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
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_FLOATS) of
        false -> erlang:error({encode_error, floats_not_allowed});
        true -> encode_float(Val, Opts)
    end;
do_encode(Val, Opts, _Depth) when is_binary(Val) ->
    Len = byte_size(Val),
    check_string_byte_limit_encode(Len, Opts),
    Hdr = encode_header(2, Len),
    append_encoded(Hdr, Val, Opts);
do_encode({text, Bin}, Opts, _Depth) when is_binary(Bin) ->
    Len = byte_size(Bin),
    check_string_byte_limit_encode(Len, Opts),
    case validate_utf8(Bin) of
        ok ->
            Hdr = encode_header(3, Len),
            append_encoded(Hdr, Bin, Opts);
        {error, invalid_utf8} ->
            erlang:error({encode_error, invalid_utf8})
    end;
do_encode(true, _Opts, _Depth) -> <<16#F5>>;
do_encode(false, _Opts, _Depth) -> <<16#F4>>;
do_encode(null, _Opts, _Depth) -> <<16#F6>>;
do_encode(undefined, _Opts, _Depth) -> <<16#F7>>;
do_encode({simple, N}, Opts, _Depth) when N >= 0, N =< 23 ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_SIMPLE) of
        false -> erlang:error({encode_error, simple_values_not_allowed});
        true -> <<((7 bsl 5) bor N)>>
    end;
do_encode({simple, N}, Opts, _Depth) when N >= 24, N =< 255 ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_SIMPLE) of
        false -> erlang:error({encode_error, simple_values_not_allowed});
        true -> <<((7 bsl 5) bor 24), N>>
    end;
do_encode({tag, Tag, Val}, Opts, Depth) when is_integer(Tag), Tag >= 0 ->
    case Tag bsr 63 < 2 of
        false -> erlang:error({encode_error, {tag_out_of_range, Tag}});
        true ->
            case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_TAGS) of
                false -> erlang:error({encode_error, tags_not_allowed});
                true ->
                    % Increment recursion depth for tag payload
                    NewDepth = Depth + 1,
                    check_depth_encode(NewDepth, Opts),
                    TagHdr = encode_header(6, Tag),
                    ValBin = do_encode(Val, Opts, NewDepth),
                    append_encoded(TagHdr, ValBin, Opts)
            end
    end;
do_encode(Val, Opts, Depth) when is_list(Val) ->
    Len = length(Val),
    check_item_limit_encode(Len, Opts),
    check_depth_encode(Depth + 1, Opts),
    Hdr = encode_header(4, Len),
    Data = fold_encode(Val, Opts, Depth + 1, <<>>),
    append_encoded(Hdr, Data, Opts);
do_encode({map, Pairs}, Opts, Depth) when is_list(Pairs) ->
    Len = length(Pairs),
    check_item_limit_encode(Len, Opts),
    check_depth_encode(Depth + 1, Opts),
    Hdr = encode_header(5, Len),
    Data = encode_map_pairs(Pairs, Opts, Depth + 1),
    append_encoded(Hdr, Data, Opts);
do_encode(Val, _Opts, _Depth) ->
    erlang:error(function_clause, [Val]).

encode_map_pairs(Pairs, Opts, Depth) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_DETERMINISTIC) of
        true ->
            fold_encode_prepared_pairs(sort_map_pairs(Pairs, Opts, Depth), Opts, Depth, <<>>);
        _ ->
            fold_encode_pairs(Pairs, Opts, Depth, <<>>)
    end.

fold_encode([], _Opts, _Depth, Acc) -> Acc;
fold_encode([Item | Rest], Opts, Depth, Acc) ->
    Bin = do_encode(Item, Opts, Depth),
    fold_encode(Rest, Opts, Depth, append_encoded(Acc, Bin, Opts)).

fold_encode_pairs([], _Opts, _Depth, Acc) -> Acc;
fold_encode_pairs([{K, V} | Rest], Opts, Depth, Acc) ->
    KBin = do_encode(K, Opts, Depth),
    AccWithKey = append_encoded(Acc, KBin, Opts),
    VBin = do_encode(V, Opts, Depth),
    fold_encode_pairs(Rest, Opts, Depth, append_encoded(AccWithKey, VBin, Opts)).

sort_map_pairs(Pairs, Opts, Depth) ->
    Decorated = sort_map_pairs(Pairs, Opts, Depth, 0, 0, []),
    [{KBin, V} || {KBin, _, V} <- lists:sort(Decorated)].

sort_map_pairs([], _Opts, _Depth, _Index, _Size, Acc) -> Acc;
sort_map_pairs([{K, V} | Rest], Opts, Depth, Index, Size, Acc) ->
    KBin = do_encode(K, Opts, Depth),
    NewSize = Size + byte_size(KBin),
    check_max_bytes_encode(NewSize, Opts),
    sort_map_pairs(Rest, Opts, Depth, Index + 1, NewSize, [{KBin, Index, V} | Acc]).

fold_encode_prepared_pairs([], _Opts, _Depth, Acc) -> Acc;
fold_encode_prepared_pairs([{KBin, V} | Rest], Opts, Depth, Acc) ->
    AccWithKey = append_encoded(Acc, KBin, Opts),
    VBin = do_encode(V, Opts, Depth),
    fold_encode_prepared_pairs(
        Rest, Opts, Depth, append_encoded(AccWithKey, VBin, Opts)).

encode_float(Val, Opts) ->
    case need_preferred_float(Opts) of
        true -> encode_preferred_float(Val);
        false -> encode_double_float(Val)
    end.

need_preferred_float(Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_PREFERRED) of
        true -> true;
        false ->
            case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_DETERMINISTIC) of
                true -> true;
                false -> false
            end
    end.

encode_double_float(Val) ->
    <<131, 70, Bits:64/integer-big>> = term_to_binary(Val),
    <<16#FB, Bits:64/integer-big>>.

encode_preferred_float(Val) ->
    case try_half_encode(Val) of
        undefined ->
            case try_single_encode(Val) of
                undefined -> encode_double_float(Val);
                {single, Bits32} -> <<16#FA, Bits32:32/integer-big>>
            end;
        {half, Bits} -> <<16#F9, Bits:16>>
    end.

try_half_encode(Val) ->
    case float_to_half_bits(Val) of
        undefined -> undefined;
        Bits -> {half, Bits}
    end.

try_single_encode(Val) ->
    try
        <<Bits32:32/integer-big>> = <<Val:32/float-big>>,
        <<Promoted:32/float-big>> = <<Bits32:32/integer-big>>,
        case float_bits(Promoted) =:= float_bits(Val) of
            true -> {single, Bits32};
            false -> undefined
        end
    catch
        _:_ -> undefined
    end.

float_to_half_bits(Val) ->
    float_bits_to_half_bits(float_bits(Val)).

float_bits_to_half_bits(Bits) ->
    S = Bits bsr 63,
    E = (Bits bsr 52) band 16#7FF,
    M = Bits band 16#000FFFFFFFFFFFFF,
    case E of
        16#7FF ->
            case M of
                0 -> (S bsl 15) bor 16#7C00;
                _ -> 16#7E00
            end;
        0 ->
            case M of
                0 -> (S bsl 15);
                _ -> undefined
            end;
        _ ->
            float_to_half_finite(S, E - 1023, M)
    end.

float_to_half_finite(S, Exponent, Mantissa)
  when Exponent >= -14, Exponent =< 15 ->
    case Mantissa band ((1 bsl 42) - 1) of
        0 ->
            HalfExponent = Exponent + 15,
            HalfMantissa = Mantissa bsr 42,
            (S bsl 15) bor (HalfExponent bsl 10) bor HalfMantissa;
        _ ->
            undefined
    end;
float_to_half_finite(S, Exponent, Mantissa)
  when Exponent >= -24, Exponent =< -15 ->
    Significand = (1 bsl 52) bor Mantissa,
    Shift = 28 - Exponent,
    case Significand band ((1 bsl Shift) - 1) of
        0 ->
            HalfMantissa = Significand bsr Shift,
            (S bsl 15) bor HalfMantissa;
        _ ->
            undefined
    end;
float_to_half_finite(_S, _Exponent, _Mantissa) -> undefined.

float_bits(Val) ->
    <<131, 70, Bits:64/integer-big>> = term_to_binary(Val),
    Bits.

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

check_max_bytes_encode(Size, Opts) ->
    case check_max_bytes(Size, Opts) of
        ok -> ok;
        {error, Reason} -> erlang:error({encode_error, Reason})
    end.

append_encoded(Left, Right, Opts) ->
    check_max_bytes_encode(byte_size(Left) + byte_size(Right), Opts),
    <<Left/binary, Right/binary>>.

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


keyfind(_Key, _N, []) -> false;
keyfind(Key, N, [H | _T]) when element(N, H) =:= Key -> H;
keyfind(Key, N, [_ | T]) -> keyfind(Key, N, T).
