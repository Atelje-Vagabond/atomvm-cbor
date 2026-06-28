# Benchmarks

This directory contains reproducible host-side microbenchmarks for AtomVM CBOR.

## Overview

The benchmark suite measures decode and encode throughput for representative workloads using only Erlang/OTP standard tools. No external dependencies, NIFs, or ports are used.

## Important

These are OTP host-side microbenchmarks. They are intended as reproducible baseline measurements, not ESP32 runtime performance guarantees.

Results depend heavily on the host CPU, OTP version, and architecture. They should be used to detect regressions between releases and to establish a relative performance baseline, not to make absolute speed claims.

## How to run

```bash
scripts/bench.sh
```

Iterations can be controlled via the `BENCH_ITERATIONS` environment variable:

```bash
BENCH_ITERATIONS=50000 scripts/bench.sh
```

The script compiles the module and benchmark runner, then outputs a table:

```
Workload                | Iterations | Total ms |  Ops/sec
-------------------------|------------|----------|---------
decode_unsigned_small    |     100000 |    158.3 |   631712
```

## Release policy

Every public release must include:

- A completed benchmark report under `docs/benchmarks/<version>.md`.
- A `scripts/release-check.sh` run that validates smoke tests, benchmarks, and documentation.
- An ESP-IDF validation summary.
- A benchmark summary in the release notes.

A release is not publishable if any of the above are missing or failing.

## Reports

- [v0.1.1](benchmarks/v0.1.1.md)
