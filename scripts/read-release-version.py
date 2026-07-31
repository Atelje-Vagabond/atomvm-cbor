#!/usr/bin/env python3
"""Read one stable SemVer from VERSION, rejecting ambiguous input."""

import argparse
import re
from pathlib import Path


STABLE_SEMVER = re.compile(
    rb"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="VERSION")
    args = parser.parse_args()

    raw = Path(args.path).read_bytes()
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    if not STABLE_SEMVER.fullmatch(raw):
        raise SystemExit("VERSION must contain exactly one stable SemVer line")
    print(raw.decode("ascii"))


if __name__ == "__main__":
    main()
