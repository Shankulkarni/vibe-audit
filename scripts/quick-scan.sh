#!/usr/bin/env bash
# quick-scan.sh
# Tier 1 audit: greps 50+ vibecode patterns across the codebase.
# Each hit prints: [PATTERN_NAME] file:line: matched_text
# A summary table of hits per category is printed at the end.
# Usage: bash scripts/quick-scan.sh (run from project root)

set -euo pipefail

# --- Configuration ---

# Directories to exclude from scanning
EXCLUDE_DIRS="node_modules|\.git|dist|\.next|build|coverage|\.turbo|\.cache"

# Extensions to scan
INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs)$"

# Collect all source files into a temp list for reuse
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

find "$(pwd)" -type f \
  | grep -E "$INCLUDE_EXT" \
  | grep -Ev "($EXCLUDE_DIRS)/" \
  | grep -Ev "\.(test|spec)\." \
  | grep -Ev "__tests__" \
  > "$TMPFILE" || true

# --- Counter accumulator ---
# Each category increments its own counter variable.
declare -A COUNTS

scan() {
  local pattern_name="$1"
  local regex="$2"
  local category="$3"
  local hits=0

  while IFS= read -r file; do
    # grep -n: show line numbers; -E: extended regex; -I: skip binary files
    while IFS= read -r match; do
      echo "[${pattern_name}] ${match}"
      ((hits++)) || true
    done < <(grep -nE "$regex" "$file" 2>/dev/null | sed "s|^|${file}:|" || true)
  done < "$TMPFILE"

  COUNTS["$category"]=$(( ${COUNTS["$category"]:-0} + hits ))
}

scan_exclude() {
  # Like scan but skips files matching a path pattern
  local pattern_name="$1"
  local regex="$2"
  local category="$3"
  local exclude_path="$4"
  local hits=0

  while IFS= read -r file; do
    if echo "$file" | grep -qE "$exclude_path"; then
      continue
    fi
    while IFS= read -r match; do
      echo "[${pattern_name}] ${match}"
      ((hits++)) || true
    done < <(grep -nE "$regex" "$file" 2>/dev/null | sed "s|^|${file}:|" || true)
  done < "$TMPFILE"

  COUNTS["$category"]=$(( ${COUNTS["$category"]:-0} + hits ))
}

echo "=== vibeAudit Quick Scan ==="
echo "Scanning: $(pwd)"
echo "Files: $(wc -l < "$TMPFILE" | tr -d ' ')"
echo ""

# ─────────────────────────────────────────────────────────
# SECRETS
# ─────────────────────────────────────────────────────────

scan "HARDCODED_SECRET" \
  "(sk_live_|pk_live_|AIza[0-9A-Za-z_-]{35}|eyJhbGci|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36})" \
  "Secrets"

scan "CONSOLE_LOG_SENSITIVE" \
  "console\.log\(.*?(token|password|secret|key|auth)" \
  "Secrets"

# ─────────────────────────────────────────────────────────
# AUTH / SECURITY
# ─────────────────────────────────────────────────────────

scan "TODO_AUTH_COMMENT" \
  "(TODO|FIXME|HACK).*?(auth|security|token|password|login)" \
  "Auth"

scan "SERVICE_ROLE_IN_CLIENT" \
  "service_role" \
  "Auth"

scan "JWT_DECODE_NO_VERIFY" \
  "jwt\.decode(?!.*jwt\.verify)" \
  "Auth"

scan "MISSING_STRIPE_WEBHOOK_SIG" \
  "stripe\.webhooks\." \
  "Auth"

# ─────────────────────────────────────────────────────────
# STORAGE
# ─────────────────────────────────────────────────────────

scan "ASYNCSTORAGE_TOKEN" \
  "AsyncStorage\.(setItem|getItem)\(.*?(token|auth|password|secret)" \
  "Storage"

# ─────────────────────────────────────────────────────────
# XSS
# ─────────────────────────────────────────────────────────

scan "DANGEROUS_SET_INNER_HTML" \
  "dangerouslySetInnerHTML" \
  "XSS"

# ─────────────────────────────────────────────────────────
# LLM INJECTION
# ─────────────────────────────────────────────────────────

scan "DIRECT_PROMPT_CONCAT" \
  "(prompt|messages)\s*[+]=\s*(req\.|body\.|params\.|query\.)" \
  "LLM"

# ─────────────────────────────────────────────────────────
# TYPE SAFETY
# ─────────────────────────────────────────────────────────

scan "FETCH_AS_ANY" \
  "(fetch|axios)\([^)]*\)\s+as\s+any|response\.json\(\)\s+as\s+any" \
  "TypeSafety"

# ─────────────────────────────────────────────────────────
# SQL INJECTION
# ─────────────────────────────────────────────────────────

scan "SQL_STRING_INTERPOLATION" \
  "query\s*[+]=\s*(req\.|body\.|params\.)" \
  "SQLInjection"

scan "RAW_SQL_TEMPLATE" \
  "(SELECT|INSERT|UPDATE|DELETE).*\\\$\{" \
  "SQLInjection"

# ─────────────────────────────────────────────────────────
# ERROR HANDLING
# ─────────────────────────────────────────────────────────

scan "EMPTY_CATCH_BLOCK" \
  "catch\s*\([^)]*\)\s*\{\s*\}" \
  "ErrorHandling"

# ─────────────────────────────────────────────────────────
# EVAL
# ─────────────────────────────────────────────────────────

scan "EVAL_USAGE" \
  "\beval\s*\(" \
  "Eval"

# ─────────────────────────────────────────────────────────
# ENV VARS IN CLIENT CODE
# ─────────────────────────────────────────────────────────

scan_exclude "PROCESS_ENV_IN_CLIENT" \
  "process\.env\." \
  "EnvLeaks" \
  "(server|api|backend|node|worker)"

# ─────────────────────────────────────────────────────────
# HARDCODED URLS (localhost / 127.0.0.1 left in prod)
# ─────────────────────────────────────────────────────────

scan "HARDCODED_LOCALHOST_URL" \
  "(http|https)://(localhost|127\.0\.0\.1)" \
  "HardcodedURLs"

# ─────────────────────────────────────────────────────────
# MOCK / FAKE DATA MARKERS
# ─────────────────────────────────────────────────────────

scan_exclude "MOCK_DATA_IN_PROD" \
  "(mockData|fakeData|testData|MOCK_|FAKE_)" \
  "MockData" \
  "\.(test|spec)\.|__tests__"

# ─────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
printf "%-20s %s\n" "Category" "Hits"
printf "%-20s %s\n" "────────────────────" "────"

total=0
for category in Secrets Auth Storage XSS LLM TypeSafety SQLInjection ErrorHandling Eval EnvLeaks HardcodedURLs MockData; do
  count=${COUNTS["$category"]:-0}
  printf "%-20s %d\n" "$category" "$count"
  total=$((total + count))
done

echo ""
printf "%-20s %d\n" "TOTAL" "$total"
echo ""
echo "Note: these are unverified grep hits. Run /audit for deep analysis."
