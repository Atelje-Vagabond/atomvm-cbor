#!/usr/bin/env python3
"""Select the highest reachable SemVer below VERSION, or fail closed."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


SEMVER = re.compile(
    r"^v?(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


@dataclass(frozen=True)
class Version:
    major: int
    minor: int
    patch: int
    prerelease: tuple[str, ...]
    build: tuple[str, ...]

    @property
    def normalized(self) -> str:
        value = f"{self.major}.{self.minor}.{self.patch}"
        if self.prerelease:
            value += "-" + ".".join(self.prerelease)
        if self.build:
            value += "+" + ".".join(self.build)
        return value


@dataclass(frozen=True)
class Candidate:
    tag: str
    version: Version
    commit: str


def parse_version(value: str) -> Version | None:
    match = SEMVER.fullmatch(value.strip())
    if not match:
        return None
    major, minor, patch, prerelease, build = match.groups()
    return Version(
        int(major),
        int(minor),
        int(patch),
        tuple(prerelease.split(".")) if prerelease else (),
        tuple(build.split(".")) if build else (),
    )


def compare(left: Version, right: Version) -> int:
    left_core = (left.major, left.minor, left.patch)
    right_core = (right.major, right.minor, right.patch)
    if left_core != right_core:
        return -1 if left_core < right_core else 1
    if not left.prerelease and not right.prerelease:
        return 0
    if not left.prerelease:
        return 1
    if not right.prerelease:
        return -1
    for left_id, right_id in zip(left.prerelease, right.prerelease):
        if left_id == right_id:
            continue
        left_numeric = left_id.isdigit()
        right_numeric = right_id.isdigit()
        if left_numeric and right_numeric:
            return -1 if int(left_id) < int(right_id) else 1
        if left_numeric != right_numeric:
            return -1 if left_numeric else 1
        return -1 if left_id < right_id else 1
    if len(left.prerelease) == len(right.prerelease):
        return 0
    return -1 if len(left.prerelease) < len(right.prerelease) else 1


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], text=True, stderr=subprocess.STDOUT
    ).strip()


def select(repo: Path) -> dict[str, str]:
    raw_current = (repo / "VERSION").read_text(encoding="utf-8").strip()
    current = parse_version(raw_current)
    if current is None:
        raise RuntimeError(f"VERSION is not unambiguous SemVer: {raw_current!r}")
    current_commit = git(repo, "rev-parse", "HEAD^{commit}")
    print(
        f"SEMVER_CURRENT version={current.normalized} commit={current_commit}",
        file=sys.stderr,
    )

    semantic: list[Candidate] = []
    raw_tags = git(repo, "tag", "--merged", "HEAD", "--list")
    for tag in sorted(filter(None, raw_tags.splitlines())):
        version = parse_version(tag)
        if version is None:
            continue
        commit = git(repo, "rev-parse", f"{tag}^{{commit}}")
        candidate = Candidate(tag, version, commit)
        semantic.append(candidate)
        disposition = "exclude-current" if compare(version, current) == 0 else "candidate"
        print(
            f"SEMVER_REACHABLE tag={tag} version={version.normalized} "
            f"commit={commit} disposition={disposition}",
            file=sys.stderr,
        )

    lower = [candidate for candidate in semantic if compare(candidate.version, current) < 0]
    if not lower:
        raise RuntimeError(
            f"no reachable semantic tag is lower than VERSION {current.normalized}"
        )

    best = lower[0]
    for candidate in lower[1:]:
        if compare(candidate.version, best.version) > 0:
            best = candidate
    tied = [candidate for candidate in lower if compare(candidate.version, best.version) == 0]
    if len(tied) != 1:
        identities = ", ".join(
            f"{candidate.tag}@{candidate.commit}" for candidate in tied
        )
        raise RuntimeError(
            f"ambiguous baseline at SemVer precedence {best.version.normalized}: {identities}"
        )

    print(
        f"SEMVER_BASELINE tag={best.tag} version={best.version.normalized} "
        f"commit={best.commit}",
        file=sys.stderr,
    )
    return {
        "tag": best.tag,
        "version": best.version.normalized,
        "commit": best.commit,
        "current_version": current.normalized,
        "current_commit": current_commit,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        print(json.dumps(select(args.repo.resolve()), sort_keys=True))
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"SEMVER_BASELINE_ERROR {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
