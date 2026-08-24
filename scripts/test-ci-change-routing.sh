#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
classifier="${repo_root}/scripts/classify-ci-changes.sh"

route() {
    local profile="$1"
    shift
    printf '%s\n' "$@" | bash "${classifier}" "${profile}" --files
}

assert_route() {
    local output="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(printf '%s\n' "${output}" | awk -F= -v wanted="${key}" '$1 == wanted { print $2 }')"
    if [ "${actual}" != "${expected}" ]; then
        echo "routing assertion failed: ${key} expected ${expected}, got ${actual}" >&2
        exit 1
    fi
}

current_version="$(python3 "${repo_root}/scripts/read-release-version.py")"
public_docs="$(route public "docs/benchmarks/${current_version}.md" ".github/releases/${current_version}.md")"
assert_route "${public_docs}" package true
assert_route "${public_docs}" performance false
assert_route "${public_docs}" otp false
assert_route "${public_docs}" esp_idf false

public_release_evidence="$(route public scripts/release-evidence.py)"
assert_route "${public_release_evidence}" package true
for key in performance otp coverage atomvm esp_idf; do
    assert_route "${public_release_evidence}" "${key}" false
done

public_version_only="$(route public VERSION)"
assert_route "${public_version_only}" package true
for key in performance otp coverage atomvm esp_idf; do
    assert_route "${public_version_only}" "${key}" false
done

public_runtime="$(route public src/avm_cbor.erl)"
for key in performance otp coverage atomvm esp_idf package; do
    assert_route "${public_runtime}" "${key}" true
done

public_workflow="$(route public .github/workflows/release-gate.yml)"
for key in performance otp coverage atomvm esp_idf package; do
    assert_route "${public_workflow}" "${key}" true
done

public_coverage="$(route public scripts/branch-coverage.escript scripts/check-coverage.escript)"
assert_route "${public_coverage}" coverage true
for key in performance otp atomvm esp_idf package; do
    assert_route "${public_coverage}" "${key}" false
done

public_unknown_script="$(route public scripts/new-release-operation.sh)"
for key in performance otp coverage atomvm esp_idf package; do
    assert_route "${public_unknown_script}" "${key}" true
done

internal_docs="$(route internal .agent/HANDOFF_CURRENT.md docs/final-continuation-report.md)"
assert_route "${internal_docs}" software false
assert_route "${internal_docs}" esp_idf false
assert_route "${internal_docs}" hardware false

internal_runtime="$(route internal src/avm_cbor.erl)"
assert_route "${internal_runtime}" software true
assert_route "${internal_runtime}" esp_idf true
assert_route "${internal_runtime}" hardware true

internal_host_test="$(route internal test/avm_cbor_continuation_tests.erl)"
assert_route "${internal_host_test}" software true
assert_route "${internal_host_test}" esp_idf false
assert_route "${internal_host_test}" hardware false

internal_hardware="$(route internal scripts/test-esp32-hardware.sh)"
assert_route "${internal_hardware}" software false
assert_route "${internal_hardware}" esp_idf true
assert_route "${internal_hardware}" hardware true

internal_unknown_erlang="$(route internal src/new_runtime_module.erl)"
assert_route "${internal_unknown_erlang}" software true
assert_route "${internal_unknown_erlang}" esp_idf true
assert_route "${internal_unknown_erlang}" hardware true

all_internal="$(bash "${classifier}" internal --all)"
assert_route "${all_internal}" software true
assert_route "${all_internal}" esp_idf true
assert_route "${all_internal}" hardware true

echo 'CI_CHANGE_ROUTING_OK'
