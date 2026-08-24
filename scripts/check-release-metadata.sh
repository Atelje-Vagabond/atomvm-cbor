#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

version="$(python3 scripts/read-release-version.py)"
release_notes=".github/releases/${version}.md"
mapfile -t evidence_identity < <(python3 - <<'PY'
import json
import re
from pathlib import Path

version = Path("VERSION").read_text(encoding="utf-8").strip()
manifest = json.loads(
    Path(f"docs/benchmarks/data/{version}.json").read_text(encoding="utf-8")
)
release_notes = Path(f".github/releases/{version}.md").read_text(encoding="utf-8")
match = re.search(
    rf"\]\(\.\./\.\./blob/([0-9a-f]{{40}})/docs/benchmarks/{re.escape(version)}\.md\)",
    release_notes,
)
if match is None:
    raise SystemExit("release report link must use a full immutable commit SHA")
print(match.group(1))
print(manifest["baseline"]["version"])
PY
)
report_snapshot_commit="${evidence_identity[0]}"
baseline_version="${evidence_identity[1]}"

grep -Fq "{vsn, \"${version}\"}" src/avm_cbor.app.src
grep -Fq '{pkg_name, atomvm_cbor}' src/avm_cbor.app.src
grep -Fq '{licenses, ["MIT"]}' src/avm_cbor.app.src
grep -Fq 'https://github.com/Atelje-Vagabond/atomvm-cbor' src/avm_cbor.app.src
grep -Fq '{prefix_ref_vsn_with_v, false}' rebar.config
grep -Fq '{"docs/benchmarks.md", #{title => "Benchmark Methodology"}}' rebar.config
grep -Fq 'filelib:wildcard("docs/benchmarks/*.md")' rebar.config.script
grep -Fq '"^v?[0-9]+\\.[0-9]+\\.[0-9]+\\.md$"' rebar.config.script
grep -Fq "# atomvm-cbor ${version}" "${release_notes}"
grep -Fq "## ${version}" CHANGELOG.md
grep -Fq "](../../blob/${report_snapshot_commit}/docs/benchmarks/${version}.md)" "${release_notes}"
grep -Fq "](../../blob/${baseline_version}/docs/benchmarks/${baseline_version}.md)" "${release_notes}"
git cat-file -e "${report_snapshot_commit}^{commit}"
git cat-file -e "refs/tags/${baseline_version}^{commit}"
git show "${report_snapshot_commit}:docs/benchmarks/${version}.md" |
    cmp - "docs/benchmarks/${version}.md"

if grep -Fq '](../../docs/' "${release_notes}"; then
    echo 'FAIL: release-note repository links must include an immutable ref path.' >&2
    exit 1
fi

if grep -RInF "v${version}" \
    README.md CHANGELOG.md VERSION src docs scripts .github \
    --exclude='source-integrity.sha256' \
    --exclude='check-release-metadata.sh'; then
    echo "FAIL: new release surfaces must use ${version} without a v prefix." >&2
    exit 1
fi

if grep -RInF "${version}" .github/workflows; then
    echo 'FAIL: workflows must derive the release version from VERSION.' >&2
    exit 1
fi

python3 - <<'PY'
import re
import subprocess
from pathlib import Path

current = Path("VERSION").read_text(encoding="utf-8").strip()
versions = {current}
for tag in subprocess.check_output(
    ["git", "tag", "--merged", "HEAD", "--list"], text=True
).splitlines():
    normalized = tag[1:] if tag.startswith("v") else tag
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", normalized):
        versions.add(normalized)

patterns = {
    version: re.compile(
        rf"(?<![0-9A-Za-z.])v?{re.escape(version)}(?![0-9A-Za-z.])"
    )
    for version in versions
}
failures = []
tracked_and_pending = subprocess.check_output(
    [
        "git", "ls-files", "--cached", "--others", "--exclude-standard", "--",
        ".github/workflows", "scripts", "bench",
    ],
    text=True,
).splitlines()
for name in sorted(set(tracked_and_pending)):
    path = Path(name)
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for line_number, line in enumerate(text.splitlines(), 1):
        for version, pattern in patterns.items():
            if pattern.search(line):
                failures.append(f"{path}:{line_number}: repository release {version}")
if failures:
    raise SystemExit(
        "workflow/script/benchmark release versions must be derived dynamically:\n"
        + "\n".join(failures)
    )
print("Workflow, script, and benchmark release-version literals are absent.")
PY

sha256sum --check scripts/source-integrity.sha256

python3 - <<'PY'
import re
from pathlib import Path

workflow = Path(".github/workflows/release-gate.yml").read_text(encoding="utf-8")


def job(name: str) -> str:
    match = re.search(
        rf"^  {re.escape(name)}:\n(.*?)(?=^  [a-z0-9-]+:\n|\Z)",
        workflow,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"release workflow job is missing: {name}")
    return match.group(1)


performance = job("performance")
if not re.search(r"^    needs: hygiene$", performance, re.MULTILINE):
    raise SystemExit("performance must run only after hygiene")
if "needs.hygiene.outputs.performance == 'true'" not in performance:
    raise SystemExit("performance must be selected by the changed-path classifier")
if "github.event.pull_request.head.repo.full_name == github.repository" not in performance:
    raise SystemExit("performance must reject untrusted fork code on the hardware runner")
if not re.search(r"^    runs-on:\n      group: public-performance$", performance, re.MULTILINE):
    raise SystemExit("performance must use the isolated public-performance runner group")
if "erlang@sha256:d10c0a75dc48c09b76c5a789e49cb1a99896f26880be83ddad2af8e79be99dba" not in performance:
    raise SystemExit("performance must use the pinned OTP 29 container")
if "--pull=never" not in performance:
    raise SystemExit("performance must not pull a mutable benchmark image")
if 'BENCHMARK_NOISE_TOLERANCE_PERCENT: "5"' not in performance:
    raise SystemExit("performance regression threshold must remain 5 percent")
if "scripts/test-semver-baseline-selector.sh" not in performance:
    raise SystemExit("performance must prove fail-closed SemVer selection")

benchmark_script = Path("scripts/benchmark-remediation.sh").read_text(encoding="utf-8")
for required in (
    'if [ "${benchmark_otp}" != "29" ]',
    "PERFORMANCE_RUNTIME otp=%s",
    "git archive \"${baseline_tag}\" src",
    "PERFORMANCE_BASELINE_CAPABILITIES",
    "erl +S 1:1 +SDcpu 1:1 +SDio 1",
    'baseline_id="${baseline_version}-${baseline_commit:0:12}"',
    'current_id="${current_version}-${fixed_commit:0:12}"',
    'performance_paths=(',
    'git diff --quiet "${fixed_commit}" -- "${performance_paths[@]}"',
    'git diff --quiet "${baseline_commit}..${fixed_commit}" --',
    '"${performance_paths[@]}"',
    'mode=exact-source-reuse',
):
    if required not in benchmark_script:
        raise SystemExit(f"dynamic/stable benchmark invariant is missing: {required}")

otp = job("otp")
if not re.search(r"^    needs: hygiene$", otp, re.MULTILINE):
    raise SystemExit("otp must run independently after hygiene")
if "needs.hygiene.outputs.otp == 'true'" not in otp:
    raise SystemExit("otp must be selected by the changed-path classifier")
if 'otp: ["25", "27", "29"]' not in otp:
    raise SystemExit("otp compatibility matrix must cover 25, 27, and 29")
if "needs.performance.result" in otp:
    raise SystemExit("otp must not be skipped when selected performance fails")

for name in ("coverage", "atomvm", "esp-idf", "package"):
    body = job(name)
    if not re.search(r"^    needs: \[hygiene, performance\]$", body, re.MULTILINE):
        raise SystemExit(f"{name} must depend on hygiene and performance")
    output_name = name.replace("-", "_")
    if f"needs.hygiene.outputs.{output_name} == 'true'" not in body:
        raise SystemExit(f"{name} must be selected by the changed-path classifier")
    if "needs.performance.result == 'success'" not in body:
        raise SystemExit(f"{name} must fail closed when selected performance fails")

hygiene = job("hygiene")
if "scripts/test-ci-change-routing.sh" not in hygiene:
    raise SystemExit("hygiene must test changed-path routing")
if "PR_ACTION" not in hygiene or "PR_BEFORE_SHA" not in hygiene:
    raise SystemExit("hygiene must route PR updates from the previous exact head")

classifier = Path("scripts/classify-ci-changes.sh").read_text(encoding="utf-8")
if "--diff-filter=ACDMRT" not in classifier:
    raise SystemExit("routing must classify deleted paths as well as added/changed paths")

release_ready = job("release-ready")
if not re.search(r"^    if: always\(\)$", release_ready, re.MULTILINE):
    raise SystemExit("release-ready must inspect skipped and selected job results")
if "PUBLIC_RELEASE_GATE_OK" not in release_ready:
    raise SystemExit("release-ready success marker is missing")

package = job("package")
if package.count("warning: documentation references file") != 2:
    raise SystemExit("package validation must reject broken HexDocs file references")

publish_workflow = Path(".github/workflows/publish-hex.yml").read_text(encoding="utf-8")
if publish_workflow.count("warning: documentation references file") != 2:
    raise SystemExit("publication preflight must reject broken HexDocs file references")
for required in (
    "actions: read",
    'git merge-base --is-ancestor "${tag_commit}" refs/remotes/origin/main',
    'actions/workflows/release-gate.yml/runs',
    'head_branch == "\'"${RELEASE_VERSION}"\'"',
    'head_sha == "\'"${tag_commit}"\'"',
    "successful exact release-tag gate is missing",
):
    if required not in publish_workflow:
        raise SystemExit(f"publication ancestry/tag-gate invariant is missing: {required}")

print("Release workflow routing, order, and unchanged 5 percent threshold passed.")
PY

for required in \
    README.md CHANGELOG.md LICENSE VERSION rebar.config rebar.config.script docs/api.md \
    docs/benchmarks.md docs/benchmarks/*.md \
    src/avm_cbor.app.src "${release_notes}"; do
    test -s "${required}"
done

python3 scripts/release-evidence.py

echo 'Release metadata and runtime integrity checks passed.'
