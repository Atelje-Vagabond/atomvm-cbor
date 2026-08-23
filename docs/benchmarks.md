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

CI always runs public hygiene and changed-path policy first. A newly opened PR
is classified against its base; later synchronize events use the previous exact
PR head, so a documentation-only follow-up does not replay an unchanged runtime
suite. Workflow-definition changes are the exception: they
select the complete chain so a changed gate proves its own scheduling and
conclusions. Deleted paths are classified, unknown executable paths fail closed
into the broad validation class, and a tag, manual run, or missing comparison
history selects the complete chain.

When runtime or benchmark paths select performance, that gate runs after
hygiene in parallel with the OTP 25, 27, and 29 compatibility matrix. OTP
validation is therefore reported even when the OTP 29 performance comparison
fails. Only after the unchanged +5% regression limit passes do the other
selected coverage, AtomVM, ESP-IDF, and package jobs fan out across the two
self-hosted runners. Documentation/release-note changes select the package job
without reserving unrelated compiler or firmware capacity. The final job checks
that every selected job passed and every unselected job was actually skipped;
an empty, ambiguous, or inconsistent routing result fails closed.

Trusted same-repository release heads run the performance gate on the canonical
isolated `public-performance` host with the digest-pinned OTP 29 container
already present on that runner; the workflow never pulls a mutable image. Fork
code cannot execute on that runner and therefore cannot satisfy the exact-head
release gate directly.

Each baseline/current measurement starts a fresh Erlang VM with the same single
normal scheduler plus one dirty CPU and one dirty I/O scheduler. Five runs
alternate baseline-first and current-first order, then aggregate the run-level
statistics by median. This removes scheduler migration as a dominant source of
sub-microsecond p95 noise without relaxing the +5% limit or hiding an individual
failure. Baseline capabilities are probed from the selected tag, so APIs absent
from an old baseline are `N/A`; future baselines are not forced through a
release-specific compile flag.

Publication has a separate fail-closed lineage check. The release tag must
match `VERSION`, resolve to the checked-out commit, be reachable from
`origin/main`, and have a successful full tag-push release-gate run for the same
tag name and commit SHA. The protected `hex-production` environment is reached
only after those checks and the complete package/coverage/docs preflight pass.
This prevents an unmerged but previously green PR commit, a moved tag, or an
unrelated successful check from becoming a publishable release identity.

See the [0.2.0 validation report](benchmarks/0.2.0.md) for the matched host,
ESP32-S3, and RP2040 evidence.
