#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [ -z "${version}" ]; then
    echo "usage: scripts/release-check.sh VERSION" >&2
    exit 2
fi
if [ "${version}" != "$(tr -d '\r\n' < VERSION)" ]; then
    echo "release version does not match VERSION" >&2
    exit 1
fi

bash scripts/check-release-metadata.sh
python3 scripts/gen-api-docs.py --check
rebar3 compile
bash scripts/test-public.sh
bash scripts/test-benchmark-regression-gate.sh
rebar3 xref
bash scripts/bench.sh

echo "PUBLIC_RELEASE_CHECK_OK version=${version}"
