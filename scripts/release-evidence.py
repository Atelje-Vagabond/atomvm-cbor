#!/usr/bin/env python3
"""Validate structured release evidence and render checked Markdown tables."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
REQUIRED_TARGETS = ["esp32-s3-n16r8", "waveshare-n32r16v", "rp2040"]
COMMON_WORKLOADS = [
    "encode/1",
    "decode/1",
    "partial_decode/1",
    "partial_decode/2",
    "partial_deep_decode/1",
    "partial_value_bytes/1",
    "partial_contents/1",
    "partial_skip/1",
    "partial_type/1",
    "partial_count/1",
    "partial_tag/1",
    "partial_size/1",
    "partial_offset/1",
    "partial_length/1",
]
CANDIDATE_ONLY_WORKLOADS = [
    "encode_with_size_nested",
    "encode_sequence_32",
    "sequence_fold_32",
    "validate_all_nested",
    "partial_map_fold",
    "partial_array_fold",
    "partial_select",
    "partial_map_find",
    "partial_array_nth",
]
FORBIDDEN_MARKERS = ["task_wdt", "Backtrace", "panic", "abort", "OOM"]


def fail(message: str) -> None:
    raise ValueError(message)


def require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{path} must be a non-empty string")
    return value


def require_positive_number(value: Any, path: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool) or value <= 0:
        fail(f"{path} must be a positive number")
    return float(value)


def require_sha256(value: Any, path: str) -> str:
    text = require_string(value, path)
    if len(text) != 64 or any(char not in "0123456789abcdef" for char in text):
        fail(f"{path} must be a lowercase SHA-256")
    return text


def require_exact_keys(actual: Any, expected: list[str], path: str) -> dict[str, Any]:
    if not isinstance(actual, dict):
        fail(f"{path} must be an object")
    actual_keys = list(actual)
    missing = [key for key in expected if key not in actual]
    extra = [key for key in actual if key not in expected]
    if missing or extra:
        fail(f"{path} key mismatch: missing={missing}, extra={extra}")
    return actual


def load_manifest() -> tuple[Path, dict[str, Any]]:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    path = ROOT / "docs" / "benchmarks" / "data" / f"{version}.json"
    if not path.is_file():
        fail(f"release evidence manifest is missing: {path.relative_to(ROOT)}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        fail("schema_version must be 1")
    if data.get("release") != version:
        fail(f"manifest release must match VERSION ({version})")
    return path, data


def validate_manifest(data: dict[str, Any]) -> None:
    require_string(data.get("baseline", {}).get("version"), "baseline.version")
    require_string(data.get("baseline", {}).get("commit"), "baseline.commit")
    require_string(data.get("candidate", {}).get("version"), "candidate.version")
    require_string(data.get("candidate", {}).get("commit"), "candidate.commit")
    require_sha256(data.get("harness", {}).get("common_sha256"), "harness.common_sha256")
    require_sha256(
        data.get("harness", {}).get("candidate_only_sha256"),
        "harness.candidate_only_sha256",
    )
    require_sha256(
        data.get("harness", {}).get("functional_soak_sha256"),
        "harness.functional_soak_sha256",
    )
    require_sha256(
        data.get("harness", {}).get("candidate_only_pack_sha256"),
        "harness.candidate_only_pack_sha256",
    )
    require_sha256(
        data.get("harness", {}).get("functional_soak_entry_sha256"),
        "harness.functional_soak_entry_sha256",
    )
    require_sha256(
        data.get("harness", {}).get("functional_soak_pack_sha256"),
        "harness.functional_soak_pack_sha256",
    )

    candidate_bundle = data.get("candidate_only_evidence_bundle")
    if not isinstance(candidate_bundle, dict):
        fail("candidate_only_evidence_bundle must be an object")
    require_string(
        candidate_bundle.get("artifact_name"),
        "candidate_only_evidence_bundle.artifact_name",
    )
    require_sha256(
        candidate_bundle.get("artifact_sha256"),
        "candidate_only_evidence_bundle.artifact_sha256",
    )
    require_string(
        candidate_bundle.get("location"),
        "candidate_only_evidence_bundle.location",
    )

    if data.get("required_targets") != REQUIRED_TARGETS:
        fail(f"required_targets must be exactly {REQUIRED_TARGETS}")
    if data.get("common_workloads") != COMMON_WORKLOADS:
        fail("common_workloads does not match the mandatory workload set/order")
    if data.get("candidate_only_workloads") != CANDIDATE_ONLY_WORKLOADS:
        fail("candidate_only_workloads does not match the mandatory workload set/order")

    targets = require_exact_keys(data.get("targets"), REQUIRED_TARGETS, "targets")
    for target_id in REQUIRED_TARGETS:
        target = targets[target_id]
        for field in ("display_name", "short_name", "identity", "cpu", "memory"):
            require_string(target.get(field), f"targets.{target_id}.{field}")

        common_evidence = target.get("common_evidence")
        if not isinstance(common_evidence, dict):
            fail(f"targets.{target_id}.common_evidence must be an object")
        if common_evidence.get("capture_count") != 10:
            fail(f"targets.{target_id}.common_evidence.capture_count must be 10")
        require_sha256(
            common_evidence.get("log_set_sha256"),
            f"targets.{target_id}.common_evidence.log_set_sha256",
        )
        require_string(
            common_evidence.get("location"),
            f"targets.{target_id}.common_evidence.location",
        )

        common = require_exact_keys(
            target.get("common_results"),
            COMMON_WORKLOADS,
            f"targets.{target_id}.common_results",
        )
        for workload in COMMON_WORKLOADS:
            result = common[workload]
            require_positive_number(
                result.get("baseline_us"),
                f"targets.{target_id}.common_results.{workload}.baseline_us",
            )
            require_positive_number(
                result.get("candidate_us"),
                f"targets.{target_id}.common_results.{workload}.candidate_us",
            )

        candidate_only = require_exact_keys(
            target.get("candidate_only_results"),
            CANDIDATE_ONLY_WORKLOADS,
            f"targets.{target_id}.candidate_only_results",
        )
        for workload in CANDIDATE_ONLY_WORKLOADS:
            result = candidate_only[workload]
            runs = result.get("runs_us") if isinstance(result, dict) else None
            if not isinstance(runs, list) or len(runs) != 5:
                fail(
                    f"targets.{target_id}.candidate_only_results.{workload}.runs_us "
                    "must contain five measurements"
                )
            for index, value in enumerate(runs):
                require_positive_number(
                    value,
                    f"targets.{target_id}.candidate_only_results.{workload}.runs_us[{index}]",
                )
        candidate_evidence = target.get("candidate_only_evidence")
        if not isinstance(candidate_evidence, dict):
            fail(f"targets.{target_id}.candidate_only_evidence must be an object")
        if candidate_evidence.get("capture_count") != 5:
            fail(f"targets.{target_id}.candidate_only_evidence.capture_count must be 5")
        require_sha256(
            candidate_evidence.get("log_set_sha256"),
            f"targets.{target_id}.candidate_only_evidence.log_set_sha256",
        )
        require_string(
            candidate_evidence.get("location"),
            f"targets.{target_id}.candidate_only_evidence.location",
        )

        soak = target.get("functional_soak")
        if not isinstance(soak, dict):
            fail(f"targets.{target_id}.functional_soak must be an object")
        if soak.get("result") != "pass":
            fail(f"targets.{target_id}.functional_soak.result must be pass")
        if soak.get("rounds") != 40:
            fail(f"targets.{target_id}.functional_soak.rounds must be 40")
        if soak.get("forbidden_markers_absent") is not True:
            fail(
                f"targets.{target_id}.functional_soak.forbidden_markers_absent "
                f"must prove absence of {FORBIDDEN_MARKERS}"
            )
        for field in (
            "source_commit",
            "run_label",
            "evidence_url",
            "artifact_name",
        ):
            require_string(soak.get(field), f"targets.{target_id}.functional_soak.{field}")
        require_sha256(
            soak.get("artifact_sha256"),
            f"targets.{target_id}.functional_soak.artifact_sha256",
        )
        for field in (
            "first_heap_max_words",
            "late_heap_max_words",
            "first_memory_max_bytes",
            "late_memory_max_bytes",
        ):
            require_positive_number(
                soak.get(field), f"targets.{target_id}.functional_soak.{field}"
            )


def marker(name: str, edge: str) -> str:
    return f"<!-- release-evidence:{name}:{edge} -->"


def generated_block(name: str, body: str) -> str:
    return f"{marker(name, 'start')}\n{body.rstrip()}\n{marker(name, 'end')}"


def replace_block(text: str, name: str, body: str) -> str:
    start = marker(name, "start")
    end = marker(name, "end")
    if text.count(start) != 1 or text.count(end) != 1:
        fail(f"document must contain exactly one {name} generated block")
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    return before + generated_block(name, body) + after


def change_text(baseline: float, candidate: float) -> str:
    percent = abs((candidate - baseline) * 100.0 / baseline)
    direction = "faster" if candidate <= baseline else "slower"
    return f"{percent:.2f}% {direction}"


def signed_change(baseline: float, candidate: float) -> float:
    return (candidate - baseline) * 100.0 / baseline


def mermaid_label(value: str) -> str:
    return value.replace("&", "&amp;").replace('"', "&quot;")


def current_release_charts(data: dict[str, Any]) -> str:
    baseline_version = mermaid_label(data["baseline"]["version"])
    candidate_version = mermaid_label(data["candidate"]["version"])
    workloads = ["encode/1", "decode/1", "partial_decode/1"]
    candidate_colors = {
        "esp32-s3-n16r8": "#5C2D91",
        "waveshare-n32r16v": "#65AE00",
        "rp2040": "#2F80ED",
    }
    lines = [
        "Representative attached-device benchmark changes from "
        f"{baseline_version} to {candidate_version}. Negative is faster; positive is "
        "slower. Chart labels are percentages rounded to two decimal places; exact "
        "timings follow in the benchmark table.",
    ]

    for target_id in REQUIRED_TARGETS:
        target = data["targets"][target_id]
        changes = []
        for workload in workloads:
            result = target["common_results"][workload]
            changes.append(
                signed_change(
                    float(result["baseline_us"]), float(result["candidate_us"])
                )
            )
        axis_limit = (
            math.ceil(max(0.01, max(abs(change) for change in changes)) * 1.2 * 100)
            / 100
        )
        change_bars = ", ".join(f"{change:.2f}" for change in changes)
        title = mermaid_label(f"{target['short_name']} at {target['cpu']}")
        lines.extend(
            [
                "",
                "```mermaid",
                "---",
                "config:",
                "  xyChart:",
                "    height: 360",
                "    showDataLabel: true",
                "    showDataLabelOutsideBar: true",
                "  themeVariables:",
                "    xyChart:",
                f'      plotColorPalette: "{candidate_colors[target_id]}"',
                "---",
                "xychart-beta",
                f'    title "{title}"',
                '    x-axis ["encode/1", "decode/1", "partial_decode/1"]',
                f'    y-axis "Timing change (%)" {-axis_limit:.2f} --> {axis_limit:.2f}',
                f"    bar [{change_bars}]",
                "```",
            ]
        )
    return "\n".join(lines)


def identity_table(data: dict[str, Any], compact: bool = False) -> str:
    targets = data["targets"]
    if compact:
        lines = ["| Board | Exact identity | CPU |", "|---|---|---:|"]
        for target_id in REQUIRED_TARGETS:
            target = targets[target_id]
            lines.append(
                f"| {target['display_name']} | {target['identity']} | {target['cpu']} |"
            )
        return "\n".join(lines)
    lines = [
        "| Board | Exact physical identity | CPU | Flash / PSRAM |",
        "| :--- | :--- | ---: | :--- |",
    ]
    for target_id in REQUIRED_TARGETS:
        target = targets[target_id]
        lines.append(
            f"| {target['display_name']} | {target['identity']} | "
            f"{target['cpu']} | {target['memory']} |"
        )
    return "\n".join(lines)


def common_table(data: dict[str, Any], workloads: list[str] | None = None) -> str:
    targets = data["targets"]
    workloads = workloads or COMMON_WORKLOADS
    names = [targets[target_id]["short_name"] for target_id in REQUIRED_TARGETS]
    baseline_version = data["baseline"]["version"]
    candidate_version = data["candidate"]["version"]
    lines = [
        "| Function | "
        + " | ".join(
            f"{name} {baseline_version} µs | {candidate_version} µs | Change"
            for name in names
        )
        + " |",
        "| :--- | " + " | ".join("---: | ---: | :---" for _ in names) + " |",
    ]
    for workload in workloads:
        cells = []
        for target_id in REQUIRED_TARGETS:
            result = targets[target_id]["common_results"][workload]
            baseline = float(result["baseline_us"])
            candidate = float(result["candidate_us"])
            cells.extend(
                [f"{baseline:.2f}", f"{candidate:.2f}", change_text(baseline, candidate)]
            )
        lines.append(f"| `{workload}` | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def common_summary(data: dict[str, Any]) -> str:
    rows = [
        "Comparable-workload totals:",
        "",
        "| Scope | Faster rows | Slower rows | Net average change |",
        "| :--- | ---: | ---: | ---: |",
    ]
    all_changes = []
    for target_id in REQUIRED_TARGETS:
        target = data["targets"][target_id]
        changes = []
        for workload in COMMON_WORKLOADS:
            result = target["common_results"][workload]
            changes.append(
                signed_change(
                    float(result["baseline_us"]), float(result["candidate_us"])
                )
            )
        all_changes.extend(changes)
        average = statistics.mean(changes)
        rows.append(
            f"| {target['display_name']} | {sum(change < 0 for change in changes)} | "
            f"{sum(change > 0 for change in changes)} | {average:+.2f}% |"
        )
    overall = statistics.mean(all_changes)
    rows.append(
        f"| All {len(all_changes)} board/workload results | "
        f"{sum(change < 0 for change in all_changes)} | "
        f"{sum(change > 0 for change in all_changes)} | {overall:+.2f}% |"
    )
    rows.extend(
        [
            "",
            "The net average is the unweighted arithmetic mean of the signed "
            "per-row changes in this exact comparison matrix. Negative is faster; "
            "positive is slower. Current-only workloads with an `N/A` baseline are "
            "excluded.",
        ]
    )
    return "\n".join(rows)


def candidate_only_table(data: dict[str, Any], include_ranges: bool = True) -> str:
    targets = data["targets"]
    names = [targets[target_id]["short_name"] for target_id in REQUIRED_TARGETS]
    baseline_version = data["baseline"]["version"]
    candidate_version = data["candidate"]["version"]
    lines = [
        f"| Workload | {baseline_version} baseline | "
        + " | ".join(
            f"{name} {candidate_version} median µs"
            + (" (five-run range)" if include_ranges else "")
            for name in names
        )
        + " |",
        "| :--- | :---: | " + " | ".join("---:" for _ in names) + " |",
    ]
    for workload in CANDIDATE_ONLY_WORKLOADS:
        cells = []
        for target_id in REQUIRED_TARGETS:
            runs = targets[target_id]["candidate_only_results"][workload]["runs_us"]
            median = statistics.median(runs)
            if include_ranges:
                cells.append(f"{median:.2f} ({min(runs):.2f}-{max(runs):.2f})")
            else:
                cells.append(f"{median:.2f}")
        lines.append(f"| `{workload}` | N/A | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def candidate_only_evidence(data: dict[str, Any]) -> str:
    bundle = data["candidate_only_evidence_bundle"]
    lines = [
        "Evidence identities:",
        "",
        f"- Candidate-only harness SHA-256: "
        f"`{data['harness']['candidate_only_sha256']}`.",
        f"- Candidate-only pack SHA-256: "
        f"`{data['harness']['candidate_only_pack_sha256']}`.",
        f"- Evidence bundle: `{bundle['artifact_name']}` "
        f"(SHA-256 `{bundle['artifact_sha256']}`), {bundle['location']}.",
    ]
    for target_id in REQUIRED_TARGETS:
        target = data["targets"][target_id]
        evidence = target["candidate_only_evidence"]
        lines.append(
            f"- {target['display_name']}: {evidence['capture_count']} captures, "
            f"log-set SHA-256 `{evidence['log_set_sha256']}`; "
            f"{evidence['location']}."
        )
    return "\n".join(lines)


def soak_table(data: dict[str, Any]) -> str:
    lines = [
        "| Board | First/late heap maximum | First/late memory maximum | Rounds | Result |",
        "| :--- | ---: | ---: | ---: | :--- |",
    ]
    evidence_lines = ["", "Evidence identities:", ""]
    for target_id in REQUIRED_TARGETS:
        target = data["targets"][target_id]
        soak = target["functional_soak"]
        lines.append(
            f"| {target['display_name']} | "
            f"{soak['first_heap_max_words']} / {soak['late_heap_max_words']} words | "
            f"{soak['first_memory_max_bytes']} / {soak['late_memory_max_bytes']} bytes | "
            f"{soak['rounds']} | {soak['result']} |"
        )
        evidence_lines.append(
            f"- {target['display_name']}: [{soak['run_label']}]({soak['evidence_url']}), "
            f"source `{soak['source_commit']}`, `{soak['artifact_name']}` "
            f"(SHA-256 `{soak['artifact_sha256']}`)."
        )
    return "\n".join(lines + evidence_lines)


def manifest_identity(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return f"Manifest: `{path.relative_to(ROOT)}` (SHA-256 `{digest}`)."


def render_documents(path: Path, data: dict[str, Any]) -> dict[Path, str]:
    version = data["release"]
    report = ROOT / "docs" / "benchmarks" / f"{version}.md"
    notes = ROOT / ".github" / "releases" / f"{version}.md"
    readme = ROOT / "README.md"

    report_text = report.read_text(encoding="utf-8")
    report_text = replace_block(report_text, "report-identities", identity_table(data))
    report_text = replace_block(
        report_text, "report-common", common_table(data) + "\n\n" + common_summary(data)
    )
    report_text = replace_block(
        report_text,
        "report-candidate-only",
        candidate_only_table(data, include_ranges=False)
        + "\n\n"
        + candidate_only_evidence(data)
        + "\n\n"
        + manifest_identity(path),
    )
    report_text = replace_block(report_text, "report-soak", soak_table(data))

    notes_text = notes.read_text(encoding="utf-8")
    notes_text = replace_block(notes_text, "notes-identities", identity_table(data))
    notes_text = replace_block(notes_text, "notes-common", common_table(data))
    notes_text = replace_block(
        notes_text,
        "notes-candidate-only",
        candidate_only_table(data) + "\n\n" + candidate_only_evidence(data),
    )
    notes_text = replace_block(notes_text, "notes-soak", soak_table(data))

    readme_text = readme.read_text(encoding="utf-8")
    readme_text = replace_block(
        readme_text, "readme-current-release", current_release_charts(data)
    )
    readme_text = replace_block(
        readme_text, "readme-identities", identity_table(data, compact=True)
    )
    readme_text = replace_block(
        readme_text,
        "readme-summary",
        common_table(data, ["encode/1", "decode/1", "partial_decode/1"]),
    )

    return {report: report_text, notes: notes_text, readme: readme_text}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write",
        action="store_true",
        help="rewrite generated Markdown blocks after validating the manifest",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate the manifest without checking generated Markdown",
    )
    args = parser.parse_args()

    try:
        path, data = load_manifest()
        validate_manifest(data)
        if args.validate_only:
            print(f"Release evidence manifest passed: {path.relative_to(ROOT)}")
            return 0
        documents = render_documents(path, data)
        if args.write:
            for document, rendered in documents.items():
                document.write_text(rendered, encoding="utf-8")
            print("Release evidence Markdown blocks regenerated.")
            return 0
        stale = []
        for document, rendered in documents.items():
            if document.read_text(encoding="utf-8") != rendered:
                stale.append(str(document.relative_to(ROOT)))
        if stale:
            fail(f"generated release evidence is stale: {stale}; run --write")
        print("Release evidence manifest and generated Markdown blocks passed.")
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
