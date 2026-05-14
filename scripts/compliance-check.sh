#!/usr/bin/env bash
# compliance-check.sh
# Shared grep pattern library for compliance skills.
# Not run directly — patterns referenced by audit-gdpr and future compliance skills.
# Usage: bash scripts/compliance-check.sh <pattern-group> <target-dir>
# Pattern groups: pii-in-logs | tracking-before-consent | consent-ui | vendor-detect | cookie-lib | error-monitoring | us-region

set -euo pipefail

EXCLUDE_DIRS="node_modules|\.git|dist|\.next|build|coverage|\.turbo|\.cache"
INCLUDE_EXT="\.(ts|tsx|js|jsx|mjs|cjs)$"
TARGET="${2:-.}"

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

find "$TARGET" -type f \
  | grep -E "$INCLUDE_EXT" \
  | grep -Ev "($EXCLUDE_DIRS)/" \
  | grep -Ev "\.(test|spec)\." \
  | grep -Ev "__tests__" \
  > "$TMPFILE" || true

case "${1:-}" in

  pii-in-logs)
    while IFS= read -r file; do
      grep -n -E \
        "console\.(log|error|warn|info)\s*\(.*\b(email|password|phone|ssn|dob|dateOfBirth|national_id|passport|credit_card|user\.)" \
        "$file" 2>/dev/null \
        | sed "s|^|[PII_IN_LOGS] ${file}:|" || true
    done < "$TMPFILE"

    while IFS= read -r file; do
      grep -n -E \
        "console\.(log|error|warn|info)\s*\(.*JSON\.stringify\s*\(\s*(user|req\.user|currentUser|profile)\s*\)" \
        "$file" 2>/dev/null \
        | sed "s|^|[PII_OBJECT_DUMP] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  tracking-before-consent)
    while IFS= read -r file; do
      grep -n -E \
        "(gtag\s*\(|fbq\s*\(|mixpanel\.init\s*\(|analytics\.track\s*\(|_paq\.push\s*\(|hotjar\.initialize\s*\(|Intercom\s*\()" \
        "$file" 2>/dev/null \
        | sed "s|^|[TRACKING_LOADER] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  consent-ui)
    while IFS= read -r file; do
      grep -n -E \
        "defaultChecked\s*=\s*\{?\s*true\s*\}?" \
        "$file" 2>/dev/null \
        | sed "s|^|[PRE_TICKED] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  vendor-detect)
    while IFS= read -r file; do
      grep -n -E \
        "from ['\"](@sendgrid|resend|@postmarkapp|twilio|openai|@anthropic-ai|@supabase|firebase|mixpanel|@segment|intercom|@hubspot|mailchimp)" \
        "$file" 2>/dev/null \
        | sed "s|^|[PROCESSOR_VENDOR] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  cookie-lib)
    while IFS= read -r file; do
      grep -n -E \
        "from ['\"]?(react-cookie-consent|cookieyes|onetrust|osano|tarteaucitron|cookiehub)" \
        "$file" 2>/dev/null \
        | sed "s|^|[COOKIE_CONSENT_LIB] ${file}:|" || true

      grep -n -E \
        "(document\.cookie\s*=|js-cookie|nookies\.set|cookies\.set)" \
        "$file" 2>/dev/null \
        | sed "s|^|[RAW_COOKIE_SET] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  error-monitoring)
    while IFS= read -r file; do
      grep -n -E \
        "from ['\"]?(@sentry/|datadog-|logrocket|rollbar|bugsnag)" \
        "$file" 2>/dev/null \
        | sed "s|^|[ERROR_MONITOR] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  us-region)
    while IFS= read -r file; do
      grep -n -E \
        "(us-east-1|us-west-2|us-central1|openai\.com|api\.anthropic\.com)" \
        "$file" 2>/dev/null \
        | sed "s|^|[US_REGION_ENDPOINT] ${file}:|" || true
    done < "$TMPFILE"
    ;;

  *)
    echo "Usage: $0 <pattern-group> [target-dir]"
    echo "Pattern groups: pii-in-logs | tracking-before-consent | consent-ui | vendor-detect | cookie-lib | error-monitoring | us-region"
    exit 1
    ;;
esac
