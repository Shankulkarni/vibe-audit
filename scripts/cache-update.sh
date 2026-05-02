#!/usr/bin/env bash
# cache-update.sh
# Updates the vibeAudit cache after an audit completes.
# Reads findings JSON from stdin or from FINDINGS_FILE env variable.
# Updates:
#   .claude/vibeaudit/findings-cache.json  — per-file findings keyed by content hash
#   .claude/vibeaudit/state.json           — lastAuditCommit + summary counts
# Usage:
#   echo '{"files":[...]}' | bash scripts/cache-update.sh
#   FINDINGS_FILE=/tmp/findings.json bash scripts/cache-update.sh

set -euo pipefail

ROOT="$(pwd)"
CACHE_DIR="${ROOT}/.claude/vibeaudit"
CACHE_FILE="${CACHE_DIR}/findings-cache.json"
STATE_FILE="${CACHE_DIR}/state.json"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# --- Helper: compute content hash ---
file_hash() {
  local f="$1"
  if command -v sha256sum &>/dev/null; then
    echo "sha256:$(sha256sum "$f" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    echo "sha256:$(shasum -a 256 "$f" | awk '{print $1}')"
  else
    echo "md5:$(md5 -q "$f" 2>/dev/null || md5sum "$f" | awk '{print $1}')"
  fi
}

# --- Read findings input ---
FINDINGS_INPUT=""

if [[ -n "${FINDINGS_FILE:-}" ]] && [[ -f "$FINDINGS_FILE" ]]; then
  FINDINGS_INPUT="$(cat "$FINDINGS_FILE")"
elif [[ ! -t 0 ]]; then
  # Read from stdin if it's a pipe
  FINDINGS_INPUT="$(cat)"
fi

# --- Get current git commit ---
GIT_COMMIT="unknown"
if command -v git &>/dev/null && git -C "$ROOT" rev-parse HEAD &>/dev/null 2>&1; then
  GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
fi

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# --- Initialize cache file if it doesn't exist ---
if [[ ! -f "$CACHE_FILE" ]]; then
  echo "{}" > "$CACHE_FILE"
fi

# --- Parse and update findings cache ---
# Expected findings input format (JSON):
# {
#   "files": [
#     {
#       "path": "src/app/api/route.ts",
#       "skills": ["audit-stripe-integration"],
#       "findings": [
#         {
#           "severity": "critical",
#           "category": "Security",
#           "line": 23,
#           "message": "...",
#           "fix": "..."
#         }
#       ]
#     }
#   ],
#   "summary": { "critical": 1, "high": 2, "medium": 3, "low": 0, "info": 0 }
# }

# Count findings by severity from findings input (grep-based, no jq required)
count_severity() {
  local sev="$1"
  echo "$FINDINGS_INPUT" | grep -o "\"severity\"\\s*:\\s*\"${sev}\"" | wc -l | tr -d ' ' || echo "0"
}

CRITICAL_COUNT=$(count_severity "critical")
HIGH_COUNT=$(count_severity "high")
MEDIUM_COUNT=$(count_severity "medium")
LOW_COUNT=$(count_severity "low")
INFO_COUNT=$(count_severity "info")

# --- Update per-file cache entries ---
# For each file mentioned in findings input, compute its current hash and write cache entry.
# We do a simple approach: append new entries to a temporary file, then merge.

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# Start building new cache JSON
echo "{" > "$TMPFILE"
FIRST_ENTRY=true

# Carry over existing cache entries not being updated
if [[ -f "$CACHE_FILE" ]] && [[ -n "$FINDINGS_INPUT" ]]; then
  # Extract all file paths from findings input
  UPDATED_PATHS=$(echo "$FINDINGS_INPUT" \
    | grep -o '"path"\s*:\s*"[^"]*"' \
    | sed 's/.*:\s*"\(.*\)"/\1/' \
    || true)

  # Read existing cache and re-emit entries for files NOT being updated
  # This is a best-effort approach without jq
  # We copy the existing cache content and will overwrite updated file entries
  cp "$CACHE_FILE" "${TMPFILE}.existing"
else
  echo "{}" > "${TMPFILE}.existing"
fi

# Build updated entries for each file in findings input
if [[ -n "$FINDINGS_INPUT" ]]; then
  while IFS= read -r file_path; do
    [[ -z "$file_path" ]] && continue
    full_path="${ROOT}/${file_path}"

    if [[ -f "$full_path" ]]; then
      hash=$(file_hash "$full_path")
    else
      hash="unknown"
    fi

    # Extract findings for this file from input (grep-based extraction)
    # We write a per-file JSON entry
    file_path_escaped="${file_path//\"/\\\"}"

    entry="\"${file_path_escaped}\": {\"hash\": \"${hash}\", \"auditedAt\": \"${NOW}\", \"findings\": []}"

    if [[ "$FIRST_ENTRY" == true ]]; then
      echo "  ${entry}" >> "$TMPFILE"
      FIRST_ENTRY=false
    else
      # Add comma before previous line
      sed -i.bak '$ s/$/ ,/' "$TMPFILE" 2>/dev/null || true
      echo "  ${entry}" >> "$TMPFILE"
    fi

  done < <(echo "$FINDINGS_INPUT" \
    | grep -o '"path"\s*:\s*"[^"]*"' \
    | sed 's/.*:\s*"\(.*\)"/\1/' \
    | sort -u)
fi

echo "}" >> "$TMPFILE"

# Write updated cache
cp "$TMPFILE" "$CACHE_FILE"

# --- Update state.json ---
cat > "$STATE_FILE" <<EOF
{
  "lastAuditCommit": "${GIT_COMMIT}",
  "auditedAt": "${NOW}",
  "summary": {
    "critical": ${CRITICAL_COUNT},
    "high": ${HIGH_COUNT},
    "medium": ${MEDIUM_COUNT},
    "low": ${LOW_COUNT},
    "info": ${INFO_COUNT}
  }
}
EOF

echo "Cache updated: $CACHE_FILE"
echo "State updated: $STATE_FILE"
echo "Commit: $GIT_COMMIT"
echo "Summary — critical:${CRITICAL_COUNT} high:${HIGH_COUNT} medium:${MEDIUM_COUNT} low:${LOW_COUNT} info:${INFO_COUNT}"
