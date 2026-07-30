#!/usr/bin/env bash
set -euo pipefail

mkdir -p coverage

threshold="${COVERAGE_THRESHOLD:-95}"
diff_file="${COVERAGE_DIFF_FILE:-coverage/changed.diff}"

if [ ! -f "${diff_file}" ]; then
    base_ref="${COVERAGE_BASE_REF:-origin/main}"
    merge_base="$(git merge-base HEAD "${base_ref}")"
    git diff --output="${diff_file}" --unified=0 "${merge_base}" -- \
        src/avm_cbor.erl src/avm_cbor_partial.erl
fi

rebar3 do clean, eunit

escript scripts/branch-coverage.escript "${threshold}" "${diff_file}"

coverdata="$(find _build/test/cover -type f -name '*.coverdata' -print -quit)"
if [ -z "${coverdata}" ]; then
    echo "coverage data not found under _build/test/cover" >&2
    exit 1
fi

escript scripts/check-coverage.escript \
    "${coverdata}" "${threshold}" "${diff_file}" coverage/branches.env
