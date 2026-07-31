#!/usr/bin/env python3
"""Generate docs/api.md from src/avm_cbor.erl.

Dependency-free public API documentation generator.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "avm_cbor.erl"
OUT = ROOT / "docs" / "api.md"

DESCRIPTIONS = {
    "decode/1": ("Decode one CBOR item using default options.", "Reads one complete CBOR value and returns the decoded value plus trailing bytes.", "It is not a strict whole-binary decoder; use decode_all/1 for that."),
    "decode/2": ("Decode one CBOR item using explicit options.", "Applies caller-provided limits and feature flags while decoding one item.", "It does not silently ignore invalid options."),
    "decode_start/2": ("Start a pull-based decode with explicit options.", "Returns an opaque immutable continuation without performing parser work.", "It is not a streaming-input API; the complete binary must already exist."),
    "decode_continue/2": ("Advance a continuation by a positive work budget.", "Returns done, more, or a controlled decode error after bounded parser transitions.", "It does not sleep, yield, or schedule the next call for the caller."),
    "decode_all/1": ("Decode a complete CBOR sequence using default options.", "Consumes all CBOR items and succeeds only when no trailing data remains.", "It is not meant for incomplete stream buffers; use decode_sequence/1 for that."),
    "decode_all/2": ("Decode a complete CBOR sequence using explicit options.", "Consumes all CBOR items while applying caller-provided limits and feature flags.", "It does not accept malformed or incomplete trailing data."),
    "decode_sequence/1": ("Decode as many complete CBOR items as possible using default options.", "Returns complete items and keeps a truncated final item as Rest.", "It is not a whole-input validation helper; use decode_all/1 for that."),
    "decode_sequence/2": ("Decode as many complete CBOR items as possible using explicit options.", "Like decode_sequence/1, but applies caller-provided limits and feature flags.", "It does not hide malformed data; malformed items still return errors."),
    "encode/1": ("Encode one supported Erlang value using default options.", "Produces definite-length CBOR for the documented public term representation.", "It does not enable preferred or deterministic encoding unless requested with encode/2."),
    "encode/2": ("Encode one supported Erlang value using explicit options.", "Supports preferred and deterministic serialization while enforcing caller-provided limits.", "It does not support arbitrary Erlang terms outside the documented representation."),
    "partial_decode/1": ("Validate and measure one CBOR item without eagerly constructing nested terms.", "Returns an opaque descriptor and trailing bytes using constrained partial-path defaults.", "The descriptor layout is private; use the partial_* accessors."),
    "partial_decode/2": ("Partially decode one CBOR item using explicit options.", "Applies decode limits, deterministic/preferred checks, and the partial max_string_size limit.", "It does not bypass validation simply because nested terms are deferred."),
    "partial_value_bytes/1": ("Return the complete encoded bytes represented by a partial descriptor.", "Returns the validated item as a sub-binary.", "It does not return only the child contents; use partial_contents/1 for that."),
    "partial_deep_decode/1": ("Materialize the value represented by a partial descriptor.", "Fully decodes the validated item only when the caller needs it.", "It does not accept forged or malformed descriptors."),
    "partial_skip/1": ("Discard a validated partial descriptor.", "Returns ok after validating that the value is a descriptor.", "It does not scan or materialize the represented value again."),
    "partial_type/1": ("Return the CBOR category represented by a partial descriptor.", "Reports unsigned, negative, bytes, text, array, map, tag, float, or simple.", "It does not return an Erlang runtime type."),
    "partial_count/1": ("Return an array item count or map pair count.", "Returns undefined for descriptor types without a count.", "It does not count nested descendants."),
    "partial_tag/1": ("Return the semantic tag number from a tag descriptor.", "Returns undefined for non-tag descriptors.", "It does not interpret tag semantics."),
    "partial_size/1": ("Return the content size of a byte or text string descriptor.", "Reports the content byte length and returns undefined for other descriptor types.", "It does not report the complete encoded item length."),
    "partial_offset/1": ("Return the descriptor item offset.", "Reports the start offset recorded for the represented item.", "It does not return a child index."),
    "partial_length/1": ("Return the complete encoded length of a descriptor item.", "Includes the CBOR header and any break marker.", "It does not return only string content length."),
    "partial_contents/1": ("Return encoded child bytes for an array, map, or tag.", "The returned binary can be walked with repeated partial_decode calls.", "It does not deep-decode the children."),
    "get/2": ("Look up a key in a decoded CBOR map.", "Searches the {map, Pairs} representation and returns {ok, Value} when present.", "It is not an Erlang map helper; decoded CBOR maps are represented as pair lists."),
    "get/3": ("Look up a key in a decoded CBOR map with a default.", "Returns the value when present, otherwise returns the supplied default.", "It does not distinguish a missing key from a present value equal to the default."),
    "require/2": ("Require a key in a decoded CBOR map.", "Returns a structured missing-key error when the key is absent.", "It does not validate the value type; use as_text/1, as_int/1, or related helpers."),
    "as_text/1": ("Extract a decoded CBOR text string.", "Accepts {text, Bin} and returns the UTF-8 binary.", "It does not accept arbitrary binaries; use as_bytes/1 for byte strings."),
    "as_bytes/1": ("Extract a decoded CBOR byte string.", "Accepts a binary byte string and returns it unchanged.", "It does not accept {text, Bin}; text and byte strings are distinct."),
    "as_int/1": ("Extract a decoded CBOR integer.", "Accepts Erlang integers returned by the decoder.", "It does not coerce floats, strings, or binaries into integers."),
    "as_bool/1": ("Extract a decoded CBOR boolean.", "Accepts only true or false.", "It does not treat other values as truthy or falsey."),
    "ble_options/0": ("Return strict options for small BLE-oriented payloads.", "Provides conservative depth, item, byte, and string limits with floats, tags, and indefinite-length items disabled.", "It is not a Bluetooth transport implementation or a performance benchmark."),
}


def exports(source: str) -> list[str]:
    match = re.search(r"-export\(\[(.*?)\]\)\.", source, re.S)
    if not match:
        raise SystemExit("could not find -export block")
    return re.findall(r"([a-zA-Z0-9_]+/\d+)", match.group(1))


def specs(source: str, public: list[str]) -> dict[str, str]:
    found = {}
    remaining = list(public)
    pattern = r"-spec\s+([a-zA-Z0-9_]+)\((.*?)\)\s*->\s*(.*?)\."
    for match in re.finditer(pattern, source, re.S):
        name, args, ret = match.groups()
        key = next((item for item in remaining if item.startswith(name + "/")), None)
        if key is None:
            continue
        remaining.remove(key)
        args = re.sub(r"\s+", " ", args.strip())
        ret = re.sub(r"\s+", " ", ret.strip())
        found[key] = f"{name}({args}) -> {ret}"
    return found


def render(public: list[str], spec_map: dict[str, str]) -> str:
    out = [
        "# API Reference",
        "",
        "Generated from `src/avm_cbor.erl` by `scripts/gen-api-docs.py`.",
        "",
        "Do not edit this file by hand. Run:",
        "",
        "```bash",
        "python3 scripts/gen-api-docs.py",
        "```",
        "",
        "## Summary",
        "",
        "| Function | Purpose |",
        "|---|---|",
    ]
    for key in public:
        summary = DESCRIPTIONS.get(key, ("TODO document this function.", "", ""))[0]
        out.append(f"| `{key}` | {summary} |")

    out.extend(["", "## Functions"])
    for key in public:
        summary, what, what_not = DESCRIPTIONS.get(key, ("TODO document this function.", "TODO", "TODO"))
        out.extend([
            "",
            f"### `{key}`",
            "",
            summary,
            "",
            "**Spec**",
            "",
            "```erlang",
            spec_map.get(key, "TODO missing -spec"),
            "```",
            "",
            "**What it does**",
            "",
            what,
            "",
            "**What it is not**",
            "",
            what_not,
        ])
    out.append("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if docs/api.md is not up to date")
    args = parser.parse_args()

    source = SRC.read_text(encoding="utf-8")
    public = exports(source)
    generated = render(public, specs(source, public))

    if args.check:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != generated:
            print("docs/api.md is not up to date. Run: python3 scripts/gen-api-docs.py", file=sys.stderr)
            return 1
        return 0

    OUT.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
