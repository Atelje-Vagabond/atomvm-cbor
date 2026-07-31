-module(avm_cbor_cont).

-include("avm_cbor_opts.hrl").

-export([start/2, continue/2]).

-define(CONT_VERSION, 1).
-define(TEXT_SCAN_BYTES, 256).
-define(REVERSE_ITEMS, 32).

-record(cbor_cont, {
    version = ?CONT_VERSION,
    mode
}).

%% A continuation step is deliberately smaller than a decoded CBOR value.
%% Parsing an item, delivering it into its parent frame, scanning a bounded
%% text segment, and reversing a bounded accumulator segment are separate
%% transitions.  This makes the caller's Budget a real upper bound on the
%% number of interpreter-visible work transitions performed by one call.

start(<<>>, _State) ->
    {error, empty};
start(Bin, State = #cbor_decode_state{}) when is_binary(Bin) ->
    Opts = avm_cbor:decode_opts(State),
    case avm_cbor:check_max_bytes(byte_size(Bin), Opts) of
        ok -> {ok, #cbor_cont{mode = {next, Bin, [], State, 0}}};
        {error, _} = Err -> Err
    end.

continue(_Continuation, Budget) when not is_integer(Budget); Budget =< 0 ->
    {error, {invalid_budget, Budget}};
continue(Continuation, Budget) ->
    case valid_continuation(Continuation) of
        false ->
            {error, invalid_continuation};
        true ->
            try run(Continuation, Budget) of
                Result -> Result
            catch
                _Class:_Reason -> {error, invalid_continuation}
            end
    end.

valid_continuation(#cbor_cont{version = ?CONT_VERSION, mode = Mode}) ->
    valid_mode(Mode);
valid_continuation(_) ->
    false.

valid_mode({next, Bin, Frames, State, Depth})
  when is_binary(Bin), is_list(Frames), is_record(State, cbor_decode_state),
       is_integer(Depth), Depth >= 0 -> true;
valid_mode({emit, _Value, Rest, Frames, State})
  when is_binary(Rest), is_list(Frames), is_record(State, cbor_decode_state) -> true;
valid_mode({validate_text, Whole, Scan, Rest, Frames, State})
  when is_binary(Whole), is_binary(Scan), is_binary(Rest), is_list(Frames),
       is_record(State, cbor_decode_state) -> true;
valid_mode({validate_indef_text, Whole, Scan, Rest, Tail, State, Depth, Size, Acc})
  when is_binary(Whole), is_binary(Scan), is_binary(Rest), is_list(Tail),
       is_record(State, cbor_decode_state), is_integer(Depth), Depth >= 0,
       is_integer(Size), Size >= 0, is_list(Acc) -> true;
valid_mode({reverse, Source, Dest, Kind, Rest, Frames, State})
  when is_list(Source), is_list(Dest), is_binary(Rest), is_list(Frames),
       is_record(State, cbor_decode_state) -> valid_reverse_kind(Kind);
valid_mode({join_binary, Chunks, Kind, Rest, Frames, State})
  when is_list(Chunks), (Kind =:= bytes orelse Kind =:= text), is_binary(Rest),
       is_list(Frames), is_record(State, cbor_decode_state) -> true;
valid_mode(_) ->
    false.

valid_reverse_kind(array) -> true;
valid_reverse_kind(map) -> true;
valid_reverse_kind(indef_bytes) -> true;
valid_reverse_kind(indef_text) -> true;
valid_reverse_kind(_) -> false.

run(Continuation, 0) ->
    {more, Continuation};
run(Continuation, Budget) ->
    case step(Continuation) of
        {next, NextContinuation} -> run(NextContinuation, Budget - 1);
        {done, Value, Rest} -> {done, Value, Rest};
        {error, _} = Err -> Err
    end.

step(#cbor_cont{mode = {next, Bin, Frames, State, Depth}}) ->
    step_next(Bin, Frames, State, Depth);
step(#cbor_cont{mode = {emit, Value, Rest, Frames, State}}) ->
    step_emit(Value, Rest, Frames, State);
step(#cbor_cont{mode = {validate_text, Whole, Scan, Rest, Frames, State}}) ->
    step_validate_text(Whole, Scan, Rest, Frames, State);
step(#cbor_cont{mode =
        {validate_indef_text, Whole, Scan, Rest, Tail, State, Depth, Size, Acc}}) ->
    step_validate_indef_text(Whole, Scan, Rest, Tail, State, Depth, Size, Acc);
step(#cbor_cont{mode = {reverse, Source, Dest, Kind, Rest, Frames, State}}) ->
    step_reverse(Source, Dest, Kind, Rest, Frames, State);
step(#cbor_cont{mode = {join_binary, Chunks, Kind, Rest, Frames, State}}) ->
    step_join_binary(Chunks, Kind, Rest, Frames, State).

step_next(<<>>, _Frames, _State, _Depth) ->
    {error, truncated};
step_next(<<16#FF, Rest/binary>>, [{indef_array, Acc, _Depth} | Tail], State, _CurrentDepth) ->
    next_reverse(Acc, array, Rest, Tail, State);
step_next(<<16#FF, Rest/binary>>, [{indef_map_key, Acc, _Depth} | Tail], State, _CurrentDepth) ->
    next_reverse(Acc, map, Rest, Tail, State);
step_next(<<16#FF, Rest/binary>>, [{indef_bytes, _Size, Acc} | Tail], State, _Depth) ->
    next_reverse(Acc, indef_bytes, Rest, Tail, State);
step_next(<<16#FF, Rest/binary>>, [{indef_text, _Size, Acc} | Tail], State, _Depth) ->
    next_reverse(Acc, indef_text, Rest, Tail, State);
step_next(Bin, [{indef_bytes, Size, Acc} | Tail], State, Depth) ->
    step_indef_string(bytes, Bin, Size, Acc, Tail, State, Depth);
step_next(Bin, [{indef_text, Size, Acc} | Tail], State, Depth) ->
    step_indef_string(text, Bin, Size, Acc, Tail, State, Depth);
step_next(Bin, Frames, State, Depth) ->
    parse_item(Bin, Frames, State, Depth).

parse_item(Bin, Frames,
           State = #cbor_decode_state{nodes_left = Left}, Depth)
  when is_integer(Left), Left > 0 ->
    parse_charged_item(
        Bin, Frames, State#cbor_decode_state{nodes_left = Left - 1}, Depth);
parse_item(_Bin, _Frames,
           #cbor_decode_state{opts = Opts}, _Depth) ->
    {error, {max_items_exceeded, Opts#cbor_opts.max_items}}.

parse_charged_item(<<First:8, Rest/binary>>, Frames, State, Depth) ->
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    Opts = avm_cbor:decode_opts(State),
    case AddInfo of
        31 -> parse_indefinite(MajorType, Rest, Frames, State, Depth, Opts);
        _ -> parse_definite(MajorType, AddInfo, Rest, Frames, State, Depth, Opts)
    end.

parse_indefinite(MajorType, Rest, Frames, State, Depth, Opts)
  when MajorType >= 2, MajorType =< 5 ->
    case avm_cbor:requires_deterministic_decode(Opts) of
        true ->
            {error, non_deterministic_indefinite};
        false ->
            case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_INDEFINITE) of
                false -> {error, indefinite_length_unsupported};
                true -> start_indefinite(MajorType, Rest, Frames, State, Depth, Opts)
            end
    end;
parse_indefinite(7, _Rest, _Frames, _State, _Depth, _Opts) ->
    {error, unexpected_break};
parse_indefinite(_MajorType, _Rest, _Frames, _State, _Depth, _Opts) ->
    {error, indefinite_length_unsupported}.

start_indefinite(2, Rest, Frames, State, Depth, _Opts) ->
    next_mode({next, Rest, [{indef_bytes, 0, []} | Frames], State, Depth});
start_indefinite(3, Rest, Frames, State, Depth, _Opts) ->
    next_mode({next, Rest, [{indef_text, 0, []} | Frames], State, Depth});
start_indefinite(4, Rest, Frames, State, Depth, Opts) ->
    NewDepth = Depth + 1,
    case avm_cbor:check_depth(NewDepth, Opts) of
        ok -> next_mode({next, Rest, [{indef_array, [], NewDepth} | Frames], State, NewDepth});
        {error, _} = Err -> Err
    end;
start_indefinite(5, Rest, Frames, State, Depth, Opts) ->
    NewDepth = Depth + 1,
    case avm_cbor:check_depth(NewDepth, Opts) of
        ok ->
            next_mode({next, Rest,
                [{indef_map_key, [], NewDepth} | Frames], State, NewDepth});
        {error, _} = Err -> Err
    end.

parse_definite(MajorType, AddInfo, Rest, Frames, State, Depth, Opts) ->
    case avm_cbor:arg(AddInfo, Rest) of
        {error, _} = Err ->
            Err;
        {ok, Arg, Rest2} ->
            PreferredResult = case AddInfo < 24 of
                true -> ok;
                false -> avm_cbor:check_preferred(MajorType, AddInfo, Arg, Opts)
            end,
            case PreferredResult of
                ok -> parse_major(MajorType, AddInfo, Arg, Rest2, Frames, State, Depth, Opts);
                {error, _} = Err -> Err
            end
    end.

parse_major(0, _AddInfo, Arg, Rest, Frames, State, _Depth, _Opts) ->
    emit_mode(Arg, Rest, Frames, State);
parse_major(1, _AddInfo, Arg, Rest, Frames, State, _Depth, _Opts) ->
    emit_mode(-1 - Arg, Rest, Frames, State);
parse_major(2, _AddInfo, Arg, Rest, Frames, State, _Depth, Opts) ->
    parse_bytes(Arg, Rest, Frames, State, Opts);
parse_major(3, _AddInfo, Arg, Rest, Frames, State, _Depth, Opts) ->
    parse_text(Arg, Rest, Frames, State, Opts);
parse_major(4, _AddInfo, Arg, Rest, Frames, State, Depth, Opts) ->
    start_array(Arg, Rest, Frames, State, Depth, Opts);
parse_major(5, _AddInfo, Arg, Rest, Frames, State, Depth, Opts) ->
    start_map(Arg, Rest, Frames, State, Depth, Opts);
parse_major(6, _AddInfo, Arg, Rest, Frames, State, Depth, Opts) ->
    start_tag(Arg, Rest, Frames, State, Depth, Opts);
parse_major(7, AddInfo, Arg, Rest, Frames, State, _Depth, Opts) ->
    case avm_cbor:simple(AddInfo, Arg, Rest, Opts) of
        {ok, Value, Rest1} -> emit_mode(Value, Rest1, Frames, State);
        {error, _} = Err -> Err
    end.

parse_bytes(N, Bin, Frames, State, Opts) ->
    case avm_cbor:check_string_byte_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<Chunk:N/binary, Rest/binary>> = Bin,
                    emit_mode(Chunk, Rest, Frames, State1);
                {ok, _State1} -> {error, truncated}
            end
    end.

parse_text(N, Bin, Frames, State, Opts) ->
    case avm_cbor:check_string_byte_limit(N, Opts) of
        {error, _} = Err -> Err;
        ok ->
            case avm_cbor:consume_string_bytes(N, State) of
                {error, _} = Err -> Err;
                {ok, State1} when byte_size(Bin) >= N ->
                    <<Chunk:N/binary, Rest/binary>> = Bin,
                    next_mode({validate_text, Chunk, Chunk, Rest, Frames, State1});
                {ok, _State1} -> {error, truncated}
            end
    end.

start_array(0, Rest, Frames, State, _Depth, _Opts) ->
    emit_mode([], Rest, Frames, State);
start_array(N, Rest, Frames, State, Depth, Opts) ->
    case ensure_declared_items(N, Rest, State) of
        {error, _} = Err -> Err;
        ok ->
            NewDepth = Depth + 1,
            case avm_cbor:check_depth(NewDepth, Opts) of
                ok ->
                    next_mode({next, Rest,
                        [{array, N, [], NewDepth} | Frames], State, NewDepth});
                {error, _} = Err -> Err
            end
    end.

start_map(0, Rest, Frames, State, _Depth, _Opts) ->
    emit_mode({map, []}, Rest, Frames, State);
start_map(N, Rest, Frames, State, Depth, Opts) ->
    case ensure_declared_items(N * 2, Rest, State) of
        {error, _} = Err -> Err;
        ok ->
            NewDepth = Depth + 1,
            case avm_cbor:check_depth(NewDepth, Opts) of
                {error, _} = Err -> Err;
                ok ->
                    Previous = case avm_cbor:requires_deterministic_decode(Opts) of
                        true -> none;
                        false -> unchecked
                    end,
                    next_mode({next, Rest,
                        [{map_key, N, [], NewDepth, Previous, Rest} | Frames],
                        State, NewDepth})
            end
    end.

start_tag(Tag, Rest, Frames, State, Depth, Opts) ->
    case ?CBOR_FLAG_ENABLED(Opts, ?CBOR_FLAG_ALLOW_TAGS) of
        false -> {error, {unsupported_tag, Tag}};
        true ->
            case ensure_declared_items(1, Rest, State) of
                {error, _} = Err -> Err;
                ok ->
                    NewDepth = Depth + 1,
                    case avm_cbor:check_depth(NewDepth, Opts) of
                        ok ->
                            next_mode({next, Rest, [{tag, Tag} | Frames], State, NewDepth});
                        {error, _} = Err -> Err
                    end
            end
    end.

ensure_declared_items(Needed, Bin, State) ->
    case avm_cbor:ensure_node_budget(Needed, State) of
        {error, _} = Err -> Err;
        ok -> declared_input_check(Needed, Bin)
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

step_emit(Value, Rest, [], _State) ->
    {done, Value, Rest};
step_emit(Value, Rest, [{tag, Tag} | Tail], State) ->
    emit_mode({tag, Tag, Value}, Rest, Tail, State);
step_emit(Value, Rest, [{array, Remaining, Acc, Depth} | Tail], State) ->
    case Remaining of
        1 -> next_reverse([Value | Acc], array, Rest, Tail, State);
        _ ->
            next_mode({next, Rest,
                [{array, Remaining - 1, [Value | Acc], Depth} | Tail], State, Depth})
    end;
step_emit(Value, Rest, [{indef_array, Acc, Depth} | Tail], State) ->
    next_mode({next, Rest, [{indef_array, [Value | Acc], Depth} | Tail], State, Depth});
step_emit(Key, Rest,
          [{map_key, Remaining, Acc, Depth, Previous, KeyInput} | Tail], State) ->
    case next_map_previous(Previous, KeyInput, Rest) of
        {error, _} = Err -> Err;
        {ok, Previous1} ->
            next_mode({next, Rest,
                [{map_value, Remaining, Acc, Depth, Previous1, Key} | Tail],
                State, Depth})
    end;
step_emit(Value, Rest,
          [{map_value, Remaining, Acc, Depth, Previous, Key} | Tail], State) ->
    Acc1 = [{Key, Value} | Acc],
    case Remaining of
        1 -> next_reverse(Acc1, map, Rest, Tail, State);
        _ ->
            next_mode({next, Rest,
                [{map_key, Remaining - 1, Acc1, Depth, Previous, Rest} | Tail],
                State, Depth})
    end;
step_emit(Key, Rest, [{indef_map_key, Acc, Depth} | Tail], State) ->
    next_mode({next, Rest,
        [{indef_map_value, Acc, Depth, Key} | Tail], State, Depth});
step_emit(Value, Rest, [{indef_map_value, Acc, Depth, Key} | Tail], State) ->
    next_mode({next, Rest,
        [{indef_map_key, [{Key, Value} | Acc], Depth} | Tail], State, Depth});
step_emit(_Value, _Rest, _Frames, _State) ->
    {error, invalid_continuation}.

next_map_previous(unchecked, _KeyInput, _Rest) ->
    {ok, unchecked};
next_map_previous(Previous, KeyInput, Rest) ->
    KeyLength = byte_size(KeyInput) - byte_size(Rest),
    case KeyLength >= 0 of
        false -> {error, invalid_continuation};
        true ->
            <<KeyBytes:KeyLength/binary, _/binary>> = KeyInput,
            case avm_cbor:check_deterministic_map_key(Previous, KeyBytes) of
                ok -> {ok, KeyBytes};
                {error, _} = Err -> Err
            end
    end.

step_validate_text(Whole, Scan, Rest, Frames, State) ->
    case validate_utf8_segment(Scan, ?TEXT_SCAN_BYTES) of
        done -> emit_mode({text, Whole}, Rest, Frames, State);
        {more, Scan1} ->
            next_mode({validate_text, Whole, Scan1, Rest, Frames, State});
        {error, _} = Err -> Err
    end.

step_validate_indef_text(Whole, Scan, Rest, Tail, State, Depth, Size, Acc) ->
    case validate_utf8_segment(Scan, ?TEXT_SCAN_BYTES) of
        done ->
            next_mode({next, Rest,
                [{indef_text, Size, [Whole | Acc]} | Tail], State, Depth});
        {more, Scan1} ->
            next_mode({validate_indef_text, Whole, Scan1, Rest,
                Tail, State, Depth, Size, Acc});
        {error, _} = Err -> Err
    end.

step_indef_string(Kind, Bin, Size, Acc, Tail, State, Depth) ->
    case avm_cbor:consume_node(State) of
        {error, _} = Err -> Err;
        {ok, State1} ->
            case definite_string_chunk(Kind, Bin) of
                {error, _} = Err -> Err;
                {ok, N, Body} ->
                    NewSize = Size + N,
                    Opts = avm_cbor:decode_opts(State1),
                    case avm_cbor:check_string_byte_limit(NewSize, Opts) of
                        {error, _} = Err -> Err;
                        ok ->
                            case avm_cbor:consume_string_bytes(N, State1) of
                                {error, _} = Err -> Err;
                                {ok, State2} when byte_size(Body) >= N ->
                                    <<Chunk:N/binary, Rest/binary>> = Body,
                                    continue_indef_string(
                                        Kind, Chunk, Rest, NewSize, Acc,
                                        Tail, State2, Depth);
                                {ok, _State2} -> {error, truncated}
                            end
                    end
            end
    end.

continue_indef_string(bytes, Chunk, Rest, NewSize, Acc, Tail, State, Depth) ->
    next_mode({next, Rest,
        [{indef_bytes, NewSize, [Chunk | Acc]} | Tail], State, Depth});
continue_indef_string(text, Chunk, Rest, NewSize, Acc, Tail, State, Depth) ->
    next_mode({validate_indef_text, Chunk, Chunk, Rest,
        Tail, State, Depth, NewSize, Acc}).

definite_string_chunk(Kind, <<First:8, Rest/binary>>) ->
    Expected = case Kind of bytes -> 2; text -> 3 end,
    MajorType = First bsr 5,
    AddInfo = First band 16#1F,
    case MajorType =:= Expected andalso AddInfo < 28 of
        false -> {error, {invalid_indefinite_chunk, expected_string_kind(Kind)}};
        true -> avm_cbor:arg(AddInfo, Rest)
    end;
definite_string_chunk(_Kind, <<>>) ->
    {error, truncated}.

expected_string_kind(bytes) -> expected_byte_string;
expected_string_kind(text) -> expected_text_string.

next_reverse(Source, Kind, Rest, Frames, State) ->
    next_mode({reverse, Source, [], Kind, Rest, Frames, State}).

step_reverse(Source, Dest, Kind, Rest, Frames, State) ->
    case reverse_segment(Source, Dest, ?REVERSE_ITEMS) of
        {more, Source1, Dest1} ->
            next_mode({reverse, Source1, Dest1, Kind, Rest, Frames, State});
        {done, Result} ->
            finish_reverse(Kind, Result, Rest, Frames, State)
    end.

reverse_segment(Source, Dest, 0) -> {more, Source, Dest};
reverse_segment([], Dest, _Remaining) -> {done, Dest};
reverse_segment([Head | Tail], Dest, Remaining) ->
    reverse_segment(Tail, [Head | Dest], Remaining - 1).

finish_reverse(array, Values, Rest, Frames, State) ->
    emit_mode(Values, Rest, Frames, State);
finish_reverse(map, Pairs, Rest, Frames, State) ->
    emit_mode({map, Pairs}, Rest, Frames, State);
finish_reverse(indef_bytes, Chunks, Rest, Frames, State) ->
    next_mode({join_binary, Chunks, bytes, Rest, Frames, State});
finish_reverse(indef_text, Chunks, Rest, Frames, State) ->
    next_mode({join_binary, Chunks, text, Rest, Frames, State}).

step_join_binary(Chunks, bytes, Rest, Frames, State) ->
    emit_mode(list_to_binary(Chunks), Rest, Frames, State);
step_join_binary(Chunks, text, Rest, Frames, State) ->
    emit_mode({text, list_to_binary(Chunks)}, Rest, Frames, State).

validate_utf8_segment(Bin, Limit) when Limit =< 0 -> {more, Bin};
validate_utf8_segment(<<>>, _Limit) -> done;
validate_utf8_segment(<<B, Rest/binary>>, Limit) when B < 16#80 ->
    validate_utf8_segment(Rest, Limit - 1);
validate_utf8_segment(<<B, C, Rest/binary>>, Limit)
  when B >= 16#C2, B =< 16#DF, C >= 16#80, C =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 2);
validate_utf8_segment(<<16#E0, C, D, Rest/binary>>, Limit)
  when C >= 16#A0, C =< 16#BF, D >= 16#80, D =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 3);
validate_utf8_segment(<<B, C, D, Rest/binary>>, Limit)
  when B >= 16#E1, B =< 16#EC,
       C >= 16#80, C =< 16#BF, D >= 16#80, D =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 3);
validate_utf8_segment(<<16#ED, C, D, Rest/binary>>, Limit)
  when C >= 16#80, C =< 16#9F, D >= 16#80, D =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 3);
validate_utf8_segment(<<B, C, D, Rest/binary>>, Limit)
  when B >= 16#EE, B =< 16#EF,
       C >= 16#80, C =< 16#BF, D >= 16#80, D =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 3);
validate_utf8_segment(<<16#F0, C, D, E, Rest/binary>>, Limit)
  when C >= 16#90, C =< 16#BF,
       D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 4);
validate_utf8_segment(<<B, C, D, E, Rest/binary>>, Limit)
  when B >= 16#F1, B =< 16#F3,
       C >= 16#80, C =< 16#BF,
       D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 4);
validate_utf8_segment(<<16#F4, C, D, E, Rest/binary>>, Limit)
  when C >= 16#80, C =< 16#8F,
       D >= 16#80, D =< 16#BF, E >= 16#80, E =< 16#BF ->
    validate_utf8_segment(Rest, Limit - 4);
validate_utf8_segment(_Bin, _Limit) ->
    {error, invalid_utf8}.

next_mode(Mode) -> {next, #cbor_cont{mode = Mode}}.

emit_mode(Value, Rest, Frames, State) ->
    next_mode({emit, Value, Rest, Frames, State}).
