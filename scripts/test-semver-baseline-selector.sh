#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

git -C "${fixture_root}" init -q
git -C "${fixture_root}" config user.name fixture
git -C "${fixture_root}" config user.email fixture@example.invalid

current_version="$(python3 -c 'from pathlib import Path; print(Path("VERSION").read_text().strip())')"
read baseline_older baseline_version unreachable_version empty_version < <(
    CURRENT_VERSION="${current_version}" python3 -c '
import os
major, minor, _patch = (int(part) for part in os.environ["CURRENT_VERSION"].split("."))
if minor > 0:
    older_major, older_minor = major, minor - 1
else:
    older_major, older_minor = major - 1, 9
print(f"{older_major}.{older_minor}.0 {older_major}.{older_minor}.1 {major + 9}.0.0 {major + 1}.0.0")
'
)

printf '%s\n' "${baseline_older}" > "${fixture_root}/VERSION"
git -C "${fixture_root}" add VERSION
git -C "${fixture_root}" commit -q -m "version ${baseline_older}"
git -C "${fixture_root}" tag "v${baseline_older}"

printf '%s\n' "${baseline_version}" > "${fixture_root}/VERSION"
git -C "${fixture_root}" commit -q -am "version ${baseline_version}"
baseline_commit="$(git -C "${fixture_root}" rev-parse HEAD)"
git -C "${fixture_root}" tag "${baseline_version}"

printf '%s\n' "${current_version}" > "${fixture_root}/VERSION"
git -C "${fixture_root}" commit -q -am "version ${current_version}"
git -C "${fixture_root}" tag "${current_version}"

main_branch="$(git -C "${fixture_root}" symbolic-ref --short HEAD)"
git -C "${fixture_root}" switch -q -c unreachable HEAD~2
git -C "${fixture_root}" commit -q --allow-empty -m 'unreachable version'
git -C "${fixture_root}" tag "${unreachable_version}"
git -C "${fixture_root}" switch -q "${main_branch}"

selection="$(python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${fixture_root}")"
CURRENT_VERSION="${current_version}" BASELINE_VERSION="${baseline_version}" python3 -c '
import json, sys
import os
value = json.load(sys.stdin)
assert value["tag"] == os.environ["BASELINE_VERSION"], value
assert value["version"] == os.environ["BASELINE_VERSION"], value
assert value["current_version"] == os.environ["CURRENT_VERSION"], value
' <<< "${selection}"
test "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"])' <<< "${selection}")" = "${baseline_commit}"

git -C "${fixture_root}" tag "v${baseline_version}" "${baseline_commit}"
if python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${fixture_root}" >/dev/null 2>&1; then
    echo "duplicate normalized baseline tags must fail closed" >&2
    exit 1
fi
git -C "${fixture_root}" tag -d "v${baseline_version}" >/dev/null

empty_root="${fixture_root}/empty"
mkdir -p "${empty_root}"
git -C "${empty_root}" init -q
git -C "${empty_root}" config user.name fixture
git -C "${empty_root}" config user.email fixture@example.invalid
printf '%s\n' "${empty_version}" > "${empty_root}/VERSION"
git -C "${empty_root}" add VERSION
git -C "${empty_root}" commit -q -m "version ${empty_version}"
if python3 "${repo_root}/scripts/select-semver-baseline.py" --repo "${empty_root}" >/dev/null 2>&1; then
    echo "missing baseline must fail closed" >&2
    exit 1
fi

echo "SemVer baseline selector tests passed."
