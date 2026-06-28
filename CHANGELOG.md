# Changelog

## v0.1.1 (2026-06-27)

- Added dependency-free benchmark runner (`bench/avm_cbor_bench.erl`, `scripts/bench.sh`)
- Added release benchmark policy and documentation (`docs/benchmarks.md`, `docs/benchmarks/v0.1.1.md`)
- Added release-check helper script (`scripts/release-check.sh`)
- Added Benchmarks section to README

## v0.1.0 (2026-06-27)

Initial public release.

### Features

- CBOR decode/encode for all major types except indefinite-length containers
- UTF-8 validation for text strings (rejects invalid continuation bytes, overlong encodings, surrogates, and codepoints above U+10FFFF)
- Semantic tag passthrough (`{tag, N, Value}`) with `allow_tags` option
- Half-precision float (IEEE 754 binary16) decode via additional info 25
- Bounded indefinite-length byte string, text string, array, and map decode with `allow_indefinite` option
- CBOR sequence helpers (`decode_all/1/2`, `decode_sequence/1/2`)
- BLE-safe profile (`ble_options/0`) with strict limits
- Controlled errors — decode/encode never crash on malicious input
- Pure Erlang, no NIFs, no ports, no `unicode`, `re`, or Erlang maps
- Compatible with OTP 25+ and AtomVM 0.6.6+

### Options

| Key | Default | BLE |
|---|---|---|
| `max_depth` | 128 | 8 |
| `max_items` | 4096 | 64 |
| `max_bytes` | 0 (unlimited) | 512 |
| `max_string_bytes` | 65536 | 128 |
| `allow_floats` | true | false |
| `allow_simple` | true | true |
| `allow_tags` | true | false |
| `allow_indefinite` | true | false |

### Limitations

- Text strings are validated as UTF-8 on decode; encode accepts arbitrary binaries as `{text, Bin}`
- Floats encode as 64-bit IEEE 754 double only
- Half-precision decode only (no half-precision encode)
- No canonical CBOR output
- No streaming or feed-based parser
- Tags are decoded as `{tag, N, Value}` tuples; no interpretation of tag semantics
