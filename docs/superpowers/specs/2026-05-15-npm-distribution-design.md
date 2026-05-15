# vibeAudit — npm Distribution Design

**Date:** 2026-05-15  
**Status:** Approved

## Goal

Distribute vibeAudit via npm so any developer can install it with `npx vibeaudit install` regardless of which AI coding tool they use. Targets Claude Code, Cursor, Gemini CLI, and Codex. Also surfaces vibeAudit in npm search for discoverability.

## Approach

Plain JS single-file CLI (`cli.js`) at the repo root. No build step — consistent with vibeAudit's prompt-only identity. Uses `@clack/prompts` for interactive UX. Three subcommands: `install`, `update`, `status`.

Install strategy: own detection logic first, `npx skills add` fallback.

## Package Structure

Two new files added to repo root. Everything else unchanged.

```
vibeAudit/
├── cli.js                   ← new, single CLI entrypoint (~150 lines)
├── package.json             ← new
├── .claude-plugin/
├── .codex-plugin/
├── gemini-extension/
├── skills/
├── agents/
├── commands/
├── scripts/
```

### `package.json`

```json
{
  "name": "vibeaudit",
  "version": "0.1.11",
  "description": "Audits AI-generated (vibecoded) apps for security, quality, and performance.",
  "bin": { "vibeaudit": "./cli.js" },
  "files": [
    "cli.js",
    "skills/",
    "agents/",
    "commands/",
    "scripts/",
    ".claude-plugin/",
    ".codex-plugin/",
    "gemini-extension/",
    "AGENTS.md",
    "sources.json"
  ],
  "engines": { "node": ">=18" },
  "dependencies": { "@clack/prompts": "^0.9" },
  "keywords": ["security", "audit", "vibecode", "ai-generated", "owasp", "claude", "cursor", "gemini"],
  "license": "MIT",
  "homepage": "https://github.com/shankulkarni/vibeaudit",
  "repository": { "type": "git", "url": "https://github.com/shankulkarni/vibeaudit" }
}
```

## Commands

### `npx vibeaudit install`

1. Detects installed AI tools by checking known config dirs:

| Tool | Detection check |
|------|----------------|
| Claude Code | `~/.claude/` exists |
| Cursor | `~/.cursor/` exists |
| Gemini CLI | `~/.gemini/` exists |
| Codex | `~/.codex/` exists |

2. Shows `@clack/prompts` multi-select, pre-ticking detected tools. Final option: "All tools via `skills` CLI".

3. For each selected tool, copies manifest + skills into the tool's plugin directory:

| Tool | Source files | Destination |
|------|-------------|-------------|
| Claude Code | `.claude-plugin/` + `skills/` + `agents/` + `commands/` | `~/.claude/plugins/vibeaudit/` |
| Cursor | `.cursor-plugin/` + `skills/` | `~/.cursor/plugins/vibeaudit/` | *(manifest TBD — not yet created)* |
| Gemini CLI | `gemini-extension/` + `skills/` | `~/.gemini/extensions/vibeaudit/` |
| Codex | `.codex-plugin/` + `skills/` | `~/.codex/plugins/vibeaudit/` |

4. Fallback: if "All tools via skills CLI" selected, or no tools detected → spawns `npx skills add shankulkarni/vibeaudit --all`.

5. Records chosen tools to `~/.vibeaudit-config.json` for `update` to reference.

### `npx vibeaudit update`

Spawns `npm install -g vibeaudit@latest`, then silently re-runs install for tools listed in `~/.vibeaudit-config.json`.

### `npx vibeaudit status`

Checks each tool's plugin dir for vibeaudit presence. Compares installed version (reads `plugin.json`) against npm latest. Outputs a table:

```
vibeAudit v0.1.11

  Claude Code    ✓ installed   v0.1.11
  Cursor         ✗ not found
  Gemini CLI     ✓ installed   v0.1.9  (update available)
  Codex          ✗ not found
```

## Versioning & Publish Workflow

Version is kept in sync across three files: `package.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`. A helper script `scripts/bump-version.sh <version>` updates all three with `sed`.

Release steps:

```bash
bash scripts/bump-version.sh 0.1.12
git commit -am "chore: bump to v0.1.12"
git tag v0.1.12
npm publish --access public
```

### `.npmignore`

```
docs/
upstream/
.idea/
*.png
req.md
.claude/
```

The `files` allowlist in `package.json` is the primary guard; `.npmignore` is belt-and-suspenders.

## Out of Scope

- CI-automated publish (manual publish for now)
- Cursor plugin manifest (`.cursor-plugin/plugin.json`) — needs to be added as a separate task
- Windows path support (Cursor/Gemini detection paths may differ)
- Uninstall command
