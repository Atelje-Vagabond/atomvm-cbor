#!/bin/sh
set -e

echo "Compiling runtime modules..."
erlc -o /tmp src/avm_cbor.erl src/avm_cbor_cont.erl src/avm_cbor_partial.erl

echo "Compiling avm_cbor_bench.erl..."
erlc -o /tmp -pa /tmp bench/avm_cbor_bench.erl

echo ""
echo "Running benchmark..."
erl -noshell -pa /tmp -eval 'avm_cbor_bench:run(), halt().'
