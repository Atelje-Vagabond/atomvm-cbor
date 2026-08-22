# Changelog

## 0.3.0

### Added

- `partial_map_fold/3` and `partial_array_fold/3` for bounded, single-pass
  traversal of opaque container descriptors with explicit early termination.
- `partial_select/2`, `partial_map_find/2`, and `partial_array_nth/2` for
  selective map and array access without deep-decoding unselected values.
- `encode_with_size/1,2` for returning the encoded binary and its exact size
  from one encode operation.
- `encode_sequence/1,2` and `sequence_fold/3` for bounded RFC 8742 sequence
  production and consumption without requiring a result list.
- `validate_all/1,2` for validating exactly one complete CBOR item without
  materializing its nested Erlang value.

### Fixed

- Forged array and map descriptors whose stored count is absent now return the
  established structured error instead of allowing arithmetic exceptions in
  traversal helpers.

### Compatibility

- Existing term representations, continuation decoding, options, resource
  limits, and structured error contracts remain compatible.
- No runtime dependency, NIF, port, or transport API was added.

## 0.2.0

First Hex.pm release of package `atomvm_cbor` and OTP application `avm_cbor`.

### Added

- Partial/deferred decode and opaque descriptor accessors.
- Deterministic encode and strict deterministic decode validation.
- Preferred-serialization checks and output selection.
- Global node and cumulative string-byte budgets.
- Duplicate-map-key and encoded-key-order validation.
- Pull-based `decode_start/2` and budgeted `decode_continue/2` with an opaque
  explicit-frame continuation and no decoder-internal sleeps or yields.
- Public RFC, malformed-input, resource-bound, property, coverage, AtomVM, and benchmark runners.

### Improved

- Options are normalized once into fixed tuple/record state instead of repeatedly scanning recursive proplists.
- Malformed and truncated payloads return structured errors across full and partial paths.
- Large fixed-cost scalar containers use an independently capped native path;
  caller-raised limits cannot enlarge its speculative allocation, and every
  other representation retains the general bounded decoder.
- Host workloads and three of four attached-device common paths improved against the public `v0.1.1` baseline; ESP32-S3 `decode/1` measured 2.05% slower.
- Public term representations remain compatible with the historical API.

### Packaging

- Added Rebar3/Hex metadata for public package `atomvm_cbor`.
- Added ExDoc/HexDocs generation with source links targeting tag `0.2.0`.
- The pre-Hex Git revisions were never published to Hex.

## v0.1.1 (2026-06-27)

- Added a dependency-free benchmark runner and initial public benchmark policy.
- Added public release-check helpers and documentation.

## Initial pre-Hex revision (2026-06-27)

Initial public Git source baseline. This version was not published to Hex.pm.
