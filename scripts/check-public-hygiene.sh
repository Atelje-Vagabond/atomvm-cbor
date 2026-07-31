#!/usr/bin/env bash
set -euo pipefail

if find . -path ./.git -prune -o -type f \( \
    -path '*/.agent/*' -o -path '*/.opencode/*' -o \
    -name AGENTS.md -o -name CLAUDE.md -o -name GEMINI.md \
\) -print | grep -q .; then
    echo "forbidden non-public path found" >&2
    exit 1
fi

mapfile -d '' files < <(git ls-files --cached --others --exclude-standard -z)
existing=()
for file in "${files[@]}"; do
    if [ -f "${file}" ] && [ "${file}" != scripts/check-public-hygiene.sh ] && [ "${file}" != scripts/check-hex-package.sh ]; then
        existing+=("${file}")
    fi
done
if [ "${#existing[@]}" -gt 0 ] && grep -InE \
    'atomvm-cbor-internal|runs-on:[[:space:]]*$|runner[_ -]?group|hw-test|/dev/tty|USB serial|ACTIVE_TASK|NEXT_ACTION|private prompt' \
    "${existing[@]}"; then
    echo "forbidden internal or device-specific marker found" >&2
    exit 1
fi

echo "PUBLIC_HYGIENE_OK"
