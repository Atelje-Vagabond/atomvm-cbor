#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

git fetch --tags

selection="$(python3 scripts/select-semver-baseline.py)"
baseline_tag="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])' <<< "${selection}")"
baseline_version="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' <<< "${selection}")"
baseline_commit="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"])' <<< "${selection}")"
current_version="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["current_version"])' <<< "${selection}")"
fixed_commit="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["current_commit"])' <<< "${selection}")"

test "${baseline_commit}" = "$(git rev-parse "${baseline_tag}^{commit}")"
test "${fixed_commit}" = "$(git rev-parse 'HEAD^{commit}')"
printf 'PERFORMANCE_BASELINE tag=%s version=%s commit=%s\n' \
    "${baseline_tag}" "${baseline_version}" "${baseline_commit}"
printf 'PERFORMANCE_CURRENT version=%s commit=%s\n' \
    "${current_version}" "${fixed_commit}"

if ! git diff --quiet -- src/avm_cbor.erl src/avm_cbor_cont.erl src/avm_cbor_partial.erl; then
    echo "source files differ from fixed commit ${fixed_commit}; commit them before benchmarking" >&2
    exit 1
fi

baseline_dir="$(mktemp -d)"
fixed_dir="$(mktemp -d)"
trap 'rm -rf "${baseline_dir}" "${fixed_dir}"' EXIT

mkdir -p "${baseline_dir}/src" "${baseline_dir}/ebin" "${fixed_dir}/ebin" bench/results
git cat-file blob "${baseline_tag}:src/avm_cbor.erl" > "${baseline_dir}/src/avm_cbor.erl"
printf 'PERFORMANCE_BASELINE_SOURCE '
sha256sum "${baseline_dir}/src/avm_cbor.erl"

erlc -Wall -DBASELINE -o "${baseline_dir}/ebin" \
    "${baseline_dir}/src/avm_cbor.erl" bench/remediation_benchmark.erl
erlc -Wall -I src -o "${fixed_dir}/ebin" \
    src/avm_cbor.erl src/avm_cbor_cont.erl src/avm_cbor_partial.erl \
    bench/remediation_benchmark.erl

runs="${BENCHMARK_RUNS:-5}"
case "${runs}" in
    ''|*[!0-9]*|0)
        echo "BENCHMARK_RUNS must be a positive integer" >&2
        exit 1
        ;;
esac

baseline_paths=()
fixed_paths=()
baseline_id="${baseline_version}-${baseline_commit:0:12}"
current_id="${current_version}-${fixed_commit:0:12}"
result_id="${baseline_id}--${current_id}"
for run in $(seq 1 "${runs}"); do
    baseline_path="${baseline_dir}/run-${run}.csv"
    fixed_path="${fixed_dir}/run-${run}.csv"
    baseline_paths+=("\"${baseline_path}\"")
    fixed_paths+=("\"${fixed_path}\"")

    if (( run % 2 == 1 )); then
        erl -noshell -pa "${baseline_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"baseline-${baseline_version}\", \"${baseline_commit}\", \"${baseline_path}\"), halt()."
        erl -noshell -pa "${fixed_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"current-${current_version}\", \"${fixed_commit}\", \"${fixed_path}\"), halt()."
    else
        erl -noshell -pa "${fixed_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"current-${current_version}\", \"${fixed_commit}\", \"${fixed_path}\"), halt()."
        erl -noshell -pa "${baseline_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"baseline-${baseline_version}\", \"${baseline_commit}\", \"${baseline_path}\"), halt()."
    fi
done

baseline_path_list="$(IFS=,; echo "${baseline_paths[*]}")"
fixed_path_list="$(IFS=,; echo "${fixed_paths[*]}")"
erl -noshell -pa "${baseline_dir}/ebin" -eval \
    "ok = remediation_benchmark:aggregate([${baseline_path_list}], \"bench/results/${result_id}-baseline.csv\"), halt()."
erl -noshell -pa "${fixed_dir}/ebin" -eval \
    "ok = remediation_benchmark:aggregate([${fixed_path_list}], \"bench/results/${result_id}-current.csv\"), halt()."
erl -noshell -pa "${fixed_dir}/ebin" -eval \
    'ok = remediation_benchmark:compare(
        "bench/results/'"${result_id}"'-baseline.csv",
        "bench/results/'"${result_id}"'-current.csv",
        "bench/results/'"${result_id}"'-comparison.json",
        "docs/benchmarks/'"${result_id}"'-local.md"
    ), halt().'

printf 'PERFORMANCE_ARTIFACT_ID %s\n' "${result_id}"
printf 'Local benchmark artifacts: bench/results/%s-* and docs/benchmarks/%s-local.md\n' \
    "${result_id}" "${result_id}"
