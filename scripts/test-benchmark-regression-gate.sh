#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

ebin="${fixture_root}/ebin"
mkdir -p "${ebin}"
erlc -Wall -o "${ebin}" "${repo_root}/bench/remediation_benchmark.erl"

write_result() {
    path="$1"
    mode="$2"
    available="$3"
    median="$4"
    p95="$5"
    {
        printf 'kind,name,available,samples,iterations,median_ns,p95_ns,mad_ns,min_ns,max_ns,gc_count,gc_reclaimed_words,heap_delta_words\n'
        printf 'META,mode,%s\n' "${mode}"
        printf 'META,identity,fixture-%s\n' "${mode}"
        printf 'META,otp_release,27\n'
        printf 'META,system_architecture,test\n'
        printf 'META,schedulers,1\n'
        printf 'META,samples,31\n'
        printf 'META,warmup_iterations,1000\n'
        printf 'BENCH,nested_decode,%s,31,3000,%s,%s,1,1,1,0,0,0\n' \
            "${available}" "${median}" "${p95}"
    } > "${path}"
}

run_compare() {
    baseline="$1"
    fixed="$2"
    suffix="$3"
    BENCHMARK_NOISE_TOLERANCE_PERCENT=5 erl -noshell -pa "${ebin}" -eval \
        "ok = remediation_benchmark:compare(\"${baseline}\", \"${fixed}\", \"${fixture_root}/${suffix}.json\", \"${fixture_root}/${suffix}.md\"), halt()."
}

baseline="${fixture_root}/baseline.csv"
fixed="${fixture_root}/fixed.csv"
write_result "${baseline}" baseline true 100 100

write_result "${fixed}" fixed true 105 105
run_compare "${baseline}" "${fixed}" tolerance-boundary
grep -q '"regression_gate": "pass"' "${fixture_root}/tolerance-boundary.json"

write_result "${fixed}" fixed true 106 100
if run_compare "${baseline}" "${fixed}" median-regression >/dev/null 2>&1; then
    echo "median regression beyond tolerance must fail" >&2
    exit 1
fi
grep -q '"regression_gate": "fail"' "${fixture_root}/median-regression.json"

write_result "${fixed}" fixed true 100 106
if run_compare "${baseline}" "${fixed}" p95-regression >/dev/null 2>&1; then
    echo "p95 regression beyond tolerance must fail" >&2
    exit 1
fi
grep -q '"regression_gate": "fail"' "${fixture_root}/p95-regression.json"

write_result "${baseline}" baseline false 0 0
write_result "${fixed}" fixed true 500 500
run_compare "${baseline}" "${fixed}" unavailable-baseline

runtime_probe="${fixture_root}/runtime-probe"
mkdir -p "${runtime_probe}/bin" "${runtime_probe}/scripts"
cp "${repo_root}/scripts/benchmark-remediation.sh" "${runtime_probe}/scripts/"
printf '#!/usr/bin/env bash\nprintf "27"\n' > "${runtime_probe}/bin/erl"
chmod +x "${runtime_probe}/bin/erl"
if PATH="${runtime_probe}/bin:${PATH}" \
    bash "${runtime_probe}/scripts/benchmark-remediation.sh" \
    >"${runtime_probe}/wrong-otp.log" 2>&1; then
    echo "release benchmark must reject a non-OTP-29 runtime" >&2
    exit 1
fi
grep -F 'release benchmark requires OTP 29, found 27' \
    "${runtime_probe}/wrong-otp.log"

echo "Benchmark regression gate tests passed."
