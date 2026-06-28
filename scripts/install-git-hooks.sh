#!/bin/sh
set -eu

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required."
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
  echo "ERROR: run this script inside a Git checkout."
  exit 1
fi

cd "$repo_root"

if [ ! -f scripts/local-pre-push-check.sh ]; then
  echo "ERROR: scripts/local-pre-push-check.sh is missing."
  exit 1
fi

mkdir -p .git/hooks
cat > .git/hooks/pre-push <<'HOOK'
#!/bin/sh
exec sh scripts/local-pre-push-check.sh "$@"
HOOK
chmod +x .git/hooks/pre-push
chmod +x scripts/local-pre-push-check.sh

echo "Local pre-push hook installed."
echo "Normal pushes run standard release checks."
echo "release/* branch pushes and v* tag pushes also run ESP-IDF validation."
