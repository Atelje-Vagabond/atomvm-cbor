#!/bin/sh
set -e

echo "Compiling avm_cbor.erl..."
erlc -o /tmp src/avm_cbor.erl

echo "Compiling avm_cbor_bench.erl..."
erlc -o /tmp bench/avm_cbor_bench.erl

echo ""
echo "Running benchmark..."
echo "These are OTP host-side microbenchmarks. They are intended as reproducible"
echo "baseline measurements, not ESP32 runtime performance guarantees."
echo ""

if [ -n "$BENCH_ITERATIONS" ]; then
    export BENCH_ITERATIONS
fi

erl -noshell -pa /tmp -eval 'avm_cbor_bench:run().'
