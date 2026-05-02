#!/usr/bin/env bash
# pack-context.sh
# Packs source files for full-audit mode using repomix (preferred) or
# a simple file concatenation fallback if repomix is not available.
# Output: .claude/vibeaudit/packed.xml
# Usage: bash scripts/pack-context.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"
OUTPUT_DIR="${ROOT}/.claude/vibeaudit"
OUTPUT_FILE="${OUTPUT_DIR}/packed.xml"

mkdir -p "$OUTPUT_DIR"

echo "Packing source context for full-audit mode..."
echo "Output: $OUTPUT_FILE"

# --- Attempt to use repomix (preferred — tree-sitter compression, ~70% token reduction) ---
if command -v repomix &>/dev/null || bunx repomix --version &>/dev/null 2>&1; then
  echo "Using repomix for compressed packing..."

  bunx repomix \
    --include "src/**,app/**,server/**,lib/**,utils/**,api/**,pages/**,components/**,hooks/**,actions/**" \
    --ignore "**/*.test.*,**/*.spec.*,node_modules,dist,.next,build,coverage,.turbo,**/__tests__/**" \
    --compress \
    --output "$OUTPUT_FILE"

  echo "Repomix pack complete."
  echo "Output size: $(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes"
  exit 0
fi

# --- Fallback: simple file concatenation ---
echo "repomix not available — using file concatenation fallback."
echo "Install repomix for ~70% token reduction: bunx repomix"
echo ""

INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs)$"
EXCLUDE_PATTERN="(node_modules|\.git|dist|\.next|build|coverage|\.turbo)/"
EXCLUDE_TEST="\.(test|spec)\.(ts|tsx|js|jsx)$|/__tests__/"

INCLUDE_DIRS="src app server lib utils api pages components hooks actions"

# Build file list from relevant directories only
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

for dir in $INCLUDE_DIRS; do
  if [[ -d "${ROOT}/${dir}" ]]; then
    find "${ROOT}/${dir}" -type f \
      | grep -E "$INCLUDE_EXT" \
      | grep -Ev "$EXCLUDE_PATTERN" \
      | grep -Ev "$EXCLUDE_TEST" \
      >> "$TMPFILE" || true
  fi
done

FILE_COUNT=$(wc -l < "$TMPFILE" | tr -d ' ')
echo "Files to pack: $FILE_COUNT"

# Write XML envelope
cat > "$OUTPUT_FILE" <<'XMLHEADER'
<?xml version="1.0" encoding="UTF-8"?>
<repository>
  <summary>vibeAudit full-audit packed context (fallback concatenation)</summary>
  <files>
XMLHEADER

while IFS= read -r filepath; do
  [[ -z "$filepath" ]] || [[ ! -f "$filepath" ]] && continue
  rel="${filepath#${ROOT}/}"

  # XML-encode the file path (minimal: escape &, <, >)
  rel_xml="${rel//&/&amp;}"
  rel_xml="${rel_xml//</&lt;}"
  rel_xml="${rel_xml//>/&gt;}"

  {
    echo "    <file path=\"${rel_xml}\">"
    echo "      <![CDATA["
    cat "$filepath"
    echo "      ]]>"
    echo "    </file>"
  } >> "$OUTPUT_FILE"

done < "$TMPFILE"

cat >> "$OUTPUT_FILE" <<'XMLFOOTER'
  </files>
</repository>
XMLFOOTER

echo "Fallback pack complete."
echo "Output size: $(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes"
echo ""
echo "Note: install bunx repomix for compressed output with ~70% token reduction."
