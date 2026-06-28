# AtomVM CBOR

A compact RFC 8949 CBOR encoder/decoder for AtomVM and constrained Erlang runtimes.

Designed for BLE-friendly device payloads on ESP32, with controlled error handling and no NIFs, ports, or complex OTP dependencies.

## Features

- Decode and encode all major CBOR types
- UTF-8 validation for text strings
- Semantic tag passthrough (`{tag, N, Value}`)
- Half-precision float (IEEE 754 binary16) decode
- Bounded indefinite-length decode (byte strings, text strings, arrays, maps)
- CBOR sequence helpers (`decode_all`, `decode_sequence`)
- BLE-safe profile with strict limits (`ble_options/0`)
- Controlled errors — never crash on malicious input
- Pure Erlang, no NIFs, no ports, no `unicode`, `re`, or Erlang maps
- Compatible with OTP 25+ and AtomVM 0.6.6+

## Supported subset

| Major type | CBOR type | Erlang representation | Notes |
|---|---|---|---|
| 0 | Unsigned integer | `N` (non-neg integer) | 0..2^64-1 |
| 1 | Negative integer | `-N-1` (negative integer) | -1..-2^64 |
| 2 | Byte string | `Bin` (binary) | Length ≤ max_string_bytes |
| 3 | Text string | `{text, Bin}` | UTF-8 validated on decode, ≤ max_string_bytes |
| 4 | Array | `[Item, ...]` | Items ≤ max_items |
| 5 | Map | `{map, [{K,V}, ...]}` | Pairs ≤ max_items |
| 6 | Tag | `{tag, N, Value}` | Passthrough, controlled by `allow_tags` |
| 7 | False / True / Null / Undefined | `false` / `true` / `null` / `undefined` | |
| 7 | Simple values | `{simple, N}` | 0..255 |
| 7 | Float (16/32/64-bit) | `F` (float) | Decode all widths; encode as 64-bit double |

## Limitations

- Floats always encode as 64-bit IEEE 754 double
- Half-precision decode only (not encode)
- No canonical CBOR output
- No streaming or feed-based parser
- Tags passthrough as `{tag, N, Value}` — no semantic interpretation (use `get`/`require` helpers to process)

## API

### Decode

```erlang
avm_cbor:decode(Bin)                         -> {ok, Value, Rest} | {error, Reason}
avm_cbor:decode(Bin, Options)                -> {ok, Value, Rest} | {error, Reason}
avm_cbor:decode_all(Bin)                     -> {ok, [Value]} | {error, Reason}
avm_cbor:decode_all(Bin, Options)            -> {ok, [Value]} | {error, Reason}
avm_cbor:decode_sequence(Bin)                -> {ok, [Value], Rest} | {error, Reason}
avm_cbor:decode_sequence(Bin, Options)       -> {ok, [Value], Rest} | {error, Reason}
```

`decode` reads one CBOR item and returns `{ok, Value, Rest}` where `Rest` is the unconsumed trailing binary.

`decode_all` strictly consumes a complete CBOR sequence and returns `{ok, Values}` only when the entire binary is consumed.

`decode_sequence` consumes as many complete CBOR items as possible and returns `{ok, Values, Rest}` where `Rest` is trailing incomplete data. A truncated final item produces a `Rest`; a malformed final item (e.g., unexpected break byte) returns an error.

### Encode

```erlang
avm_cbor:encode(Value)                       -> {ok, Binary} | {error, Reason}
avm_cbor:encode(Value, Options)              -> {ok, Binary} | {error, Reason}
```

Integer encoding always uses the shortest CBOR definite-length form.

### Options

| Key | Type | Default | BLE | Description |
|---|---|---|---|---|
| `max_depth` | non-neg int | 128 | 8 | Max nesting depth (0 = unlimited) |
| `max_items` | non-neg int | 4096 | 64 | Max items in arrays/maps |
| `max_bytes` | non-neg int | 0 | 512 | Max input binary bytes (0 = unlimited) |
| `max_string_bytes` | non-neg int | 65536 | 128 | Max string/byte length |
| `allow_floats` | boolean | true | false | Accept float payloads |
| `allow_simple` | boolean | true | true | Accept simple values |
| `allow_tags` | boolean | true | false | Accept CBOR tags |
| `allow_indefinite` | boolean | true | false | Accept indefinite-length items |

**Errors**: always returned as `{error, Reason}` — never crash on malicious input.

### Helpers

```erlang
avm_cbor:get(Key, {map, Pairs})              -> {ok, Value} | error
avm_cbor:get(Key, {map, Pairs}, Default)     -> Value | Default
avm_cbor:require(Key, {map, Pairs})          -> {ok, Value} | {error, {missing_key, Key}}
avm_cbor:as_text({text, Bin})                -> {ok, Bin} | {error, bad_type}
avm_cbor:as_bytes(Bin)                       -> {ok, Bin} | {error, bad_type}
avm_cbor:as_int(N)                           -> {ok, N} | {error, bad_type}
avm_cbor:as_bool(true|false)                 -> {ok, Bool} | {error, bad_type}
```

### BLE profile

```erlang
avm_cbor:ble_options() -> proplist()
```

Returns strict limits for BLE advertising/scan-response payloads.

## Examples

```erlang
%% Decode a simple integer
{ok, 42, <<>>} = avm_cbor:decode(<<24, 42>>).

%% Decode with strict BLE limits
{error, {max_bytes_exceeded, 512}} =
    avm_cbor:decode(LargePayload, avm_cbor:ble_options()).

%% Decode a tagged value
{ok, {tag, 1, {text, <<"hello">>}}, <<>>} =
    avm_cbor:decode(<<193, 101, 104, 101, 108, 108, 111>>).

%% Decode a CBOR sequence
{ok, [1, 2, 3]} = avm_cbor:decode_all(<<1, 2, 3>>).

%% Encode a structured payload
{ok, Bin} = avm_cbor:encode({map, [
    {1, {text, <<"set_wifi">>}},
    {2, {text, <<"MySSID">>}},
    {3, <<"secret">>}
]}).

%% Access decoded map values
{ok, {map, Pairs}, <<>>} = avm_cbor:decode(<<...>>),
{ok, <<"set_wifi">>} = avm_cbor:get(1, {map, Pairs}),
<<"default">>       = avm_cbor:get(99, {map, Pairs}, <<"default">>),
{ok, 42}            = avm_cbor:require(3, {map, Pairs}),

%% Type-safe extraction
{ok, <<"hello">>} = avm_cbor:as_text({text, <<"hello">>}),
{ok, <<"bytes">>} = avm_cbor:as_bytes(<<"bytes">>),
{ok, 42}          = avm_cbor:as_int(42),
{ok, true}        = avm_cbor:as_bool(true).
```

## Benchmarks

```bash
scripts/bench.sh
```

Run a reproducible host-side benchmark suite for decode and encode workloads.

These are OTP host-side microbenchmarks. They are intended as reproducible baseline measurements, not ESP32 runtime performance guarantees.

See [docs/benchmarks.md](docs/benchmarks.md) for details and release benchmark policy.

## Testing

```bash
# Compile and run smoke tests
erlc -o /tmp src/avm_cbor.erl
erlc -o /tmp test/avm_cbor_smoke.erl
erl -noshell -pa /tmp -eval 'avm_cbor_smoke:run().'

# AtomVM validation (requires atomvm binary)
erlc -o /tmp src/avm_cbor.erl
erlc -o /tmp test/avm_cbor_atomvm.erl
atomvm /tmp/avm_cbor.beam /tmp/avm_cbor_atomvm.beam /path/to/atomvmlib.avm
```

## CI

Pull requests run two jobs:

1. **basic** — doc existence, smoke tests on OTP 27
2. **atomvm** — all tests validated on official AtomVM release binary

ESP-IDF firmware build validation is available as a manually triggered workflow.

## Release

```bash
git tag v$(cat VERSION)
git push origin v$(cat VERSION)
```

## AtomVM notes

- No Erlang maps, `unicode`, `re`, `io_lib`, `calendar`, `math`, `proplists`, `term_to_binary`, `binary_to_term`, NIFs, ports, or complex OTP used in the encode/decode path.
- `lists:reverse/1` is available on AtomVM; other `lists` functions (`keyfind/3`, `foldl/3`, `keydelete/3`) have local replacements.
- Binary construction with `bsl`/`bor` inside `<<>>` works the same as OTP.
- All decode errors return tuples; encode errors are caught with try/catch.
- Integer literals >= 2^60 should be computed rather than written as literals in source (AtomVM 0.6.6 crashes on COMPACT_NBITS_VALUE encoding from OTP 27).
