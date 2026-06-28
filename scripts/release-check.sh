#!/bin/sh
set -e

if [ $# -eq 0 ]; then
    echo "FAIL: No version argument provided."
    echo "Usage: $0 <version> [--with-esp-idf]"
    echo "Example: $0 v0.1.1"
    exit 1
fi

VERSION="$1"
WITH_ESP_IDF=false

if [ "$2" = "--with-esp-idf" ]; then
    WITH_ESP_IDF=true
fi

TOTAL=0
PASSED=0

check() {
    TOTAL=$((TOTAL + 1))
    if [ "$1" -eq 0 ]; then
        echo "  PASS: $2"
        PASSED=$((PASSED + 1))
    else
        echo "  FAIL: $2"
    fi
}

echo ""
echo "=== Release Check: $VERSION ==="
echo ""

echo "--- Step 1: Compile src/avm_cbor.erl ---"
erlc -o /tmp src/avm_cbor.erl
check $? "compile avm_cbor.erl"

echo ""
echo "--- Step 2: Compile and run smoke tests ---"
erlc -o /tmp test/avm_cbor_smoke.erl
erl -noshell -pa /tmp -eval 'avm_cbor_smoke:run().'
check $? "smoke tests pass"

echo ""
echo "--- Step 3: Run benchmark suite ---"
sh scripts/bench.sh
check $? "benchmark runner succeeds"

echo ""
echo "--- Step 4: Verify benchmark report exists ---"
REPORT="docs/benchmarks/$VERSION.md"
if [ -f "$REPORT" ]; then
    check 0 "benchmark report $REPORT exists"
else
    check 1 "benchmark report $REPORT missing"
fi

echo ""
echo "--- Step 5: Verify docs/benchmarks.md links to version ---"
if grep -q "$VERSION" docs/benchmarks.md 2>/dev/null; then
    check 0 "docs/benchmarks.md links to $VERSION"
else
    check 1 "docs/benchmarks.md does not link to $VERSION"
fi

echo ""
echo "--- Step 6: ESP-IDF validation ---"
if [ "$WITH_ESP_IDF" = true ]; then
    if command -v docker >/dev/null 2>&1; then
        set +e
        echo "  Running ESP-IDF v5.4.3..."
        sh scripts/test-esp-idf.sh v5.4.3
        check $? "ESP-IDF v5.4.3 validation"
        echo "  Running ESP-IDF v5.5.2..."
        sh scripts/test-esp-idf.sh v5.5.2
        check $? "ESP-IDF v5.5.2 validation"
        set -e
    else
        echo "  FAIL: --with-esp-idf requested but Docker is not available."
        TOTAL=$((TOTAL + 1))
    fi
else
    echo "  SKIP (use --with-esp-idf to include ESP-IDF validation)"
fi

echo ""
echo "=== Result ==="
if [ "$PASSED" -eq "$TOTAL" ]; then
    echo "PASS: $PASSED/$TOTAL checks passed."
    exit 0
else
    echo "FAIL: $PASSED/$TOTAL checks passed."
    exit 1
fi
