#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

version="$(tr -d '\r\n' < VERSION)"
test "${version}" = "0.2.0"

grep -Fq '{vsn, "0.2.0"}' src/avm_cbor.app.src
grep -Fq '{pkg_name, atomvm_cbor}' src/avm_cbor.app.src
grep -Fq '{licenses, ["MIT"]}' src/avm_cbor.app.src
grep -Fq 'https://github.com/Atelje-Vagabond/atomvm-cbor' src/avm_cbor.app.src
grep -Fq '{prefix_ref_vsn_with_v, false}' rebar.config
grep -Fq '# atomvm-cbor 0.2.0' .github/releases/0.2.0.md
grep -Fq '## 0.2.0' CHANGELOG.md

if grep -RInF 'v0.2.0' \
    README.md CHANGELOG.md VERSION src docs scripts .github \
    --exclude='source-integrity.sha256' \
    --exclude='check-release-metadata.sh' \
    --exclude='publish-hex.yml'; then
    echo 'FAIL: new release surfaces must use 0.2.0 without a v prefix.' >&2
    exit 1
fi

sha256sum --check scripts/source-integrity.sha256

for required in \
    README.md CHANGELOG.md LICENSE VERSION rebar.config docs/api.md \
    src/avm_cbor.app.src .github/releases/0.2.0.md; do
    test -s "${required}"
done

echo 'Release metadata and runtime integrity checks passed.'
