#!/usr/bin/env bash
# sync-upstream.sh
# Fetches upstream skill/rule files from sources.json and vendors them locally.
# Compares against existing vendored copies — exits 0 if changes found, 1 if nothing new.
# Usage: bash scripts/sync-upstream.sh [--dry-run]
# Requires: bash, curl, jq, git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_FILE="${ROOT_DIR}/sources.json"
UPSTREAM_DIR="${ROOT_DIR}/upstream"
DRY_RUN=false
CHANGES_FOUND=false

if [[ "${1:-}" == "--dry-run" ]]; then
	DRY_RUN=true
	echo "[dry-run] No files will be written."
fi

if [[ ! -f "$SOURCES_FILE" ]]; then
	echo "ERROR: sources.json not found at $SOURCES_FILE" >&2
	exit 2
fi

# Create upstream dir if needed
if [[ "$DRY_RUN" == false ]]; then
	mkdir -p "$UPSTREAM_DIR"
fi

# Read source count
SOURCE_COUNT=$(jq '.sources | length' "$SOURCES_FILE")
echo "=== vibeAudit Upstream Sync ==="
echo "Sources: $SOURCE_COUNT"
echo ""

for i in $(seq 0 $((SOURCE_COUNT - 1))); do
	SOURCE_ID=$(jq -r ".sources[$i].id" "$SOURCES_FILE")
	REPO=$(jq -r ".sources[$i].repo" "$SOURCES_FILE")
	BRANCH=$(jq -r ".sources[$i].branch" "$SOURCES_FILE")
	TARGET_DIR_NAME=$(jq -r ".sources[$i].target_dir" "$SOURCES_FILE")
	TARGET_DIR="${ROOT_DIR}/${TARGET_DIR_NAME}"
	COVERS=$(jq -r ".sources[$i].covers" "$SOURCES_FILE")
	PATH_COUNT=$(jq ".sources[$i].paths | length" "$SOURCES_FILE")

	echo "--- [$SOURCE_ID] $REPO ---"
	echo "    Covers: $COVERS"

	if [[ "$DRY_RUN" == false ]]; then
		mkdir -p "$TARGET_DIR"
	fi

	for j in $(seq 0 $((PATH_COUNT - 1))); do
		REMOTE_PATH=$(jq -r ".sources[$i].paths[$j]" "$SOURCES_FILE")

		# If path ends with /, it's a directory — fetch the tree via GitHub API
		if [[ "$REMOTE_PATH" == */ ]]; then
			echo "    Fetching directory: $REMOTE_PATH"

			# Use GitHub API to list files in the directory
			API_URL="https://api.github.com/repos/${REPO}/contents/${REMOTE_PATH}?ref=${BRANCH}"
			DIR_LISTING=$(curl -sf -H "Accept: application/vnd.github.v3+json" \
				${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
				"$API_URL" 2>/dev/null || echo "[]")

			if [[ "$DIR_LISTING" == "[]" ]] || [[ "$DIR_LISTING" == *"Not Found"* ]]; then
				echo "    WARN: Could not list $REMOTE_PATH — skipping" >&2
				continue
			fi

			# Filter to .md files only
			FILE_NAMES=$(echo "$DIR_LISTING" | jq -r '.[] | select(.type == "file") | select(.name | endswith(".md")) | .name' 2>/dev/null || true)

			for FILE_NAME in $FILE_NAMES; do
				RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${REMOTE_PATH}${FILE_NAME}"
				LOCAL_FILE="${TARGET_DIR}/${FILE_NAME}"

				CONTENT=$(curl -sf "$RAW_URL" 2>/dev/null || echo "")
				if [[ -z "$CONTENT" ]]; then
					echo "    WARN: Failed to fetch $FILE_NAME — skipping" >&2
					continue
				fi

				# Compare with existing
				if [[ -f "$LOCAL_FILE" ]]; then
					EXISTING=$(cat "$LOCAL_FILE")
					if [[ "$CONTENT" == "$EXISTING" ]]; then
						continue
					fi
					echo "    UPDATED: $FILE_NAME"
				else
					echo "    NEW: $FILE_NAME"
				fi

				CHANGES_FOUND=true
				if [[ "$DRY_RUN" == false ]]; then
					echo "$CONTENT" > "$LOCAL_FILE"
				fi
			done
		else
			# Single file fetch — derive unique local name from path to avoid collisions
			# e.g. plugins/insecure-defaults/skills/insecure-defaults/SKILL.md → insecure-defaults.md
			PARENT_DIR=$(basename "$(dirname "$REMOTE_PATH")")
			FILE_EXT=$(basename "$REMOTE_PATH" | sed 's/.*\.//')
			LOCAL_NAME="${PARENT_DIR}.${FILE_EXT}"
			RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${REMOTE_PATH}"
			LOCAL_FILE="${TARGET_DIR}/${LOCAL_NAME}"

			echo "    Fetching: $REMOTE_PATH"
			CONTENT=$(curl -sf "$RAW_URL" 2>/dev/null || echo "")

			if [[ -z "$CONTENT" ]]; then
				echo "    WARN: Failed to fetch $REMOTE_PATH — skipping" >&2
				continue
			fi

			# Compare with existing
			if [[ -f "$LOCAL_FILE" ]]; then
				EXISTING=$(cat "$LOCAL_FILE")
				if [[ "$CONTENT" == "$EXISTING" ]]; then
					echo "    No changes: $LOCAL_NAME"
					continue
				fi
				echo "    UPDATED: $LOCAL_NAME"
			else
				echo "    NEW: $LOCAL_NAME"
			fi

			CHANGES_FOUND=true
			if [[ "$DRY_RUN" == false ]]; then
				echo "$CONTENT" > "$LOCAL_FILE"
			fi
		fi
	done

	echo ""
done

# Write sync timestamp
if [[ "$DRY_RUN" == false && "$CHANGES_FOUND" == true ]]; then
	SYNC_META="${UPSTREAM_DIR}/last-sync.json"
	cat > "$SYNC_META" <<EOF
{
  "syncedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}
EOF
fi

echo "=== Sync Complete ==="
if [[ "$CHANGES_FOUND" == true ]]; then
	echo "Changes found — review upstream/ directory."
	exit 0
else
	echo "No changes detected."
	exit 1
fi
