#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

benchmark_otp="$(erl -noshell -eval \
    'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
if [ "${benchmark_otp}" != "29" ]; then
    echo "release benchmark requires OTP 29, found ${benchmark_otp}" >&2
    exit 1
fi
printf 'PERFORMANCE_RUNTIME otp=%s\n' "${benchmark_otp}"

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

# Use identical, minimal scheduler topology for every fresh baseline/current
# VM. This controls scheduler migration without changing the regression limit.
erl_benchmark=(erl +S 1:1 +SDcpu 1:1 +SDio 1)

baseline_dir="$(mktemp -d)"
fixed_dir="$(mktemp -d)"
trap 'rm -rf "${baseline_dir}" "${fixed_dir}"' EXIT

mkdir -p "${baseline_dir}/src" "${baseline_dir}/ebin" "${fixed_dir}/ebin" bench/results
git archive "${baseline_tag}" src | tar -x -C "${baseline_dir}"
printf 'PERFORMANCE_BASELINE_SOURCES\n'
find "${baseline_dir}/src" -maxdepth 1 -type f \
    \( -name '*.erl' -o -name '*.hrl' \) -print0 | sort -z | xargs -0 sha256sum

baseline_sources=("${baseline_dir}"/src/*.erl)
erlc -Wall -I "${baseline_dir}/src" -o "${baseline_dir}/ebin" \
    "${baseline_sources[@]}"
read -r baseline_has_partial baseline_has_deterministic baseline_has_benefit_apis < <(
    "${erl_benchmark[@]}" -noshell -pa "${baseline_dir}/ebin" -eval '
        Exports = avm_cbor:module_info(exports),
        HasPartial = lists:member({partial_decode, 1}, Exports),
        HasDeterministic = case catch avm_cbor:decode(
            <<16#9F, 1, 16#FF>>, [{deterministic, true}]) of
            {error, non_deterministic_indefinite} -> true;
            _ -> false
        end,
        HasBenefitApis = lists:all(
            fun(Export) -> lists:member(Export, Exports) end,
            [{encode_with_size, 1}, {encode_sequence, 1}, {sequence_fold, 3},
             {validate_all, 1}, {partial_map_fold, 3}, {partial_array_fold, 3},
             {partial_select, 2}, {partial_map_find, 2}, {partial_array_nth, 2}]
        ),
        io:format("~p ~p ~p~n", [HasPartial, HasDeterministic, HasBenefitApis]),
        halt().'
)
printf 'PERFORMANCE_BASELINE_CAPABILITIES partial=%s deterministic=%s benefit_apis=%s\n' \
    "${baseline_has_partial}" "${baseline_has_deterministic}" \
    "${baseline_has_benefit_apis}"

baseline_defines=()
if [ "${baseline_has_partial}" = true ]; then
    baseline_defines+=(-DHAS_PARTIAL)
fi
if [ "${baseline_has_deterministic}" = true ]; then
    baseline_defines+=(-DHAS_DETERMINISTIC)
fi
if [ "${baseline_has_benefit_apis}" = true ]; then
    baseline_defines+=(-DHAS_BENEFIT_APIS)
fi
erlc -Wall -I "${baseline_dir}/src" "${baseline_defines[@]}" \
    -o "${baseline_dir}/ebin" bench/remediation_benchmark.erl
erlc -Wall -I src -DHAS_PARTIAL -DHAS_DETERMINISTIC -DHAS_BENEFIT_APIS \
    -o "${fixed_dir}/ebin" \
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
        "${erl_benchmark[@]}" -noshell -pa "${baseline_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"baseline-${baseline_version}\", \"${baseline_commit}\", \"${baseline_path}\"), halt()."
        "${erl_benchmark[@]}" -noshell -pa "${fixed_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"current-${current_version}\", \"${fixed_commit}\", \"${fixed_path}\"), halt()."
    else
        "${erl_benchmark[@]}" -noshell -pa "${fixed_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"current-${current_version}\", \"${fixed_commit}\", \"${fixed_path}\"), halt()."
        "${erl_benchmark[@]}" -noshell -pa "${baseline_dir}/ebin" -eval \
            "ok = remediation_benchmark:run(\"baseline-${baseline_version}\", \"${baseline_commit}\", \"${baseline_path}\"), halt()."
    fi
done

baseline_path_list="$(IFS=,; echo "${baseline_paths[*]}")"
fixed_path_list="$(IFS=,; echo "${fixed_paths[*]}")"
"${erl_benchmark[@]}" -noshell -pa "${baseline_dir}/ebin" -eval \
    "ok = remediation_benchmark:aggregate([${baseline_path_list}], \"bench/results/${result_id}-baseline.csv\"), halt()."
"${erl_benchmark[@]}" -noshell -pa "${fixed_dir}/ebin" -eval \
    "ok = remediation_benchmark:aggregate([${fixed_path_list}], \"bench/results/${result_id}-current.csv\"), halt()."
"${erl_benchmark[@]}" -noshell -pa "${fixed_dir}/ebin" -eval \
    'ok = remediation_benchmark:compare(
        "bench/results/'"${result_id}"'-baseline.csv",
        "bench/results/'"${result_id}"'-current.csv",
        "bench/results/'"${result_id}"'-comparison.json",
        "docs/benchmarks/'"${result_id}"'-local.md"
    ), halt().'

printf 'PERFORMANCE_ARTIFACT_ID %s\n' "${result_id}"
printf 'Local benchmark artifacts: bench/results/%s-* and docs/benchmarks/%s-local.md\n' \
    "${result_id}" "${result_id}"
