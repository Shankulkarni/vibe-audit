#!/usr/bin/env bash
# setup.sh
# One-time setup for vibeAudit in the current project.
# Creates the .claude/vibeaudit/ cache directory and initializes empty state files.
# Makes all scripts in the vibeAudit plugin's scripts/ directory executable.
# Usage: bash path/to/vibeAudit/scripts/setup.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"
CACHE_DIR="${ROOT}/.claude/vibeaudit"

# Resolve the directory where this script lives (the plugin's scripts/ dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== vibeAudit Setup ==="
echo "Project root: $ROOT"
echo ""

# --- Create cache directory ---
echo "Creating cache directory: $CACHE_DIR"
mkdir -p "$CACHE_DIR"

# --- Initialize empty state files if they don't already exist ---

if [[ ! -f "${CACHE_DIR}/state.json" ]]; then
  echo "Initializing state.json..."
  cat > "${CACHE_DIR}/state.json" <<'EOF'
{
  "lastAuditCommit": "unknown",
  "auditedAt": null,
  "stackDetected": [],
  "summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "info": 0
  }
}
EOF
else
  echo "state.json already exists — skipping."
fi

if [[ ! -f "${CACHE_DIR}/findings-cache.json" ]]; then
  echo "Initializing findings-cache.json..."
  echo "{}" > "${CACHE_DIR}/findings-cache.json"
else
  echo "findings-cache.json already exists — skipping."
fi

if [[ ! -f "${CACHE_DIR}/index.json" ]]; then
  echo "Initializing index.json..."
  cat > "${CACHE_DIR}/index.json" <<'EOF'
{
  "gitCommit": "unknown",
  "generatedAt": null,
  "files": {}
}
EOF
else
  echo "index.json already exists — skipping."
fi

# --- Make all plugin scripts executable ---
echo ""
echo "Making scripts executable..."
chmod +x "${SCRIPT_DIR}/detect-stack.sh"
chmod +x "${SCRIPT_DIR}/quick-scan.sh"
chmod +x "${SCRIPT_DIR}/find-secrets.sh"
chmod +x "${SCRIPT_DIR}/build-index.sh"
chmod +x "${SCRIPT_DIR}/cache-check.sh"
chmod +x "${SCRIPT_DIR}/cache-update.sh"
chmod +x "${SCRIPT_DIR}/pack-context.sh"
chmod +x "${SCRIPT_DIR}/auto-update.sh"
chmod +x "${SCRIPT_DIR}/setup.sh"
chmod +x "${SCRIPT_DIR}/teardown.sh"
echo "All scripts are now executable."

# --- Print next steps ---
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run your first audit:   /audit"
echo "  2. Quick scan only:        /audit:quick"
echo "  3. Full deep audit:        /audit:full"
echo "  4. Security only:          /audit:security"
echo "  5. Generate report:        /audit:report"
echo ""
echo "Cache files created in: $CACHE_DIR"
echo "  state.json          — tracks last audit commit and summary"
echo "  findings-cache.json — per-file cached findings"
echo "  index.json          — repo symbol index (populated by build-index.sh)"
echo ""
echo "To clean up all cache files: bash ${SCRIPT_DIR}/teardown.sh"
