#!/usr/bin/env bash
# auto-update.sh
# Pulls the latest vibeAudit plugin code before an audit runs.
# Resolves its own install location so it works regardless of where the plugin is installed.
# Usage: bash path/to/vibeAudit/scripts/auto-update.sh

set -euo pipefail

# Resolve the plugin root (one level up from scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Bail if the plugin directory is not a git repo (e.g. manual copy install)
if [[ ! -d "${PLUGIN_DIR}/.git" ]]; then
  echo "[vibeAudit] Plugin directory is not a git repo — skipping auto-update."
  exit 0
fi

echo "[vibeAudit] Checking for updates..."

cd "$PLUGIN_DIR"

# Fetch latest from remote
if ! git fetch --quiet origin 2>/dev/null; then
  echo "[vibeAudit] Could not reach remote — running with current version."
  exit 0
fi

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "@{upstream}" 2>/dev/null || echo "$LOCAL")

if [[ "$LOCAL" == "$REMOTE" ]]; then
  echo "[vibeAudit] Already up to date."
else
  # Check for local uncommitted changes that would block a pull
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "[vibeAudit] Local changes detected in plugin directory — skipping update to avoid conflicts."
    exit 0
  fi

  if git merge-fast-forward "$REMOTE" 2>/dev/null || git pull --ff-only --quiet origin 2>/dev/null; then
    NEW=$(git rev-parse --short HEAD)
    echo "[vibeAudit] Updated to ${NEW}."
  else
    echo "[vibeAudit] Update available but fast-forward not possible — running with current version."
  fi
fi
