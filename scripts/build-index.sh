#!/usr/bin/env bash
# build-index.sh
# Fallback repo indexer — zero binary dependencies, uses grep/find/sed only.
#
# Prefer agent-toolkit when available (git-incremental, accurate re-export tracking):
#   bunx @harryy/agent-toolkit repo intel
#   → writes .agents/intel/summary.md and .agents/intel/repo.json
#
# This script runs when agent-toolkit is not available. It produces:
#   .claude/vibeaudit/index.json with gitCommit, files map (imports, exports, lines)
#
# Usage: bash scripts/build-index.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"
OUTPUT_DIR="${ROOT}/.claude/vibeaudit"
OUTPUT_FILE="${OUTPUT_DIR}/index.json"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# --- Git commit hash ---
GIT_COMMIT="unknown"
if command -v git &>/dev/null && git -C "$ROOT" rev-parse HEAD &>/dev/null 2>&1; then
  GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
fi

echo "Building index for: $ROOT"
echo "Git commit: $GIT_COMMIT"

# --- Collect source files ---
# Scan .ts, .tsx, .js, .jsx files; exclude generated/vendored directories
EXCLUDE_PATTERN="(node_modules|\.git|dist|\.next|build|coverage|\.turbo)/"
INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs)$"

# Build index JSON incrementally
# We construct JSON manually to avoid requiring jq

INDEX_JSON=""
FIRST_FILE=true

while IFS= read -r filepath; do
  # Relative path from project root (strip leading ROOT + /)
  rel="${filepath#${ROOT}/}"

  # Line count
  line_count=0
  if [[ -f "$filepath" ]]; then
    line_count=$(wc -l < "$filepath" | tr -d ' ')
  fi

  # Extract imports: lines matching `import ... from '...'` or `import '...'`
  # Output as JSON array of quoted strings
  imports_raw=$(grep -E "^\s*import\s+.*\s+from\s+['\"]|^\s*import\s+['\"]" "$filepath" 2>/dev/null \
    | sed -E "s/.*from\s+['\"]([^'\"]+)['\"].*/\1/;s/.*import\s+['\"]([^'\"]+)['\"].*/\1/" \
    | sort -u \
    || true)

  imports_json="["
  first_import=true
  while IFS= read -r imp; do
    [[ -z "$imp" ]] && continue
    # Escape double quotes in the value
    imp_escaped="${imp//\"/\\\"}"
    if [[ "$first_import" == true ]]; then
      imports_json+="\"${imp_escaped}\""
      first_import=false
    else
      imports_json+=",\"${imp_escaped}\""
    fi
  done <<< "$imports_raw"
  imports_json+="]"

  # Extract exports: lines starting with `export`
  exports_raw=$(grep -E "^export\s+(default\s+)?(function|class|const|let|var|type|enum|async)" "$filepath" 2>/dev/null \
    | sed -E "s/^export\s+(default\s+)?(async\s+)?(function|class|const|let|var|type|enum)\s+([A-Za-z0-9_]+).*/\4/" \
    | grep -E "^[A-Za-z]" \
    | sort -u \
    || true)

  exports_json="["
  first_export=true
  while IFS= read -r exp; do
    [[ -z "$exp" ]] && continue
    exp_escaped="${exp//\"/\\\"}"
    if [[ "$first_export" == true ]]; then
      exports_json+="\"${exp_escaped}\""
      first_export=false
    else
      exports_json+=",\"${exp_escaped}\""
    fi
  done <<< "$exports_raw"
  exports_json+="]"

  # Build file entry
  rel_escaped="${rel//\"/\\\"}"
  file_entry="\"${rel_escaped}\":{\"imports\":${imports_json},\"exports\":${exports_json},\"lines\":${line_count}}"

  if [[ "$FIRST_FILE" == true ]]; then
    INDEX_JSON+="${file_entry}"
    FIRST_FILE=false
  else
    INDEX_JSON+=",${file_entry}"
  fi

done < <(find "$ROOT" -type f \
  | grep -E "$INCLUDE_EXT" \
  | grep -Ev "$EXCLUDE_PATTERN" \
  | sort)

# Write final JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "gitCommit": "${GIT_COMMIT}",
  "generatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "files": {${INDEX_JSON}}
}
EOF

FILE_COUNT=$(grep -o '"lines"' "$OUTPUT_FILE" | wc -l | tr -d ' ')
echo "Index written to: $OUTPUT_FILE"
echo "Files indexed: $FILE_COUNT"
