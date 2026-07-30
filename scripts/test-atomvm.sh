#!/usr/bin/env bash
set -euo pipefail

# AtomVM validation script for avm_cbor
# Prerequisites:
#   - erlc installed
#   - atomvm binary installed (download from https://github.com/atomvm/AtomVM/releases)
#   - atomvmlib.avm (same release)
#   - (optional) packbeam for .avm packaging
#
# Usage:
#   ATOMVM=/path/to/atomvm ATOMVMLIB=/path/to/atomvmlib.avm scripts/test-atomvm.sh

ATOMVM="${ATOMVM:-atomvm}"
ATOMVMLIB="${ATOMVMLIB:-atomvmlib.avm}"
ERLC="${ERLC:-erlc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$REPO_DIR"

echo "=== Compiling ==="
"$ERLC" -o /tmp src/avm_cbor.erl src/avm_cbor_partial.erl
"$ERLC" -o /tmp test/avm_cbor_atomvm.erl

echo "=== Running under AtomVM (.beam path) ==="
"$ATOMVM" /tmp/avm_cbor.beam /tmp/avm_cbor_partial.beam /tmp/avm_cbor_atomvm.beam "$ATOMVMLIB"

echo "=== (optional) Creating .avm pack ==="
if command -v packbeam &>/dev/null; then
    packbeam create -s avm_cbor_atomvm /tmp/avm_cbor_test.avm /tmp/avm_cbor.beam /tmp/avm_cbor_partial.beam /tmp/avm_cbor_atomvm.beam
    "$ATOMVM" /tmp/avm_cbor_test.avm "$ATOMVMLIB"
    echo "=== .avm pack path also passed ==="
else
    echo "  (packbeam not found - skipping .avm pack test)"
fi

echo "=== All AtomVM validation tests passed ==="
