#!/usr/bin/env bash
set -euo pipefail

# ESP-IDF build validation for avm_cbor integration into AtomVM
#
# Clones AtomVM release-0.6, places avm_cbor as an ESP-IDF component,
# compiles avm_cbor.erl with erlc, then builds the ESP32 firmware with idf.py.
#
# Prerequisites:
#   - Docker (runs espressif/idf container)
#
# Usage:
#   scripts/test-esp-idf.sh [idf-version]
#
# Examples:
#   scripts/test-esp-idf.sh          # default v5.4.3
#   scripts/test-esp-idf.sh v5.5.2
#   scripts/test-esp-idf.sh v5.4.3

IDF_VERSION="${1:-v5.4.3}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== ESP-IDF build validation (${IDF_VERSION}) ==="

docker run --rm -e IDF_VERSION="${IDF_VERSION}" -v "${REPO_DIR}:/project" "espressif/idf:${IDF_VERSION}" bash -c '
  set -euo pipefail

  echo "=== Cloning AtomVM release-0.6 ==="
  git clone --depth 1 --branch release-0.6 https://github.com/atomvm/AtomVM.git /atomvm

  echo "=== Placing avm_cbor as ESP-IDF component ==="
  cp -r /project /atomvm/src/platforms/esp32/components/avm_cbor

  echo "=== Installing erlang-base ==="
  apt-get update -qq && apt-get install -y -qq erlang-base

  echo "=== Compiling avm_cbor.erl ==="
  erlc -o /tmp /atomvm/src/platforms/esp32/components/avm_cbor/src/avm_cbor.erl
  echo "erlc: avm_cbor.erl compiles successfully"

  IDF_VERSION_SHORT=$(echo "$IDF_VERSION" | sed "s/v//")

  if [ "$(printf '%s\n' "5.5" "$IDF_VERSION_SHORT" | sort -V | head -n1)" = "5.5" ]; then
    echo "=== Installing xtensa toolchain (required for v5.5+) ==="
    idf_tools.py install xtensa-esp-elf-gdb
    idf_tools.py install xtensa-esp32-elf
  fi

  echo "=== Building ESP32 firmware ==="
  . $IDF_PATH/export.sh
  cd /atomvm/src/platforms/esp32
  idf.py reconfigure
  idf.py build
  echo "=== ESP-IDF build (${IDF_VERSION}) PASSED ==="
'

echo "=== ESP-IDF validation (${IDF_VERSION}) completed ==="
