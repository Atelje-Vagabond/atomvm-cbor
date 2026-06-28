#!/bin/sh
set -eu

version="${AVM_CBOR_VERSION:-v$(cat VERSION)}"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
needs_full=false

case "$branch" in
  release/*) needs_full=true ;;
esac

while read local_ref local_sha remote_ref remote_sha; do
  case "$local_ref" in refs/tags/v*) needs_full=true ;; esac
  case "$remote_ref" in refs/heads/release/*|refs/tags/v*) needs_full=true ;; esac
done

echo "AtomVM CBOR pre-push checks"
echo "Branch: $branch"
echo "Version: $version"

sh scripts/release-check.sh "$version"

if [ "${AVM_CBOR_WITH_ESP_IDF:-}" = "1" ]; then
  needs_full=true
fi

if [ "$needs_full" = true ]; then
  echo "Release branch or tag push detected; running ESP-IDF validation."
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: ESP-IDF validation needs a Docker-compatible container runtime."
    echo "Examples: Docker Desktop, OrbStack, Colima, Podman with Docker-compatible CLI, or native Docker Engine."
    exit 1
  fi
  sh scripts/release-check.sh "$version" --with-esp-idf
else
  echo "Skipping ESP-IDF validation for this non-release push."
  echo "Run before release: scripts/release-check.sh $version --with-esp-idf"
fi

echo "Pre-push checks passed."
