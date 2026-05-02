#!/usr/bin/env bash
# teardown.sh
# Removes the .claude/vibeaudit/ cache directory and all its contents.
# Does not remove the .claude/ directory itself in case other tools use it.
# Usage: bash path/to/vibeAudit/scripts/teardown.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"
CACHE_DIR="${ROOT}/.claude/vibeaudit"

echo "=== vibeAudit Teardown ==="
echo "Project root: $ROOT"
echo ""

if [[ ! -d "$CACHE_DIR" ]]; then
  echo "Nothing to remove: $CACHE_DIR does not exist."
  exit 0
fi

echo "Removing: $CACHE_DIR"
rm -rf "$CACHE_DIR"

echo ""
echo "Teardown complete. vibeAudit cache removed."
echo "Run setup.sh to reinitialize, or /audit to start fresh."
