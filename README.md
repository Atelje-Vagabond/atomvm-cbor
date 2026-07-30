# atomvm-cbor

[![Public Release Gate](https://github.com/Atelje-Vagabond/atomvm-cbor/actions/workflows/release-gate.yml/badge.svg?branch=main)](https://github.com/Atelje-Vagabond/atomvm-cbor/actions/workflows/release-gate.yml)
![Line coverage](https://img.shields.io/badge/line%20coverage-99.59%25-brightgreen)
![Branch coverage](https://img.shields.io/badge/branch%20coverage-99.36%25-brightgreen)

A compact RFC 8949 CBOR encoder and decoder for AtomVM and constrained Erlang runtimes. It is pure Erlang, has no runtime dependencies, NIFs, or ports, and preserves the public `{text, Binary}` and `{map, Pairs}` representations.

Version 0.2.0 is the first Hex.pm release. Historical Git tag `v0.1.0` remains a source and benchmark baseline only and was never published to Hex.

## Installation

Rebar3 projects use the OTP application name `avm_cbor` and Hex package name `atomvm_cbor`:

```erlang
{deps, [
    {avm_cbor, "~> 0.2.0", {pkg, atomvm_cbor}}
]}.
```

Mix projects use:

```elixir
{:avm_cbor, "~> 0.2.0", hex: :atomvm_cbor}
```

## Capabilities

- All CBOR major types, UTF-8 validation, semantic-tag passthrough, and half/32/64-bit float decode.
- Definite and bounded indefinite-length strings, arrays, and maps.
- Preferred serialization and deterministic encoding/validation under explicit options.
- Duplicate-map-key rejection and encoded-key ordering checks in deterministic decode.
- Full decode, complete-input decode, CBOR sequence decode, and deferred partial decode.
- Depth, node, input-byte, per-string, cumulative-string, and partial-string limits.
- Structured errors for malformed, truncated, unsupported, and resource-bound inputs.
- OTP 25+ and AtomVM 0.6.6 compatibility.

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
avm_cbor:encode(Value, Options).
```

`decode/1,2` consumes one value and returns `{ok, Value, Rest}`. `decode_all/1,2` requires a complete input. `decode_sequence/1,2` returns all complete sequence items and retains a truncated final item as `Rest`.

## Partial and deferred decode

`partial_decode/1,2` validates and measures one value without eagerly constructing nested Erlang terms. It returns an opaque descriptor; callers must use the public accessors rather than matching its internal shape.

```erlang
{ok, Descriptor, Rest} = avm_cbor:partial_decode(Binary),
Type = avm_cbor:partial_type(Descriptor),
Length = avm_cbor:partial_length(Descriptor),
{ok, Value} = avm_cbor:partial_deep_decode(Descriptor).
```

Available accessors are `partial_value_bytes/1`, `partial_deep_decode/1`, `partial_skip/1`, `partial_type/1`, `partial_count/1`, `partial_tag/1`, `partial_size/1`, `partial_offset/1`, `partial_length/1`, and `partial_contents/1`.

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

## Documentation and validation

- [API guide](docs/api.md)
- [Benchmark methodology](docs/benchmarks.md)
- [Changelog](CHANGELOG.md)

Run the public validation suite:

```bash
scripts/release-check.sh 0.2.0
```

Run the reproducible host benchmark:

```bash
scripts/bench.sh
```

Benchmark values depend on the host, OTP version, and architecture. Published comparisons are measured context, not guarantees for other devices.

## License

MIT. See [LICENSE](LICENSE).
