# Changelog

## 0.2.0

First Hex.pm release of package `atomvm_cbor` and OTP application `avm_cbor`.

### Added

- Partial/deferred decode and opaque descriptor accessors.
- Deterministic encode and strict deterministic decode validation.
- Preferred-serialization checks and output selection.
- Global node and cumulative string-byte budgets.
- Duplicate-map-key and encoded-key-order validation.
- Public RFC, malformed-input, resource-bound, property, coverage, AtomVM, and benchmark runners.

### Improved

- Options are normalized once into fixed tuple/record state instead of repeatedly scanning recursive proplists.
- Malformed and truncated payloads return structured errors across full and partial paths.
- Common host and attached-device encode/decode workloads improved against the historical `v0.1.0` baseline in the audited measurements.
- Public term representations remain compatible with the historical API.

### Packaging

- Added Rebar3/Hex metadata for public package `atomvm_cbor`.
- Added ExDoc/HexDocs generation with source links targeting tag `0.2.0`.
- Historical Git `v0.1.0` was never published to Hex.

## v0.1.1 (2026-06-27)

- Added a dependency-free benchmark runner and initial public benchmark policy.
- Added public release-check helpers and documentation.

## v0.1.0 (2026-06-27)

Initial public Git source baseline. This version was not published to Hex.pm.
