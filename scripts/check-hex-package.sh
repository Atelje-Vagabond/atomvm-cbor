#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 UNPACKED_PACKAGE_DIR" >&2
    exit 2
fi

package_dir="$1"
test -d "${package_dir}"
release_version="$(python3 scripts/read-release-version.py)"
release_manifest="docs/benchmarks/data/${release_version}.json"

release_manifests=()
for candidate in docs/benchmarks/data/*.json; do
    if [[ "$(basename "${candidate}")" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+\.json$ ]]; then
        release_manifests+=("${candidate}")
    fi
done
if [ "${#release_manifests[@]}" -eq 0 ]; then
    echo 'FAIL: no canonical versioned release-evidence manifests found.' >&2
    exit 1
fi

benchmark_reports=()
for candidate in docs/benchmarks/*.md; do
    if [[ "$(basename "${candidate}")" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+\.md$ ]]; then
        benchmark_reports+=("${candidate}")
    fi
done
chart_assets=(docs/benchmarks/charts/"${release_version}"/*.svg)
if [ "${#chart_assets[@]}" -ne 3 ] || [ ! -f "${chart_assets[0]}" ]; then
    echo 'FAIL: expected exactly three current-release SVG benchmark charts.' >&2
    exit 1
fi
if [ "${#benchmark_reports[@]}" -eq 0 ]; then
    echo 'FAIL: no canonical versioned benchmark reports found.' >&2
    exit 1
fi

for required in \
    src/avm_cbor.erl src/avm_cbor_cont.erl src/avm_cbor_partial.erl src/avm_cbor_opts.hrl \
    src/avm_cbor.app.src rebar.config VERSION README.md CHANGELOG.md \
    LICENSE docs/api.md docs/decoder-policy.md docs/atomvm-memory-internals.md \
    docs/benchmarks.md "${release_manifest}" "${benchmark_reports[@]}" \
    "${chart_assets[@]}"; do
    test -s "${package_dir}/${required}"
done

actual="$(mktemp)"
expected="$(mktemp)"
trap 'rm -f "${actual}" "${expected}"' EXIT
find "${package_dir}" -type f -printf '%P\n' | sort > "${actual}"
cat > "${expected}" <<'FILES'
CHANGELOG.md
LICENSE
README.md
VERSION
docs/api.md
docs/atomvm-memory-internals.md
docs/benchmarks.md
docs/decoder-policy.md
hex_metadata.config
rebar.config
src/avm_cbor.app.src
src/avm_cbor.erl
src/avm_cbor_cont.erl
src/avm_cbor_opts.hrl
src/avm_cbor_partial.erl
FILES
for benchmark_report in "${benchmark_reports[@]}"; do
    printf '%s\n' "${benchmark_report}" >> "${expected}"
done
printf '%s\n' "${release_manifests[@]}" >> "${expected}"
printf '%s\n' "${chart_assets[@]}" >> "${expected}"
sort -o "${expected}" "${expected}"
if ! diff -u "${expected}" "${actual}"; then
    echo 'FAIL: Hex package file list differs from the allowlist.' >&2
    exit 1
fi

for forbidden in \
    .git .github .agent _build ebin test bench scripts hardware-results; do
    if find "${package_dir}" -path "*/${forbidden}" -print -quit | grep -q .; then
        echo "FAIL: forbidden package path found: ${forbidden}" >&2
        exit 1
    fi
done

if grep -RInE \
    'atomvm-cbor-internal|runner[_ -]?group|/dev/tty|USB serial|\.agent|HANDOFF|ACTIVE_TASK|HEX_API_KEY' \
    "${package_dir}"; then
    echo 'FAIL: non-public or secret-related content found in package.' >&2
    exit 1
fi

echo 'Hex package content check passed.'
