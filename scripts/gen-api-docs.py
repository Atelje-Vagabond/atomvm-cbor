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
    "sequence_fold/3": ("Fold complete CBOR sequence items without building a result list.", "Calls Fun(Item, Acc) for each complete item; {cont, NewAcc} continues, while {halt, Result} returns the result and unconsumed Rest.", "It is not a streaming-input API; a truncated final item is returned unchanged as Rest, and callback exceptions are not caught."),
    "encode/1": ("Encode one supported Erlang value using default options.", "Produces definite-length CBOR for the documented public term representation.", "It does not enable preferred or deterministic encoding unless requested with encode/2."),
    "encode/2": ("Encode one supported Erlang value using explicit options.", "Supports preferred and deterministic serialization while enforcing caller-provided limits.", "It does not support arbitrary Erlang terms outside the documented representation."),
    "encode_with_size/1": ("Encode one value and return its exact byte size using default options.", "Returns {ok, Binary, Size}, where Size is measured from the binary produced by the single encode operation.", "It is not a separate sizing or preflight pass."),
    "encode_with_size/2": ("Encode one value and return its exact byte size using explicit options.", "Applies the same normalized options and limits as encode/2, then returns {ok, Binary, Size}.", "It does not estimate a size or encode the value twice."),
    "encode_sequence/1": ("Encode a list of values as an RFC 8742 CBOR sequence using default options.", "Encodes each list element as one CBOR data item and concatenates the item binaries while enforcing sequence limits.", "It does not encode the input list as a CBOR array."),
    "encode_sequence/2": ("Encode a list of values as an RFC 8742 CBOR sequence using explicit options.", "Applies the supplied encoding options to every item and enforces cumulative max_items and max_bytes limits.", "It does not accept a non-list or improper list as a sequence."),
    "validate_all/1": ("Validate exactly one complete CBOR item using default partial-decoding limits.", "Checks the entire item and returns ok only when no trailing bytes remain, without materializing its nested Erlang value.", "It is not a CBOR sequence validator; additional complete items are reported as trailing bytes."),
    "validate_all/2": ("Validate exactly one complete CBOR item using explicit options.", "Applies partial-decoding limits plus deterministic or preferred checks and rejects trailing bytes.", "It does not return the decoded value; use decode_all/2 when the materialized term is required."),
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
    "partial_map_fold/3": ("Fold a map descriptor as opaque key and value descriptors.", "Calls Fun(KeyDescriptor, ValueDescriptor, Acc) in CBOR map order; {cont, NewAcc} continues and {halt, Result} stops early.", "It does not materialize the map or catch callback exceptions."),
    "partial_array_fold/3": ("Fold an array descriptor as opaque element descriptors.", "Calls Fun(ElementDescriptor, Acc) in array order with the same continue and early-halt contract as partial_map_fold/3.", "It does not materialize the array or accept a non-array descriptor."),
    "partial_select/2": ("Select requested keys from a map descriptor in one pass.", "Returns {ok, Found, Missing}; found pairs retain CBOR map order, missing keys retain request order, and values remain descriptors.", "It does not accept duplicate requested keys or deep-decode selected values; the first matching map entry wins."),
    "partial_map_find/2": ("Find the first matching key in a map descriptor.", "Compares decoded keys exactly and returns the matching opaque value descriptor without decoding that value.", "It does not return a materialized value or search past the first match."),
    "partial_array_nth/2": ("Return an opaque array element descriptor by zero-based index.", "Traverses the array until the requested non-negative index and returns that element descriptor.", "It is not one-based and does not deep-decode the selected element."),
    "get/2": ("Look up a key in a decoded CBOR map.", "Searches the {map, Pairs} representation and returns {ok, Value} when present.", "It is not an Erlang map helper; decoded CBOR maps are represented as pair lists."),
    "get/3": ("Look up a key in a decoded CBOR map with a default.", "Returns the value when present, otherwise returns the supplied default.", "It does not distinguish a missing key from a present value equal to the default."),
    "require/2": ("Require a key in a decoded CBOR map.", "Returns a structured missing-key error when the key is absent.", "It does not validate the value type; use as_text/1, as_int/1, or related helpers."),
    "as_text/1": ("Extract a decoded CBOR text string.", "Accepts {text, Bin} and returns the UTF-8 binary.", "It does not accept arbitrary binaries; use as_bytes/1 for byte strings."),
    "as_bytes/1": ("Extract a decoded CBOR byte string.", "Accepts a binary byte string and returns it unchanged.", "It does not accept {text, Bin}; text and byte strings are distinct."),
    "as_int/1": ("Extract a decoded CBOR integer.", "Accepts Erlang integers returned by the decoder.", "It does not coerce floats, strings, or binaries into integers."),
    "as_bool/1": ("Extract a decoded CBOR boolean.", "Accepts only true or false.", "It does not treat other values as truthy or falsey."),
    "ble_options/0": ("Return strict options for small BLE-oriented payloads.", "Provides conservative depth, item, byte, and string limits with floats, tags, and indefinite-length items disabled.", "It is not a Bluetooth transport implementation or a performance benchmark."),
}

EXAMPLES = {
    "decode/1": '{ok, 42, <<>>} = avm_cbor:decode(<<16#18, 42>>).',
    "decode/2": '{ok, [1, 2], <<>>} = avm_cbor:decode(<<16#82, 1, 2>>, [{max_items, 3}]).',
    "decode_start/2": (
        '{ok, State} = avm_cbor:decode_start(<<16#82, 1, 2>>, []),\n'
        '{done, [1, 2], <<>>} = avm_cbor:decode_continue(State, 100).'
    ),
    "decode_continue/2": (
        '{ok, State} = avm_cbor:decode_start(<<16#82, 1, 2>>, []),\n'
        '{done, [1, 2], <<>>} = avm_cbor:decode_continue(State, 100).'
    ),
    "decode_all/1": '{ok, [1, 2]} = avm_cbor:decode_all(<<1, 2>>).',
    "decode_all/2": (
        '{ok, [1, 2]} = avm_cbor:decode_all(<<1, 2>>, [{max_items, 2}]).'
    ),
    "decode_sequence/1": (
        '{ok, [1], <<16#82, 2>>} = '
        'avm_cbor:decode_sequence(<<1, 16#82, 2>>).'
    ),
    "decode_sequence/2": (
        '{ok, [1, 2], <<>>} = '
        'avm_cbor:decode_sequence(<<1, 2>>, [{max_items, 2}]).'
    ),
    "sequence_fold/3": (
        'Sum = fun(Item, Acc) -> {cont, Item + Acc} end,\n'
        '{ok, 6, <<>>} = avm_cbor:sequence_fold(<<1, 2, 3>>, Sum, 0).'
    ),
    "encode/1": '{ok, <<16#82, 1, 2>>} = avm_cbor:encode([1, 2]).',
    "encode/2": (
        '{ok, <<23>>} = avm_cbor:encode(23, [{preferred, true}]).'
    ),
    "encode_with_size/1": (
        '{ok, <<16#82, 1, 2>>, 3} = avm_cbor:encode_with_size([1, 2]).'
    ),
    "encode_with_size/2": (
        '{ok, <<23>>, 1} = '
        'avm_cbor:encode_with_size(23, [{preferred, true}]).'
    ),
    "encode_sequence/1": (
        '{ok, <<1, 2, 3>>} = avm_cbor:encode_sequence([1, 2, 3]).'
    ),
    "encode_sequence/2": (
        '{ok, <<1, 2>>} = '
        'avm_cbor:encode_sequence([1, 2], [{max_items, 2}]).'
    ),
    "validate_all/1": 'ok = avm_cbor:validate_all(<<16#82, 1, 2>>).',
    "validate_all/2": (
        'ok = avm_cbor:validate_all(<<23>>, [{preferred, true}]).'
    ),
    "partial_decode/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        'array = avm_cbor:partial_type(Partial).'
    ),
    "partial_decode/2": (
        '{ok, Partial, <<>>} = '
        'avm_cbor:partial_decode(<<16#81, 1>>, [{max_depth, 2}]),\n'
        'array = avm_cbor:partial_type(Partial).'
    ),
    "partial_value_bytes/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '<<16#82, 1, 2>> = avm_cbor:partial_value_bytes(Partial).'
    ),
    "partial_deep_decode/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '{ok, [1, 2]} = avm_cbor:partial_deep_decode(Partial).'
    ),
    "partial_skip/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        'ok = avm_cbor:partial_skip(Partial).'
    ),
    "partial_type/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        'array = avm_cbor:partial_type(Partial).'
    ),
    "partial_count/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#A1, 1, 2>>),\n'
        '1 = avm_cbor:partial_count(Partial).'
    ),
    "partial_tag/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#C1, 1>>),\n'
        '1 = avm_cbor:partial_tag(Partial).'
    ),
    "partial_size/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#62, "ok">>),\n'
        '2 = avm_cbor:partial_size(Partial).'
    ),
    "partial_offset/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '0 = avm_cbor:partial_offset(Partial).'
    ),
    "partial_length/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '3 = avm_cbor:partial_length(Partial).'
    ),
    "partial_contents/1": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '{ok, <<1, 2>>} = avm_cbor:partial_contents(Partial).'
    ),
    "partial_map_fold/3": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#A1, 1, 2>>),\n'
        'Count = fun(_Key, _Value, Acc) -> {cont, Acc + 1} end,\n'
        '{ok, 1} = avm_cbor:partial_map_fold(Partial, Count, 0).'
    ),
    "partial_array_fold/3": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        'Sum = fun(Element, Acc) ->\n'
        '    {ok, Value} = avm_cbor:partial_deep_decode(Element),\n'
        '    {cont, Acc + Value}\n'
        'end,\n'
        '{ok, 3} = avm_cbor:partial_array_fold(Partial, Sum, 0).'
    ),
    "partial_select/2": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#A2, 1, 2, 3, 4>>),\n'
        '{ok, [{1, Value}], [9]} = avm_cbor:partial_select(Partial, [1, 9]),\n'
        '{ok, 2} = avm_cbor:partial_deep_decode(Value).'
    ),
    "partial_map_find/2": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#A1, 1, 2>>),\n'
        '{ok, Value} = avm_cbor:partial_map_find(Partial, 1),\n'
        '{ok, 2} = avm_cbor:partial_deep_decode(Value).'
    ),
    "partial_array_nth/2": (
        '{ok, Partial, <<>>} = avm_cbor:partial_decode(<<16#82, 1, 2>>),\n'
        '{ok, Second} = avm_cbor:partial_array_nth(Partial, 1),\n'
        '{ok, 2} = avm_cbor:partial_deep_decode(Second).'
    ),
    "get/2": (
        'Map = {map, [{{text, <<"id">>}, 7}]},\n'
        '{ok, 7} = avm_cbor:get({text, <<"id">>}, Map).'
    ),
    "get/3": (
        'Map = {map, []},\n'
        'unknown = avm_cbor:get({text, <<"id">>}, Map, unknown).'
    ),
    "require/2": (
        'Map = {map, [{{text, <<"id">>}, 7}]},\n'
        '{ok, 7} = avm_cbor:require({text, <<"id">>}, Map).'
    ),
    "as_text/1": '{ok, <<"hello">>} = avm_cbor:as_text({text, <<"hello">>}).',
    "as_bytes/1": '{ok, <<1, 2>>} = avm_cbor:as_bytes(<<1, 2>>).',
    "as_int/1": '{ok, 42} = avm_cbor:as_int(42).',
    "as_bool/1": '{ok, true} = avm_cbor:as_bool(true).',
    "ble_options/0": (
        'Options = avm_cbor:ble_options(),\n'
        '{max_depth, 8} = lists:keyfind(max_depth, 1, Options).'
    ),
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
    missing_descriptions = [key for key in public if key not in DESCRIPTIONS]
    placeholder_descriptions = [
        key
        for key in public
        if key in DESCRIPTIONS
        and any(not text.strip() or "TODO" in text.upper() for text in DESCRIPTIONS[key])
    ]
    missing_examples = [key for key in public if key not in EXAMPLES]
    placeholder_examples = [
        key
        for key in public
        if key in EXAMPLES
        and (not EXAMPLES[key].strip() or "TODO" in EXAMPLES[key].upper())
    ]
    missing_specs = [key for key in public if key not in spec_map]
    if (
        missing_descriptions
        or placeholder_descriptions
        or missing_examples
        or placeholder_examples
        or missing_specs
    ):
        raise SystemExit(
            "incomplete public API documentation: "
            f"missing descriptions={missing_descriptions}, "
            f"placeholder descriptions={placeholder_descriptions}, "
            f"missing examples={missing_examples}, "
            f"placeholder examples={placeholder_examples}, "
            f"missing specs={missing_specs}"
        )

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
        summary = DESCRIPTIONS[key][0]
        out.append(f"| `{key}` | {summary} |")

    out.extend(["", "## Functions"])
    for key in public:
        summary, what, what_not = DESCRIPTIONS[key]
        out.extend([
            "",
            f"### `{key}`",
            "",
            summary,
            "",
            "**Spec**",
            "",
            "```erlang",
            spec_map[key],
            "```",
            "",
            "**Example**",
            "",
            "```erlang",
            EXAMPLES[key],
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
