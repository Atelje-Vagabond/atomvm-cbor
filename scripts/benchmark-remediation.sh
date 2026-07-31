#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

git fetch --tags

baseline_ref="v0.1.1"
baseline_commit="$(git rev-parse "${baseline_ref}^{commit}")"
fixed_commit="$(git rev-parse HEAD)"

if ! git diff --quiet -- src/avm_cbor.erl src/avm_cbor_partial.erl; then
    echo "source files differ from fixed commit ${fixed_commit}; commit them before benchmarking" >&2
    exit 1
fi

baseline_dir="$(mktemp -d)"
fixed_dir="$(mktemp -d)"
trap 'rm -rf "${baseline_dir}" "${fixed_dir}"' EXIT

mkdir -p "${baseline_dir}/src" "${baseline_dir}/ebin" "${fixed_dir}/ebin" bench/results
git cat-file blob "${baseline_ref}:src/avm_cbor.erl" > "${baseline_dir}/src/avm_cbor.erl"
echo "549986e06f74701d9d1fe7e48dd584528ae4088fab5d2ca281783f4ce0e0cc78  ${baseline_dir}/src/avm_cbor.erl" | sha256sum --check

erlc -Wall -DBASELINE -o "${baseline_dir}/ebin" \
    "${baseline_dir}/src/avm_cbor.erl" bench/remediation_benchmark.erl
erlc -Wall -I src -o "${fixed_dir}/ebin" \
    src/avm_cbor.erl src/avm_cbor_partial.erl bench/remediation_benchmark.erl

erl -noshell -pa "${baseline_dir}/ebin" -eval \
    "ok = remediation_benchmark:run(\"v0.1.1-source-baseline\", \"${baseline_commit}\", \"bench/results/v0.1.1.csv\"), halt()."
erl -noshell -pa "${fixed_dir}/ebin" -eval \
    "ok = remediation_benchmark:run(\"fixed\", \"${fixed_commit}\", \"bench/results/0.2.0.csv\"), halt()."
erl -noshell -pa "${fixed_dir}/ebin" -eval \
    'ok = remediation_benchmark:compare(
        "bench/results/v0.1.1.csv",
        "bench/results/0.2.0.csv",
        "bench/results/0.2.0-comparison.json",
        "docs/benchmarks/0.2.0-local.md"
    ), halt().'

echo "Local benchmark artifacts written under ignored result paths."
