#!/usr/bin/env bash
set -euo pipefail

profile="${1:-}"
source_mode="${2:---files}"

case "${profile}" in
    public|internal) ;;
    *)
        echo "usage: $0 public|internal [--files|--diff BASE [HEAD]|--all]" >&2
        exit 2
        ;;
esac

performance=false
otp=false
coverage=false
atomvm=false
esp_idf=false
package=false
software=false
hardware=false

mark_public_runtime() {
    performance=true
    otp=true
    coverage=true
    atomvm=true
    esp_idf=true
    package=true
}

mark_internal_runtime() {
    software=true
    esp_idf=true
    hardware=true
}

classify_public() {
    local file_name="$1"
    case "${file_name}" in
        src/avm_cbor.app.src)
            otp=true
            package=true
            ;;
        src/*|include/*)
            mark_public_runtime
            ;;
        test/avm_cbor_atomvm.erl)
            otp=true
            coverage=true
            atomvm=true
            esp_idf=true
            ;;
        test/*)
            otp=true
            coverage=true
            ;;
        bench/*|scripts/benchmark-remediation.sh|scripts/test-benchmark-regression-gate.sh|scripts/select-semver-baseline.py|scripts/test-semver-baseline-selector.sh)
            performance=true
            ;;
        scripts/test-public.sh)
            otp=true
            coverage=true
            ;;
        scripts/coverage-gate.sh|scripts/check-coverage.escript|scripts/branch-coverage.escript)
            coverage=true
            ;;
        scripts/test-atomvm.sh)
            atomvm=true
            ;;
        scripts/test-esp-idf.sh|scripts/run-esp-idf-release-validation.sh|scripts/test-release-check-esp-idf.sh)
            esp_idf=true
            ;;
        VERSION)
            performance=true
            package=true
            ;;
        rebar.config|rebar.lock)
            mark_public_runtime
            ;;
        .github/workflows/publish-hex.yml|.github/releases/*|docs/*|README.md|CHANGELOG.md|LICENSE|hex_metadata.config|scripts/gen-api-docs.py|scripts/release-evidence.py|scripts/check-hex-package.sh|scripts/release-check.sh|scripts/read-release-version.py|scripts/verify-hex-release.py)
            package=true
            ;;
        .github/workflows/release-gate.yml)
            mark_public_runtime
            ;;
        scripts/classify-ci-changes.sh|scripts/test-ci-change-routing.sh|scripts/check-release-metadata.sh|scripts/check-public-hygiene.sh|scripts/source-integrity.sha256)
            # The always-on hygiene job validates routing and workflow policy.
            ;;
        *.erl|*.hrl)
            mark_public_runtime
            ;;
        *.sh|*.py|*.escript)
            performance=true
            otp=true
            coverage=true
            atomvm=true
            esp_idf=true
            package=true
            ;;
        *)
            # Unknown public assets can affect the Hex allowlist or docs bundle.
            package=true
            ;;
    esac
}

classify_internal() {
    local file_name="$1"
    case "${file_name}" in
        .agent/*|docs/*|README.md|CHANGELOG.md|LICENSE|VERSION)
            ;;
        .github/workflows/pr-validation.yml|scripts/classify-ci-changes.sh|scripts/test-ci-change-routing.sh|scripts/check-workflows.sh|scripts/check-agent-state.sh)
            # The always-on routing job validates these files without hardware.
            ;;
        src/*|include/*|rebar.config|rebar.lock)
            mark_internal_runtime
            ;;
        test/avm_cbor_hardware*.erl|test/avm_cbor_atomvm.erl|bench/cbor_release_benchmark.erl)
            software=true
            esp_idf=true
            hardware=true
            ;;
        test/*|bench/*)
            software=true
            ;;
        hardware/*|scripts/build-hardware-pack.sh|scripts/test-esp32-hardware.sh|scripts/test-rp2040-hardware.sh|scripts/find-esp32-port.sh|scripts/find-rp2040-bootsel.sh|scripts/capture-serial-markers.py|scripts/check-atomvm-esp32-base.py|scripts/test-hardware-discovery.sh)
            esp_idf=true
            hardware=true
            ;;
        scripts/test-esp-idf.sh|scripts/run-esp-idf-release-validation.sh|scripts/test-release-check-esp-idf.sh)
            esp_idf=true
            ;;
        *.erl|*.hrl)
            mark_internal_runtime
            ;;
        *.sh|*.py|*.escript)
            software=true
            ;;
        *)
            ;;
    esac
}

classify_file() {
    local file_name="$1"
    [ -n "${file_name}" ] || return 0
    case "${profile}" in
        public) classify_public "${file_name}" ;;
        internal) classify_internal "${file_name}" ;;
    esac
}

case "${source_mode}" in
    --all)
        case "${profile}" in
            public) mark_public_runtime ;;
            internal) mark_internal_runtime ;;
        esac
        ;;
    --files)
        while IFS= read -r changed_file; do
            classify_file "${changed_file}"
        done
        ;;
    --diff)
        base_commit="${3:-}"
        head_commit="${4:-HEAD}"
        if [ -z "${base_commit}" ] ||
           ! git cat-file -e "${base_commit}^{commit}" 2>/dev/null ||
           ! git cat-file -e "${head_commit}^{commit}" 2>/dev/null; then
            echo "invalid CI diff boundary" >&2
            exit 2
        fi
        while IFS= read -r changed_file; do
            classify_file "${changed_file}"
        done < <(git diff --name-only --diff-filter=ACDMRT "${base_commit}..${head_commit}")
        ;;
    *)
        echo "unsupported change source: ${source_mode}" >&2
        exit 2
        ;;
esac

printf 'performance=%s\n' "${performance}"
printf 'otp=%s\n' "${otp}"
printf 'coverage=%s\n' "${coverage}"
printf 'atomvm=%s\n' "${atomvm}"
printf 'esp_idf=%s\n' "${esp_idf}"
printf 'package=%s\n' "${package}"
printf 'software=%s\n' "${software}"
printf 'hardware=%s\n' "${hardware}"
