#!/usr/bin/env bash
# detect-stack.sh
# Reads package.json in the current working directory and emits stack flags.
# Output: one KEY=true line per detected technology.
# Usage: bash scripts/detect-stack.sh (run from project root)

set -euo pipefail

PACKAGE_JSON="$(pwd)/package.json"

# If no package.json, nothing to detect
if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "# No package.json found in $(pwd)" >&2
  exit 0
fi

# node is always true when package.json exists
echo "STACK_NODE=true"

# Helper: check whether a dep name appears in dependencies or devDependencies
has_dep() {
  local dep="$1"
  # Use grep to avoid requiring jq — portable and zero-dependency
  grep -q "\"${dep}\"" "$PACKAGE_JSON" 2>/dev/null
}

# --- Framework / runtime detection ---

if has_dep "next"; then
  echo "STACK_NEXTJS=true"
fi

if has_dep "react-native"; then
  echo "STACK_REACT_NATIVE=true"
fi

if has_dep "expo"; then
  echo "STACK_EXPO=true"
fi

if has_dep "react"; then
  echo "STACK_REACT=true"
fi

# --- Database / BaaS ---

if has_dep "@supabase/supabase-js"; then
  echo "STACK_SUPABASE=true"
fi

# --- Payments ---

if has_dep "stripe"; then
  echo "STACK_STRIPE=true"
fi

# --- AI / LLM ---

if has_dep "openai"; then
  echo "STACK_OPENAI=true"
fi

if has_dep "anthropic"; then
  echo "STACK_ANTHROPIC=true"
fi

# --- Type system ---

if has_dep "typescript"; then
  echo "STACK_TYPESCRIPT=true"
fi

# --- Deployment ---

# vercel dep in package.json OR vercel.json present in project root
if has_dep "vercel" || [[ -f "$(pwd)/vercel.json" ]]; then
  echo "STACK_VERCEL=true"
fi
