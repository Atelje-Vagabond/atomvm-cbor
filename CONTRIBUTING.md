# Contributing

Contributions are welcome when they keep the public repository focused, reproducible, and safe for constrained AtomVM targets.

## Pull requests

- Keep changes focused and explain compatibility impact.
- Add tests for behavior changes and documentation for public API changes.
- Add or update representative benchmarks for performance-sensitive changes.

### Release benchmark comparison rule

Every release after the first must publish a previous-release comparison for
each physical board used as release evidence. The report must identify the
board and configuration, both release versions and source identities, AtomVM
and SDK versions, harness, payload, iterations, units, statistic, prior and
current values, change, gate result, and retained-evidence provenance.

Reuse retained comparable measurements when the measured function and harness
are unchanged; do not rerun device benchmarks merely to regenerate a report.
Never relabel historical measurements as a different source revision. If
comparable evidence is missing, stop the release and obtain explicit human
authorization before running hardware benchmarks again. This comparison is a
release-blocking requirement before merge, tag, Hex/HexDocs publication, or a
GitHub release. Existing tags and releases must remain immutable.
- Include a `Signed-off-by:` trailer (`git commit -s`).
- Do not include credentials, private infrastructure identifiers, raw private
  evidence, or assistant/runtime state.

All required checks must pass on the exact pull-request head. General public
validation runs on the isolated CI runner pool. The performance gate may use
the isolated `public-performance` host only for trusted same-repository heads;
fork code cannot execute there or satisfy the exact-head release gate directly.
Public validation never requires physical-device access.

## Local validation

Requirements for the core suite are Erlang/OTP 25 or newer, Rebar3, Python 3, and a POSIX-compatible shell.

```bash
scripts/release-check.sh 0.2.0
```

Generate or check the API reference:

```bash
python3 scripts/gen-api-docs.py
python3 scripts/gen-api-docs.py --check
```

Run the reproducible host benchmark:

```bash
scripts/bench.sh
```

Run both supported ESP-IDF integration builds when Docker is available:

```bash
scripts/test-esp-idf.sh v5.4.3
scripts/test-esp-idf.sh v5.5.2
```

The ESP-IDF helper uses digest-pinned public images and the exact AtomVM 0.6.6 source commit. It validates build integration; it is not a physical-device test.

## Release identity

- OTP application: `avm_cbor`
- Hex package: `atomvm_cbor`
- Current version and tag: `0.2.0`
- Public `v0.1.1`: source/benchmark baseline only; never publish it to Hex

Release tags use the exact `VERSION` value and never add a leading `v`.

## Benchmarks

Compare versions with the same host, runtime, payload, harness, warmup, and sample count. Include units and methodology. Report an unavailable historical API as `N/A`; do not infer a baseline. Benchmark results are measured context rather than universal latency, security, or memory-safety guarantees.
