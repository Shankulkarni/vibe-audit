#!/usr/bin/env bash
# find-secrets.sh
# Focused scan for hardcoded secrets and exposed credentials in source files.
# Excludes: node_modules, .git, test files, spec files, __tests__
# Usage: bash scripts/find-secrets.sh (run from project root)

set -euo pipefail

ROOT="$(pwd)"

# Patterns to exclude from scanning
EXCLUDE_PATTERN="(node_modules|\.git|dist|\.next|build|coverage|\.turbo)/|\.(test|spec)\.(ts|tsx|js|jsx)$|/__tests__/"

# Extensions to include
INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs|json|env\.example|yaml|yml)$"

echo "=== vibeAudit Secret Scanner ==="
echo "Root: $ROOT"
echo ""

# Collect source files (excluding test files and binary-ignored dirs)
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

find "$ROOT" -type f \
  | grep -E "$INCLUDE_EXT" \
  | grep -Ev "$EXCLUDE_PATTERN" \
  > "$TMPFILE" || true

total_hits=0

scan_secret() {
  local label="$1"
  local regex="$2"
  local hits=0

  while IFS= read -r file; do
    while IFS= read -r match; do
      echo "[${label}] ${match}"
      ((hits++)) || true
    done < <(grep -nE "$regex" "$file" 2>/dev/null | sed "s|^|${file}:|" || true)
  done < "$TMPFILE"

  if [[ $hits -gt 0 ]]; then
    total_hits=$((total_hits + hits))
  fi
}

# ─────────────────────────────────────────────────────────
# API Keys
# ─────────────────────────────────────────────────────────

echo "--- API Keys ---"

# Stripe live secret key
scan_secret "STRIPE_SK_LIVE" \
  "sk_live_[0-9A-Za-z]{24,}"

# Stripe live publishable key
scan_secret "STRIPE_PK_LIVE" \
  "pk_live_[0-9A-Za-z]{24,}"

# OpenAI secret key
scan_secret "OPENAI_SK" \
  "sk-[0-9A-Za-z]{32,}"

# Anthropic API key
scan_secret "ANTHROPIC_KEY" \
  "sk-ant-[0-9A-Za-z_-]{32,}"

# AWS access key ID
scan_secret "AWS_ACCESS_KEY_ID" \
  "AKIA[0-9A-Z]{16}"

# GCP API key
scan_secret "GCP_API_KEY" \
  "AIza[0-9A-Za-z_-]{35}"

# GitHub personal access token
scan_secret "GITHUB_TOKEN_GHP" \
  "ghp_[0-9A-Za-z]{36}"

# GitHub apps token
scan_secret "GITHUB_TOKEN_GHS" \
  "ghs_[0-9A-Za-z]{36}"

# ─────────────────────────────────────────────────────────
# JWT tokens
# ─────────────────────────────────────────────────────────

echo ""
echo "--- JWT Tokens ---"

scan_secret "JWT_TOKEN" \
  "eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"

# ─────────────────────────────────────────────────────────
# Private key blocks
# ─────────────────────────────────────────────────────────

echo ""
echo "--- Private Keys ---"

scan_secret "PRIVATE_KEY_BLOCK" \
  "-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"

# ─────────────────────────────────────────────────────────
# .env variable patterns in non-.env source files
# ─────────────────────────────────────────────────────────

echo ""
echo "--- ENV Variable Assignments in Source ---"

# KEY=value pattern in .ts/.js/.tsx/.jsx files (not in .env files themselves)
while IFS= read -r file; do
  # Skip actual .env files — only flag .env-style assignments in source code
  if echo "$file" | grep -qE "\.(env|envrc)"; then
    continue
  fi
  while IFS= read -r match; do
    echo "[ENV_VAR_IN_SOURCE] ${file}:${match}"
    ((total_hits++)) || true
  done < <(grep -nE "^[A-Z_]{3,}=['\"][^'\"]{8,}['\"]" "$file" 2>/dev/null || true)
done < "$TMPFILE"

# ─────────────────────────────────────────────────────────
# Connection strings
# ─────────────────────────────────────────────────────────

echo ""
echo "--- Connection Strings ---"

scan_secret "POSTGRESQL_CONN_STRING" \
  "postgresql://[^\"'\s]+"

scan_secret "MONGODB_CONN_STRING" \
  "mongodb(\+srv)?://[^\"'\s]+"

scan_secret "MYSQL_CONN_STRING" \
  "mysql://[^\"'\s]+"

scan_secret "REDIS_CONN_STRING" \
  "redis://[^\"'\s]+"

# ─────────────────────────────────────────────────────────
# Passwords hardcoded in source
# ─────────────────────────────────────────────────────────

echo ""
echo "--- Hardcoded Passwords ---"

scan_secret "HARDCODED_PASSWORD" \
  "password\s*=\s*[\"'][^\"']{6,}[\"']"

scan_secret "HARDCODED_SECRET_VAR" \
  "(secret|api_key|apikey|auth_token)\s*=\s*[\"'][^\"']{8,}[\"']"

# ─────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Secret Scan Complete ==="
echo "Total hits: $total_hits"
echo ""

if [[ $total_hits -gt 0 ]]; then
  echo "ACTION REQUIRED: Review each hit above. Rotate any real credentials immediately."
  echo "If these are test/example values, add them to .gitignore or use environment variables."
else
  echo "No obvious hardcoded secrets detected. This does not guarantee absence of secrets."
fi
