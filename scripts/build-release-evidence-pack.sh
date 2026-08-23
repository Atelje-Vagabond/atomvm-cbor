#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
output="${2:-}"
packbeam="${PACKBEAM:-packbeam}"

if [[ -z "${mode}" || -z "${output}" ]]; then
    echo "usage: $0 candidate-api|functional-soak OUTPUT.avm" >&2
    exit 2
fi

if ! command -v "${packbeam}" >/dev/null 2>&1 && [[ ! -x "${packbeam}" ]]; then
    echo "PackBEAM executable not found: ${packbeam}" >&2
    exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "${build_dir}"' EXIT

common_sources=(
    src/avm_cbor.erl
    src/avm_cbor_cont.erl
    src/avm_cbor_partial.erl
)

case "${mode}" in
    candidate-api)
        start_module="candidate_api_benchmark_entry"
        extra_sources=(
            bench/cbor_candidate_api_benchmark.erl
            bench/candidate_api_benchmark_entry.erl
        )
        ;;
    functional-soak)
        start_module="functional_soak_entry"
        extra_sources=(
            test/avm_cbor_atomvm.erl
            test/avm_cbor_hardware_soak.erl
            bench/functional_soak_entry.erl
        )
        ;;
    *)
        echo "unknown release-evidence mode: ${mode}" >&2
        exit 2
        ;;
esac

erlc -o "${build_dir}" "${common_sources[@]}" "${extra_sources[@]}"

beam_files=("${build_dir}"/*.beam)
"${packbeam}" create --start "${start_module}" "${output}" "${beam_files[@]}"
test -s "${output}"

printf 'Release evidence pack: %s (%s bytes)\n' "${output}" "$(wc -c < "${output}")"
