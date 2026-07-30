#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 UNPACKED_PACKAGE_DIR" >&2
    exit 2
fi

package_dir="$1"
test -d "${package_dir}"

for required in \
    src/avm_cbor.erl src/avm_cbor_partial.erl src/avm_cbor_opts.hrl \
    src/avm_cbor.app.src rebar.config VERSION README.md CHANGELOG.md \
    LICENSE docs/api.md; do
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
hex_metadata.config
rebar.config
src/avm_cbor.app.src
src/avm_cbor.erl
src/avm_cbor_opts.hrl
src/avm_cbor_partial.erl
FILES
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
