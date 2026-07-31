# Decoder policy and security limits

This document defines the decoder's public option contract, recursive charging
model, deterministic profile, and stable error behavior. Limits are explicit
policies supplied by the caller. They are not estimates of physical RAM or of
memory safely available to an AtomVM process.

## Option representation and operation scope

Public options are proplists. The library validates them and normalizes them
once into fixed-shape internal records before decoding. Recursive functions use
constant-time record fields; they do not search, rebuild, or convert proplists.
Duplicate options are last-wins.

Each public call is one operation. `decode_all/1,2` and
`decode_sequence/1,2` retain the same state across all top-level items.
`partial_decode/1,2` measures the complete represented item with one state, and
`partial_deep_decode/1` performs a separately bounded deep-decode operation
using the normalized policy stored in the validated opaque descriptor.

## Global node/work budget

`max_items` is a positive global node/work budget, not a per-container length.
The decoder charges each consumed node. Definite declarations must authorize
their direct-child allocation against the remaining budget before recursive
descent:

- one node for every scalar or definite string value;
- one node for every array or map container;
- one node for each array element;
- map keys and values independently;
- one node for a tag and another for its tagged value;
- one node for every indefinite string chunk;
- one node for every top-level sequence value.

Nested containers and later sequence items never reset the budget. For example,
`[[1,2],[3,4]]` consumes seven nodes: the outer array, two inner arrays, and
four integers. A budget of six fails with
`{error, {max_items_exceeded, 6}}`; seven succeeds.

The small-integer top-level sequence fast path carries the decremented
fixed-shape state after every value; it does not defer or batch budget updates.

Declared definite array/map lengths are checked against the remaining node
budget before child allocation or descent. Arrays require at least one
remaining node per declared child; maps require two per pair. The recursive
decoder still charges each child at consumption time.

### Fixed-cost definite-container optimization

Physical ESP32-S3 evidence showed that the general synchronous decoder spent
more than eight seconds dispatching the exact 4096-node flat integer array. The
idle task could not run during that single call, so the hardware watchdog fired.
The selected remedy is algorithmic: large definite arrays and
non-deterministic maps containing only preferred one-byte unsigned integers use the
pinned AtomVM native `erlang:binary_to_list/1` implementation after admission
checks and accept its result only after byte validation. Every other container
uses the unchanged general bounded loop. This removes repeated
option decoding, argument decoding, and state-record rebuilding for a common
fixed-cost subset. It adds no sleep, yield, scheduler call, watchdog change, or
PSRAM-dependent behavior.

The optimization is guarded by these invariants:

1. The public entry point checks the complete input against `max_bytes` before
   parsing.
2. The container node is charged normally. Its declared number of direct
   children must fit both the remaining `max_items` budget and the remaining
   input before the optimized loop begins. The fast path repeats the byte-size
   guard because the general parser may defer an insufficient-input result to
   preserve a more specific reserved-header or unexpected-break error.
3. Only preferred one-byte unsigned integers (`00`-`17`) use the native path. Each
   consumes exactly one input byte and exactly one node. The already-proven
   child budget therefore bounds both loop iterations and list allocation.
   Native conversion is attempted only for 64 through 4095 direct nodes; this
   independent internal ceiling prevents a caller-raised policy from turning a
   failed speculative conversion into unbounded temporary allocation.
4. Batched nodes are deducted before the loop returns or re-enters the general
   decoder. Nested descendants still consume their own nodes, so a declaration
   that fits but whose complete tree exceeds `max_items` still fails.
5. Negative, mixed, multi-byte, nested, string, float, simple, tag, indefinite,
   reserved, truncated, or malformed input returns to the unchanged general
   bounded decoder and retains its stable result.
6. Deterministic maps never use the pair fast path. Their original encoded key
   bytes continue through strict ordering and duplicate-key validation.

This is not a second unchecked decoder. It is a fixed-cost inner loop behind
the same admission checks and fallback. Exact-limit, one-over-limit,
insufficient-input, malformed, nested-budget, deterministic-map, and mixed-form
regressions exercise these boundaries on OTP; the compact array/map path is
also exercised by the AtomVM and physical maximum suites.

At pinned AtomVM commit `ff993a80963298b532c1e573f883951ecaac9fef`,
`erlang:binary_to_list/1` is registered in
[`nifs.gperf:51`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/nifs.gperf#L51).
Its implementation validates the binary, reserves exactly two heap words per
byte, and constructs the result in a native reverse loop in
[`nifs.c:1966-1984`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/nifs.c#L1966-L1984).
The decoder first bounds the candidate by declared children and its separate
4095-node ceiling, then verifies that every returned byte is a complete
preferred unsigned item before accepting the list.

## Untrusted request admission

Decoder options are trusted application policy. A network client must never be
allowed to supply or enlarge `max_items`, `max_bytes`, depth, or string limits.
Choose a fixed profile per endpoint; use `ble_options/0` or a stricter
application profile on constrained devices.

`max_bytes` rejects an oversized binary at the decoder boundary, but that
binary has already been allocated by the transport. HTTP, BLE, MQTT, socket,
or file-ingress code must enforce the same or smaller byte limit while reading,
before buffering the complete request. On targets whose physical memory is
smaller than the library default, the ingress and decoder profile must use a
target-specific lower ceiling.

For a request protocol that permits exactly one CBOR item, accept only
`{ok, Value, <<>>}` or `{done, Value, <<>>}`. Treat non-empty `Rest` as trailing
data and reject it; otherwise an attacker can append data that the application
did not authenticate or validate. Long-running MCU handlers should use the
continuation API with caller-owned scheduling, while retaining exactly the same
fixed resource profile.

At the default profile, an array with 4095 scalar children consumes exactly
4096 nodes and is admitted. A 4096-child array requires 4097 nodes and returns
`{error, {max_items_exceeded, 4096}}`. A tag plus a 2047-pair map consumes
exactly 4096 nodes; adding one pair exceeds the same global budget. Inputs above
1 MiB return `{error, {max_bytes_exceeded, 1048576}}` before parsing.

## String limits

`max_string_bytes` is the positive per-string limit.
`max_total_string_bytes` is a separate positive cumulative byte budget across
all byte/text strings and all indefinite chunks in the operation. Both checks
happen before slicing or retaining a chunk.

An indefinite string's complete length must fit `max_string_bytes`; each chunk
also decrements `max_total_string_bytes` and consumes one node. Chunks are held
in a bounded reverse list and combined once, avoiding repeated binary
concatenation and quadratic copying.

Partial decoding additionally applies positive `max_string_size` (default
8192) to the complete represented string.

## Depth and declared lengths

The top-level item starts at depth zero. Entering an array, map, or tag payload
increments depth by one, and `max_depth` is checked before recursive descent.
Values exactly at the configured depth are accepted; the next level fails with
`{error, {max_depth_exceeded, Limit}}`.

Before slicing or growing an accumulator, declared lengths are checked against
the remaining input, `max_bytes`, the relevant string limits, and remaining
node/work budget. Oversized or truncated declarations therefore fail without
allocation proportional to the declared size.

## Indefinite items

When `allow_indefinite` is true, indefinite arrays and maps use the same depth,
node, string, and input limits as definite items. Indefinite strings additionally
enforce chunk type and cumulative length:

- byte strings accept only definite byte-string chunks;
- text strings accept only definite UTF-8 text-string chunks;
- nested indefinite string chunks are rejected;
- a missing break is `truncated`;
- a break outside an indefinite context is `unexpected_break`;
- a map break after a key but before its value is `unexpected_break`.

Deterministic mode is stricter than the general indefinite-item policy. When
`deterministic` is true, byte strings, text strings, arrays, maps, nested
values, and partial-measurement inputs using additional-information value 31
are rejected with `{error, non_deterministic_indefinite}`. This prohibition
overrides `allow_indefinite = true` regardless of duplicate-option order.
Preferred mode alone does not impose this prohibition.

The constrained BLE profile disables indefinite items.

## Constrained embedded profile

`avm_cbor:ble_options/0` returns this proplist:

```erlang
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
]
```

The profile is fixed and caller-selected. The library does not call a physical
memory API, use a percentage of nominal RAM, detect PSRAM, or silently choose a
larger profile.

## RFC 8949 preferred and deterministic profile

- Integer arguments and definite lengths use their shortest encodings.
- Preferred/deterministic floats use the shortest exact binary16, binary32, or
  binary64 representation, including binary16 subnormals and signed zero.
- Infinity uses binary16 when the runtime can supply a non-finite float.
- The selected deterministic NaN encoding is binary16 `F9 7E 00`.
- Wider exactly representable float encodings are rejected in preferred decode
  mode with `{non_preferred_float, half | single}`.
- Deterministic map keys are ordered lexicographically by their complete encoded
  key bytes, including cases whose encoded lengths differ.
- Deterministic full and partial map decoding compares the original encoded key
  sub-binaries, not decoded Erlang terms. Keys must be strictly increasing;
  reversed keys return `non_deterministic_map_order` and identical encoded keys
  return `duplicate_map_key`. Each key is recursively validated before the
  ordering comparison.
- Deterministic decoding rejects all indefinite-length items. Preferred mode
  remains distinct and may accept indefinite items when `allow_indefinite` is
  true.

The supported BEAM/AtomVM decoder path does not expose NaN or infinity as
ordinary Erlang float values; those inputs return
`{error, {unsupported_simple_value, invalid_float}}`. Wider encodings can be
rejected for preferred width before that runtime representation check.

## Stable public decode errors

Every public decode entry point validates its untrusted boundary. It does not
wrap the complete decoder in a broad catch. Important stable results include:

| Condition | Result |
| :--- | :--- |
| Non-binary input | `{error, invalid_input}` |
| Non-list options | `{error, invalid_options_list}` |
| Unknown, mistyped, zero, or negative option | `{error, {invalid_option, Option}}` |
| Empty single/partial input | `{error, empty}` |
| Missing bytes or break | `{error, truncated}` |
| Reserved additional information | `{error, reserved_additional_info}` |
| Break in a definite context | `{error, unexpected_break}` |
| Invalid indefinite chunk type | `{error, {invalid_indefinite_chunk, Expected}}` |
| Indefinite item in deterministic mode | `{error, non_deterministic_indefinite}` |
| Deterministic map key is out of encoded-byte order | `{error, non_deterministic_map_order}` |
| Duplicate encoded deterministic map key | `{error, duplicate_map_key}` |
| Invalid text | `{error, invalid_utf8}` |
| Byte, node, depth, or string limit | `{error, {LimitName, ConfiguredLimit}}` |
| Disallowed float/tag/indefinite item | the corresponding stable policy error |
| Wider preferred integer/simple/float | the corresponding `non_preferred_*` error |
| Non-canonical deterministic NaN | `{error, {non_deterministic_nan, 16#7E00}}` |
| Forged partial descriptor | `{error, not_a_partial}` |
| Deep partial value with trailing bytes | `{error, {trailing_bytes, Count}}` |

Security compatibility corrections in this remediation are intentional:

- `max_items` now applies globally instead of resetting per container;
- zero limits are rejected rather than meaning unlimited;
- `max_total_string_bytes` adds a distinct cumulative bound;
- public non-binary inputs return `invalid_input` instead of raising;
- preferred float decoding now rejects wider exact equivalents.

## Coverage evidence

OTP `cover` measures executable lines. It does not provide true source branch
coverage, so `scripts/branch-coverage.escript` compiles a test-only transformed
copy of the two source modules and counts these actual outcomes:

- case, if, multi-clause function, and anonymous-function selection;
- complete guard true/false results;
- `andalso` and `orelse` short-circuit outcomes;
- try success and exception handlers.

The production modules are not instrumented. `scripts/coverage-gate.sh`
requires at least 95% total line coverage, total true branch coverage,
changed-line coverage, and changed-branch coverage. The defined parsing,
budget, public-boundary, and RFC functions require 100% line and branch
coverage. Machine-readable evidence is written to `coverage/lines.json` and
`coverage/branches.json`; `coverage/uncovered.txt` lists every uncovered line
and branch.

The deterministic indefinite-policy gate, original-key capture, AtomVM-safe
bytewise comparator, full map loop, and partial measuring map loop are all in
the 100% critical line/true-branch set.

The reproducible randomized suite uses seed `{2026,7,30}`. Any randomized
failure reports that seed and a counterexample minimized by the suite's binary
or Erlang-term shrinker.

