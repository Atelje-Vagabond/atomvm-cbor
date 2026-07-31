#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

erlc -Wall -DTEST -o "${test_dir}" \
    src/avm_cbor.erl src/avm_cbor_cont.erl src/avm_cbor_partial.erl
erlc -Wall -DTEST -o "${test_dir}" -pa "${test_dir}" \
    test/avm_cbor_smoke.erl \
    test/avm_cbor_partial_tests.erl \
    test/avm_cbor_rfc8949.erl \
    test/avm_cbor_coverage_tests.erl \
    test/avm_cbor_deterministic_decode_tests.erl \
    test/avm_cbor_security_tests.erl \
    test/avm_cbor_property_tests.erl \
    test/avm_cbor_continuation_tests.erl

erl -noshell -pa "${test_dir}" -eval 'avm_cbor_smoke:run().'
erl -noshell -pa "${test_dir}" -eval 'avm_cbor_partial_tests:run().'
erl -noshell -pa "${test_dir}" -eval 'avm_cbor_rfc8949:run().'
erl -noshell -pa "${test_dir}" -eval \
    'case eunit:test([avm_cbor_coverage_tests, avm_cbor_deterministic_decode_tests, avm_cbor_security_tests, avm_cbor_property_tests, avm_cbor_continuation_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'

echo "PUBLIC_TESTS_OK"
