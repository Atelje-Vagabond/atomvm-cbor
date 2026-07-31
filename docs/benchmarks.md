# Benchmarks

The public benchmark runners provide reproducible host-side and AtomVM-compatible workloads without publishing private audit artifacts or device logs.

## Run locally

```bash
scripts/bench.sh
```

The remediation benchmark compares representative decode, encode, sequence, malformed-input, partial, and deterministic-map workloads. Lower latency is better. Results vary by CPU, OTP version, architecture, scheduler state, and power policy, so compare versions on the same system and report methodology with every result.

Release notes may contain independently validated host and hardware summaries. These are historical measured context, not universal latency guarantees and not claims that the implementation is leak-free or secure against every possible workload.

The public release gate reads the candidate version from `VERSION`, considers
only SemVer tags reachable from the candidate commit, normalizes the optional
historical `v` prefix, excludes the current version, and selects the greatest
lower SemVer as the baseline. Missing or equal-precedence duplicate baselines
fail closed. The log records the selected tag and peeled commit SHA, and result
files include both baseline and candidate version/SHA identities. This avoids a
stale hard-coded baseline while keeping the comparison reproducible and
auditable. APIs absent from the selected baseline are reported as `N/A` rather
than inferred.

CI deliberately runs public hygiene first and the performance gate by itself
second. Only after the unchanged +5% regression gate passes do the remaining
OTP, coverage, AtomVM, ESP-IDF, and package jobs fan out across the two
self-hosted runners. This prevents expensive downstream work from running for
an unaudited or regressing candidate.

See the [0.2.0 validation report](benchmarks/0.2.0.md) for the matched host,
ESP32-S3, and RP2040 evidence.
