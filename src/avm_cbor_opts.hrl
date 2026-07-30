%% Private normalized option state shared by avm_cbor and avm_cbor_partial.
%% Public callers continue to use option proplists; recursive code uses this
%% fixed tuple so policy reads do not scan or rebuild lists.
-record(cbor_opts, {
    max_depth,
    max_items,
    max_bytes,
    max_string_bytes,
    max_total_string_bytes,
    max_string_size,
    flags
}).

%% Per-operation decode state.  The option record is immutable after the
%% public proplist has been normalized; only the two remaining budgets are
%% threaded through recursive decode and partial-measurement calls.
-record(cbor_decode_state, {
    opts,
    nodes_left,
    string_bytes_left
}).

-define(CBOR_FLAG_ALLOW_FLOATS, 1).
-define(CBOR_FLAG_ALLOW_SIMPLE, 2).
-define(CBOR_FLAG_ALLOW_TAGS, 4).
-define(CBOR_FLAG_ALLOW_INDEFINITE, 8).
-define(CBOR_FLAG_PREFERRED, 16).
-define(CBOR_FLAG_DETERMINISTIC, 32).
-define(CBOR_ALL_FLAGS, 63).

-define(CBOR_DEFAULT_FLAGS,
    (?CBOR_FLAG_ALLOW_FLOATS bor
     ?CBOR_FLAG_ALLOW_SIMPLE bor
     ?CBOR_FLAG_ALLOW_TAGS bor
     ?CBOR_FLAG_ALLOW_INDEFINITE)).

-define(CBOR_DEFAULT_OPTS, #cbor_opts{
    max_depth = 128,
    max_items = 4096,
    max_bytes = 1048576,
    max_string_bytes = 65536,
    max_total_string_bytes = 1048576,
    max_string_size = 0,
    flags = ?CBOR_DEFAULT_FLAGS
}).

-define(CBOR_PARTIAL_DEFAULT_OPTS, #cbor_opts{
    max_depth = 128,
    max_items = 64,
    max_bytes = 1048576,
    max_string_bytes = 65536,
    max_total_string_bytes = 1048576,
    max_string_size = 8192,
    flags = ?CBOR_DEFAULT_FLAGS
}).

%% Trusted immutable state for decode/1. Keeping the default budgets beside
%% the default options avoids rebuilding them from record field reads on every
%% hot-path call while preserving immutable per-call state threading.
-define(CBOR_DEFAULT_DECODE_STATE, #cbor_decode_state{
    opts = ?CBOR_DEFAULT_OPTS,
    nodes_left = 4096,
    string_bytes_left = 1048576
}).

%% A CBOR node consumes at least one input byte. For default decode/1 inputs no
%% larger than the 4096-node budget, the input size itself proves that the
%% global node bound cannot be exceeded, so recursive calls need not rebuild
%% the state record merely to decrement that already-proven budget.
-define(CBOR_SMALL_INPUT_DEFAULT_DECODE_STATE, #cbor_decode_state{
    opts = ?CBOR_DEFAULT_OPTS,
    nodes_left = input_size_proven,
    string_bytes_left = 1048576
}).

-define(CBOR_FLAG_ENABLED(Opts, Flag),
    (((Opts)#cbor_opts.flags band (Flag)) =/= 0)).
