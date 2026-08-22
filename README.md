# atomvm-cbor

<p>
  <a href="https://github.com/Atelje-Vagabond/atomvm-cbor/actions/workflows/release-gate.yml"><img height="28" alt="Public Release Gate" src="https://img.shields.io/github/actions/workflow/status/Atelje-Vagabond/atomvm-cbor/release-gate.yml?branch=main&amp;event=push&amp;label=release%20gate&amp;style=flat"></a>
  <a href="https://github.com/Atelje-Vagabond/atomvm-cbor/blob/main/docs/benchmarks.md"><img height="28" alt="Line and branch coverage gate 95%" src="https://img.shields.io/github/actions/workflow/status/Atelje-Vagabond/atomvm-cbor/release-gate.yml?branch=main&amp;event=push&amp;label=coverage%20%E2%89%A595%25&amp;style=flat"></a>
  <a href="LICENSE"><img height="28" alt="MIT License" src="https://img.shields.io/github/license/Atelje-Vagabond/atomvm-cbor?style=flat"></a>
  <a href="https://www.erlang.org/"><img height="28" alt="Erlang OTP 25+" src="https://img.shields.io/badge/Erlang%2FOTP-25%2B-A90533?style=flat&amp;logo=erlang&amp;logoColor=white"></a>
  <a href="https://www.atomvm.net/"><img height="28" alt="AtomVM 0.6.6" src="https://img.shields.io/badge/AtomVM-0.6.6-5C2D91?style=flat"></a>
  <a href="https://buymeacoffee.com/ateljevagabond"><img height="28" alt="Buy Me a Coffee" src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?style=flat&amp;logo=buymeacoffee&amp;logoColor=FFDD00"></a>
</p>

A compact RFC 8949 CBOR encoder and decoder for AtomVM and constrained Erlang runtimes. It is pure Erlang, has no runtime dependencies, NIFs, or ports, and preserves the public `{text, Binary}` and `{map, Pairs}` representations.

Version 0.3.0 adds bounded descriptor traversal, selective extraction, sequence
encoding/folding, exact-size encoding, and complete-input validation. Version
0.2.0 was the first Hex.pm release; public Git tag `v0.1.1` was never published
to Hex.

## Installation

Rebar3 projects use the OTP application name `avm_cbor` and Hex package name `atomvm_cbor`:

```erlang
{deps, [
    {avm_cbor, "~> 0.3.0", {pkg, atomvm_cbor}}
]}.
```

Mix projects use:

```elixir
{:avm_cbor, "~> 0.3.0", hex: :atomvm_cbor}
```

## Capabilities

- All CBOR major types, UTF-8 validation, semantic-tag passthrough, and half/32/64-bit float decode.
- Definite and bounded indefinite-length strings, arrays, and maps.
- Preferred serialization and deterministic encoding/validation under explicit options.
- Duplicate-map-key rejection and encoded-key ordering checks in deterministic decode.
- Full decode, pull-based continuation decode, complete-input decode, bounded
  CBOR sequence encode/decode/fold, and deferred partial decode.
- Single-pass partial map/array folds, selective map lookup, and indexed array
  access without deep-decoding unselected values.
- Depth, node, input-byte, per-string, cumulative-string, and partial-string limits.
- Structured errors for malformed, truncated, unsupported, and resource-bound inputs.
- OTP 25+ and AtomVM 0.6.6 compatibility.

## Attached-device benchmarks

Lower timings are better. The common encode/decode results compare the exact
public `v0.1.1` baseline with `0.2.0` using the same CBOR payload and AtomVM
0.6.6 harness on each device. See the [benchmark methodology](docs/benchmarks.md)
and the [full 0.2.0 validation report](docs/benchmarks/0.2.0.md) for complete
provenance, hardware details, soak results, and reproduction guidance.

| Board | Function | v0.1.1 µs | 0.2.0 µs | Change |
|---|---:|---:|---:|---:|
| ESP32-S3 (8 MB PSRAM) | `encode/1` | 8705.82 | 7120.54 | 18.21% faster |
| ESP32-S3 (8 MB PSRAM) | `decode/1` | 8508.98 | 8683.68 | 2.05% slower |
| RP2040 (16 MB flash) | `encode/1` | 7248.56 | 5118.92 | 29.38% faster |
| RP2040 (16 MB flash) | `decode/1` | 7105.50 | 6400.78 | 9.92% faster |
| WaveShare ESP32-S3-DEV-KIT-N32R16V | `encode/1` | 6080.32 | 4064.56 | 33.15% faster |
| WaveShare ESP32-S3-DEV-KIT-N32R16V | `decode/1` | 5853.32 | 4600.30 | 21.41% faster |

The partial/deferred APIs are new in `0.2.0`, so no `v0.1.1` measurements
exist for them.

| Function | ESP32-S3 0.2.0 µs | RP2040 0.2.0 µs | WaveShare N32R16V 0.2.0 µs |
|---|---:|---:|---:|
| `partial_decode/1` | 13109.00 | 9875.48 | 7518.24 |
| `partial_decode/2` | 13326.80 | 9928.18 | 7570.60 |
| `partial_deep_decode/1` | 10805.88 | 8243.96 | 5911.32 |
| `partial_value_bytes/1` | 767.53 | 579.66 | 562.63 |
| `partial_contents/1` | 959.06 | 506.69 | 607.53 |
| `partial_skip/1` | 380.07 | 228.66 | 295.30 |
| `partial_type/1` | 382.08 | 229.65 | 295.48 |
| `partial_count/1` | 381.27 | 229.65 | 296.33 |
| `partial_tag/1` | 438.55 | 253.83 | 360.91 |
| `partial_size/1` | 455.71 | 260.95 | 382.75 |
| `partial_offset/1` | 379.89 | 227.56 | 296.28 |
| `partial_length/1` | 382.62 | 234.45 | 295.84 |

The older ESP32-S3 `decode/1` regression is measured and reproducible. It is
accepted under the unchanged 5% release threshold because `0.2.0` retains the
new fail-closed node and string-byte accounting on this general decode path.
The same workload improves on RP2040 and WaveShare, so no single hardware or
security-check cause is claimed. The full report includes the complete
technical interpretation and maximum-bound testing.

## Public term representation

| CBOR value | Erlang value |
|---|---|
| unsigned or negative integer | integer |
| byte string | binary |
| text string | `{text, Binary}` |
| array | list |
| map | `{map, [{Key, Value}, ...]}` |
| semantic tag | `{tag, Number, Value}` |
| boolean/null/undefined | `true`, `false`, `null`, `undefined` |
| simple value | `{simple, Number}` |
| float | float |

## Core API

```erlang
avm_cbor:decode(Binary).
avm_cbor:decode(Binary, Options).
avm_cbor:decode_all(Binary, Options).
avm_cbor:decode_sequence(Binary, Options).
avm_cbor:sequence_fold(Binary, Fun, Acc).
avm_cbor:encode(Value, Options).
avm_cbor:encode_with_size(Value, Options).
avm_cbor:encode_sequence(Values, Options).
avm_cbor:validate_all(Binary, Options).
```

`decode/1,2` consumes one value and returns `{ok, Value, Rest}`. `decode_all/1,2` requires a complete input. `decode_sequence/1,2` returns all complete sequence items and retains a truncated final item as `Rest`.

`encode_with_size/1,2` returns `{ok, Binary, Size}` from the real encode
operation. `encode_sequence/1,2` emits concatenated RFC 8742 items while
enforcing the configured item and total-byte limits. `sequence_fold/3` consumes
complete sequence items with `{cont, NewAcc}` or `{halt, Result}` callbacks.
`validate_all/1,2` validates exactly one complete item and rejects trailing
bytes without constructing its nested Erlang value.

### Pull-based continuation decode

```erlang
{ok, State0} = avm_cbor:decode_start(Binary, Options),
case avm_cbor:decode_continue(State0, Budget) of
    {done, Value, Rest} -> use(Value, Rest);
    {more, State1} -> schedule_next(State1);
    {error, Reason} -> reject(Reason)
end.
```

`Budget` is a positive bound on explicit parser transitions. The returned state
is immutable and opaque. The decoder never sleeps or yields; event-loop pacing
belongs to the caller. This is not a streaming-input API: `Binary` must already
exist when `decode_start/2` is called.

## Partial and deferred decode

`partial_decode/1,2` validates and measures one value without eagerly constructing nested Erlang terms. It returns an opaque descriptor; callers must use the public accessors rather than matching its internal shape.

```erlang
{ok, Descriptor, Rest} = avm_cbor:partial_decode(Binary),
Type = avm_cbor:partial_type(Descriptor),
Length = avm_cbor:partial_length(Descriptor),
{ok, Value} = avm_cbor:partial_deep_decode(Descriptor).
```

Available accessors are `partial_value_bytes/1`, `partial_deep_decode/1`, `partial_skip/1`, `partial_type/1`, `partial_count/1`, `partial_tag/1`, `partial_size/1`, `partial_offset/1`, `partial_length/1`, and `partial_contents/1`.

Maps and arrays can be traversed without deep-decoding unselected values:

```erlang
{ok, MapDescriptor, <<>>} = avm_cbor:partial_decode(Binary),
{ok, ValueDescriptor} = avm_cbor:partial_map_find(MapDescriptor, Key),
{ok, Value} = avm_cbor:partial_deep_decode(ValueDescriptor).
```

`partial_map_fold/3` and `partial_array_fold/3` support `{cont, NewAcc}` and
`{halt, Result}` callbacks. `partial_select/2` finds a small requested key set
in one map pass, `partial_map_find/2` returns the first matching value
descriptor, and `partial_array_nth/2` uses a zero-based index.

## Options and limits

| Option | Default | Partial default | Purpose |
|---|---:|---:|---|
| `max_depth` | 128 | 128 | nesting depth |
| `max_items` | 4096 | 64 | global node/work budget |
| `max_bytes` | 1048576 | 1048576 | input/output bytes |
| `max_string_bytes` | 65536 | 65536 | one string or chunk |
| `max_total_string_bytes` | 1048576 | 1048576 | cumulative decoded string bytes |
| `max_string_size` | not used | 8192 | partial byte/text content |
| `allow_floats` | `true` | `true` | float support |
| `allow_simple` | `true` | `true` | simple values |
| `allow_tags` | `true` | `true` | semantic tags |
| `allow_indefinite` | `true` | `true` | indefinite-length values |
| `preferred` | `false` | `false` | preferred serialization checks/output |
| `deterministic` | `false` | `false` | deterministic encoding and strict decode validation |

Options are normalized once into fixed internal state. Recursive paths do not repeatedly scan or rebuild option proplists.

`deterministic=true` rejects indefinite-length input, non-preferred width choices, duplicate map keys, and map keys not ordered by their original encoded bytes. `ble_options/0` provides a stricter device-oriented profile.

Treat options as trusted application policy. Do not allow a network client to
raise them. Enforce the same or a smaller byte ceiling at transport ingress
before buffering the complete request, use a lower fixed profile on targets
that cannot allocate the defaults, and require empty trailing `Rest` for
protocols that permit exactly one item.

Large definite containers made entirely of preferred one-byte unsigned values
use a bounded fixed-cost path. It is independently capped at 4095 direct nodes,
so caller-raised limits cannot turn it into an unbounded speculative
allocation. Mixed, malformed, deterministic, nested, multi-byte, or larger
containers use the general bounded decoder and retain the same errors.

## Documentation and validation

- [API guide](docs/api.md)
- [Decoder policy and security limits](docs/decoder-policy.md)
- [Pinned AtomVM memory evidence](docs/atomvm-memory-internals.md)
- [Benchmark methodology](https://github.com/Atelje-Vagabond/atomvm-cbor/blob/main/docs/benchmarks.md)
- [0.3.0 benchmark report](docs/benchmarks/0.3.0.md)
- [Changelog](CHANGELOG.md)

Run the public validation suite:

```bash
scripts/release-check.sh 0.3.0
```

Run the reproducible host benchmark:

```bash
scripts/bench.sh
```

Benchmark values depend on the host, OTP version, and architecture. Published comparisons are measured context, not guarantees for other devices.

## License

MIT. See [LICENSE](LICENSE).
