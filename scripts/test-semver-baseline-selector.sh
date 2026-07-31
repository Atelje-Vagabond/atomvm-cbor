#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

git -C "${fixture_root}" init -q
git -C "${fixture_root}" config user.name fixture
git -C "${fixture_root}" config user.email fixture@example.invalid

printf '0.1.0\n' > "${fixture_root}/VERSION"
git -C "${fixture_root}" add VERSION
git -C "${fixture_root}" commit -q -m 'version 0.1.0'
git -C "${fixture_root}" tag v0.1.0

printf '0.1.1\n' > "${fixture_root}/VERSION"
git -C "${fixture_root}" commit -q -am 'version 0.1.1'
baseline_commit="$(git -C "${fixture_root}" rev-parse HEAD)"
git -C "${fixture_root}" tag 0.1.1

printf '0.2.0\n' > "${fixture_root}/VERSION"
git -C "${fixture_root}" commit -q -am 'version 0.2.0'
git -C "${fixture_root}" tag 0.2.0

main_branch="$(git -C "${fixture_root}" symbolic-ref --short HEAD)"
git -C "${fixture_root}" switch -q -c unreachable HEAD~2
git -C "${fixture_root}" commit -q --allow-empty -m 'unreachable version'
git -C "${fixture_root}" tag 9.0.0
git -C "${fixture_root}" switch -q "${main_branch}"

selection="$(python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${fixture_root}")"
python3 -c '
import json, sys
value = json.load(sys.stdin)
assert value["tag"] == "0.1.1", value
assert value["version"] == "0.1.1", value
assert value["current_version"] == "0.2.0", value
' <<< "${selection}"
test "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"])' <<< "${selection}")" = "${baseline_commit}"

git -C "${fixture_root}" tag v0.1.1 "${baseline_commit}"
if python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${fixture_root}" >/dev/null 2>&1; then
    echo "duplicate normalized baseline tags must fail closed" >&2
    exit 1
fi
git -C "${fixture_root}" tag -d v0.1.1 >/dev/null

empty_root="${fixture_root}/empty"
mkdir -p "${empty_root}"
git -C "${empty_root}" init -q
git -C "${empty_root}" config user.name fixture
git -C "${empty_root}" config user.email fixture@example.invalid
printf '1.0.0\n' > "${empty_root}/VERSION"
git -C "${empty_root}" add VERSION
git -C "${empty_root}" commit -q -m 'version 1.0.0'
if python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${empty_root}" >/dev/null 2>&1; then
    echo "missing baseline must fail closed" >&2
    exit 1
fi

echo "SemVer baseline selector tests passed."
