#!/usr/bin/env bash
set -euo pipefail

idf_version="${1:-}"
case "${idf_version}" in
    v5.4.3)
        image="espressif/idf@sha256:9352fff95ecee99e953b8fdd4949cda6baeeae76fe23c330dca1133ef92679f9"
        ;;
    v5.5.2)
        image="espressif/idf@sha256:05cbfc42ed2e987b8026722c15bf1d8523d3e4fd1b4ac04d2e4056f5e0918b99"
        ;;
    *)
        echo "usage: scripts/test-esp-idf.sh v5.4.3|v5.5.2" >&2
        exit 2
        ;;
esac

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
atomvm_commit="ff993a80963298b532c1e573f883951ecaac9fef"

docker run --rm \
    -e IDF_VERSION="${idf_version}" \
    -e ATOMVM_COMMIT="${atomvm_commit}" \
    -v "${repo_dir}:/project:ro" \
    "${image}" bash -c '
        set -euo pipefail
        git clone --filter=blob:none --no-checkout https://github.com/atomvm/AtomVM.git /atomvm
        git -C /atomvm checkout --detach "${ATOMVM_COMMIT}"
        test "$(git -C /atomvm rev-parse HEAD)" = "${ATOMVM_COMMIT}"
        apt-get update -qq
        apt-get install -y -qq erlang-base
        erlc -o /tmp /project/src/avm_cbor.erl /project/src/avm_cbor_partial.erl
        . "${IDF_PATH}/export.sh"
        cd /atomvm/src/platforms/esp32
        idf.py reconfigure
        idf.py build
        size="$(stat -c %s build/atomvm-esp32.bin)"
        test "${size}" -gt 0
        printf "ESP_IDF_VALIDATION_OK version=%s firmware_bytes=%s\n" "${IDF_VERSION}" "${size}"
    '
