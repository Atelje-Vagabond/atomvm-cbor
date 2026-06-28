# Contributing

Thanks for your interest in AtomVM CBOR.

This project aims to keep the public repository small, readable, and reproducible. Contributions are welcome when they preserve that goal.

## Before opening a pull request

Please keep changes focused and easy to review.

Good pull requests usually include:

- a clear explanation of the change
- tests or benchmark updates when behavior changes
- documentation updates when user-facing behavior changes
- a `Signed-off-by:` trailer in every commit

Use:

```bash
git commit -s
```

The public CI checks for a generic DCO-style sign-off, such as:

```text
Signed-off-by: Your Name <you@example.com>
```

It does not require a maintainer-specific identity.

## Code owner review

All pull requests require review from the project code owner before merge.

The code owner is defined in `.github/CODEOWNERS`.

## Required tools

For normal development and smoke testing, you need:

- Erlang/OTP 25 or newer
- a POSIX-like shell environment
- `make`, `sh`, and common command-line tools

For AtomVM validation, you need network access so the workflow or local command can download the official AtomVM release binary and library used by the test.

For ESP-IDF validation, container support is required because the validation helper may run ESP-IDF builds in a containerized environment.

Common working setups include:

- Docker Desktop on macOS, Linux, or Windows
- OrbStack on macOS
- Colima with Docker CLI support on macOS
- Podman with Docker-style CLI support on Linux
- native Linux Docker Engine

The exact commands are documented in `scripts/release-check.sh` and `scripts/test-esp-idf.sh`.

If your system does not have a suitable container runtime, run the normal OTP and AtomVM checks first and mention that ESP-IDF validation was not run locally.

## Optional local pre-push hook

You can install the optional local hook with:

```bash
sh scripts/install-git-hooks.sh
```

For normal feature branches, the hook runs the standard release check before push:

```bash
scripts/release-check.sh v0.1.1
```

ESP-IDF validation is intentionally not run on every normal branch push. It is reserved for release-focused pushes:

- current branch is `release/*`
- pushed ref is a `v*` tag
- remote ref is a `release/*` branch
- `AVM_CBOR_WITH_ESP_IDF=1` is set

In those cases, the hook runs:

```bash
scripts/release-check.sh v0.1.1 --with-esp-idf
```

Local hooks are a developer convenience. GitHub CI remains the source of truth for pull request and merge readiness.

## Local checks

Run smoke tests:

```bash
erlc -o /tmp src/avm_cbor.erl
erlc -o /tmp test/avm_cbor_smoke.erl
erl -noshell -pa /tmp -eval 'avm_cbor_smoke:run().'
```

Run benchmarks:

```bash
scripts/bench.sh
```

Generate API documentation:

```bash
python3 scripts/gen-api-docs.py
```

Check generated API documentation:

```bash
python3 scripts/gen-api-docs.py --check
```

Run release checks:

```bash
scripts/release-check.sh v0.1.1
```

Run release checks with ESP-IDF validation when a suitable container runtime is available:

```bash
scripts/release-check.sh v0.1.1 --with-esp-idf
```

## API documentation

The public API reference is generated into `docs/api.md` from the exported functions and specs in `src/avm_cbor.erl`.

When a public function is added, removed, or changed, update the generator descriptions if needed and regenerate the API reference.

## Benchmark notes

Benchmark results in this repository are OTP host-side microbenchmarks. They are useful for release-to-release regression tracking on comparable hosts.

They are not ESP32 or AtomVM runtime performance measurements. ESP32 runtime performance should be measured separately on-device.

When updating benchmark reports, include:

- host operating system
- CPU model
- RAM
- Erlang/OTP version
- commit or tag
- command used

## Public repository hygiene

This repository must stay public-safe.

Do not add project-private operational notes, machine-specific files, assistant-specific instruction files, or local environment material.

The CI rejects known non-public file names and markers.

## Pull request style

Please keep PRs small when possible.

Use clear titles, for example:

```text
fix: reject duplicate map keys in strict mode
docs: clarify benchmark interpretation
test: add CBOR tag roundtrip cases
```

If a PR changes behavior, explain compatibility impact clearly.

## Release expectations

A release should have:

- passing OTP smoke tests
- passing AtomVM validation
- updated docs when needed
- benchmark report when release performance tracking changes
- manual ESP-IDF build validation when release scope requires it

ESP-IDF validation confirms build compatibility for the tested ESP-IDF versions. Runtime performance and hardware behavior must be measured separately on physical devices.
