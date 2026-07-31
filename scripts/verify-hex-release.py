#!/usr/bin/env python3
"""Fail-closed public Hex release verification."""

import argparse
import json
import re
import sys
import urllib.error
import urllib.request

PACKAGE = "atomvm_cbor"
APP = "avm_cbor"
ORGANIZATION = "ateljevagabond"
API = f"https://hex.pm/api/packages/{PACKAGE}"


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return 404, None
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("state", choices=["absent", "published"])
    parser.add_argument("--version", required=True)
    parser.add_argument("--checksum")
    args = parser.parse_args()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", args.version):
        raise SystemExit("--version must be a stable SemVer")
    version = args.version

    if args.state == "absent":
        release_status, _release = fetch(f"{API}/releases/{version}")
        if release_status != 404:
            raise SystemExit(f"atomvm_cbor {version} already exists on public Hex")
        print("HEX_RELEASE_ABSENT")
        return

    status, package = fetch(API)
    if status != 200:
        raise SystemExit("published package is not visible through the public Hex API")
    if package.get("repository") != "hexpm":
        raise SystemExit("package is not in the global public hexpm repository")
    owners = {owner.get("username") for owner in package.get("owners", [])}
    if ORGANIZATION not in owners:
        raise SystemExit("public Hex API does not show the expected organization owner")

    release_status, release = fetch(f"{API}/releases/{version}")
    if release_status != 200:
        raise SystemExit(f"release {version} is not visible through the public Hex API")
    if release.get("version") != version or release.get("meta", {}).get("app") != APP:
        raise SystemExit("published release identity does not match app/version")
    if not release.get("has_docs"):
        raise SystemExit(f"HexDocs is not published for {version}")
    if args.checksum and release.get("checksum") != args.checksum:
        raise SystemExit("published Hex checksum differs from the locally built package")

    docs = release.get("docs_html_url")
    if not docs:
        raise SystemExit("Hex API did not return a documentation URL")
    try:
        with urllib.request.urlopen(docs, timeout=30) as response:
            if response.status != 200:
                raise SystemExit("HexDocs did not resolve successfully")
    except urllib.error.HTTPError as error:
        raise SystemExit(f"HexDocs request failed: {error.code}") from error
    print("HEX_RELEASE_VERIFIED")


if __name__ == "__main__":
    try:
        main()
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"Hex verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
