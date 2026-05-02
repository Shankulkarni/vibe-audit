#!/usr/bin/env bash
# cache-check.sh
# Determines which files need re-auditing based on git diff and content hash cache.
# Output: list of file paths (relative to project root) that need auditing.
# Usage: bash scripts/cache-check.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"
STATE_FILE="${ROOT}/.claude/vibeaudit/state.json"
CACHE_FILE="${ROOT}/.claude/vibeaudit/findings-cache.json"

EXCLUDE_PATTERN="(node_modules|\.git|dist|\.next|build|coverage|\.turbo)/"
INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs)$"

# --- Helper: compute a simple content hash (sha256 if available, else md5) ---
file_hash() {
  local f="$1"
  if command -v sha256sum &>/dev/null; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    md5 -q "$f" 2>/dev/null || md5sum "$f" | awk '{print $1}'
  fi
}

# --- Case 1: No state.json — first run, audit everything ---
if [[ ! -f "$STATE_FILE" ]]; then
  echo "# No state.json found — queuing all source files for audit" >&2

  find "$ROOT" -type f \
    | grep -E "$INCLUDE_EXT" \
    | grep -Ev "$EXCLUDE_PATTERN" \
    | sed "s|${ROOT}/||" \
    | sort

  exit 0
fi

# --- Read last audit commit from state.json ---
# Parse without jq: extract "lastAuditCommit" value
LAST_COMMIT=$(grep -o '"lastAuditCommit"\s*:\s*"[^"]*"' "$STATE_FILE" \
  | sed 's/.*:\s*"\(.*\)"/\1/' \
  || echo "")

if [[ -z "$LAST_COMMIT" ]] || [[ "$LAST_COMMIT" == "unknown" ]]; then
  echo "# lastAuditCommit not found or unknown — queuing all source files" >&2

  find "$ROOT" -type f \
    | grep -E "$INCLUDE_EXT" \
    | grep -Ev "$EXCLUDE_PATTERN" \
    | sed "s|${ROOT}/||" \
    | sort

  exit 0
fi

# --- Case 2: Git diff to find changed files since last audit ---
CHANGED_FILES=""
if command -v git &>/dev/null && git -C "$ROOT" rev-parse HEAD &>/dev/null 2>&1; then
  # Get files changed since last audit commit (handles missing commit gracefully)
  CHANGED_FILES=$(git -C "$ROOT" diff "${LAST_COMMIT}...HEAD" --name-only 2>/dev/null \
    | grep -E "$INCLUDE_EXT" \
    | grep -Ev "$EXCLUDE_PATTERN" \
    || true)
else
  echo "# git not available — queuing all source files" >&2

  find "$ROOT" -type f \
    | grep -E "$INCLUDE_EXT" \
    | grep -Ev "$EXCLUDE_PATTERN" \
    | sed "s|${ROOT}/||" \
    | sort

  exit 0
fi

# Build a set of changed files for quick lookup
declare -A changed_set
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  changed_set["$f"]=1
done <<< "$CHANGED_FILES"

# --- Case 3: For unchanged files, check hash cache ---
# If a file has no cached findings or its hash changed, queue it too.

OUTPUT_FILES=()

# First, add all changed files that actually exist
for f in "${!changed_set[@]}"; do
  if [[ -f "${ROOT}/${f}" ]]; then
    OUTPUT_FILES+=("$f")
  fi
done

# Then, check all source files not in the changed set against the hash cache
while IFS= read -r filepath; do
  rel="${filepath#${ROOT}/}"

  # Skip if already in changed set
  if [[ -n "${changed_set["$rel"]+_}" ]]; then
    continue
  fi

  # If no cache file, queue everything
  if [[ ! -f "$CACHE_FILE" ]]; then
    OUTPUT_FILES+=("$rel")
    continue
  fi

  # Check if this file has a cached entry
  if ! grep -q "\"${rel}\"" "$CACHE_FILE" 2>/dev/null; then
    # No cached findings for this file
    OUTPUT_FILES+=("$rel")
    continue
  fi

  # Extract cached hash for this file (simple grep approach)
  cached_hash=$(grep -A 2 "\"${rel}\"" "$CACHE_FILE" \
    | grep '"hash"' \
    | sed 's/.*"hash"\s*:\s*"\([^"]*\)".*/\1/' \
    | head -1 \
    || echo "")

  if [[ -z "$cached_hash" ]]; then
    OUTPUT_FILES+=("$rel")
    continue
  fi

  # Compute current file hash
  current_hash=$(file_hash "$filepath")

  # Queue if hash mismatch
  if [[ "sha256:${current_hash}" != "$cached_hash" ]] && [[ "$current_hash" != "$cached_hash" ]]; then
    OUTPUT_FILES+=("$rel")
  fi

done < <(find "$ROOT" -type f \
  | grep -E "$INCLUDE_EXT" \
  | grep -Ev "$EXCLUDE_PATTERN" \
  | sort)

# --- Output the final list ---
echo "# Files requiring audit: ${#OUTPUT_FILES[@]}" >&2

for f in "${OUTPUT_FILES[@]}"; do
  echo "$f"
done | sort -u
