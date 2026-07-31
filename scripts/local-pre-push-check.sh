#!/bin/sh
set -eu

version="${AVM_CBOR_VERSION:-$(cat VERSION)}"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
needs_full=false

case "$branch" in
  release/*) needs_full=true ;;
esac

while read local_ref local_sha remote_ref remote_sha; do
  case "$local_ref" in refs/tags/[0-9]*) needs_full=true ;; esac
  case "$remote_ref" in refs/heads/release/*|refs/tags/[0-9]*) needs_full=true ;; esac
done

echo "AtomVM CBOR pre-push checks"
echo "Branch: $branch"
echo "Version: $version"

bash scripts/release-check.sh "$version"

if [ "$needs_full" = true ] || [ "${AVM_CBOR_WITH_ESP_IDF:-}" = "1" ]; then
  command -v docker >/dev/null 2>&1 || {
    echo "ERROR: ESP-IDF validation needs Docker." >&2
    exit 1
  }
  bash scripts/test-esp-idf.sh v5.4.3
  bash scripts/test-esp-idf.sh v5.5.2
fi

echo "Pre-push checks passed."
