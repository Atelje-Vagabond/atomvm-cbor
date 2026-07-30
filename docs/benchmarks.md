# Benchmarks

The public benchmark runners provide reproducible host-side and AtomVM-compatible workloads without publishing private audit artifacts or device logs.

## Run locally

```bash
scripts/bench.sh
```

The remediation benchmark compares representative decode, encode, sequence, malformed-input, partial, and deterministic-map workloads. Lower latency is better. Results vary by CPU, OTP version, architecture, scheduler state, and power policy, so compare versions on the same system and report methodology with every result.

Release notes may contain independently validated host and hardware summaries. These are historical measured context, not universal latency guarantees and not claims that the implementation is leak-free or secure against every possible workload.

The public release gate validates the benchmark harness and the historical v0.1.0 source comparison where supported. The public `v0.1.1` tag contains byte-identical runtime source and is checksum-verified by the runner, so it is the reproducible public source reference. APIs absent from v0.1.0 are reported as `N/A` rather than inferred.
