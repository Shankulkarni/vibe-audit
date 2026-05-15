# vibeAudit — npm Distribution Design

**Date:** 2026-05-15  
**Status:** Approved

## Goal

Distribute vibeAudit via npm so any developer can install it with `npx vibeaudit install` regardless of which AI coding tool they use. Targets Claude Code, Cursor, Gemini CLI, and Codex. Also surfaces vibeAudit in npm search for discoverability.

## Approach

Plain JS single-file CLI (`cli.js`) at the repo root. No build step — consistent with vibeAudit's prompt-only identity. Uses `@clack/prompts` for interactive UX. Four subcommands: `install`, `update`, `status`, `uninstall`.

Install strategy: own detection logic first, `npx skills add` fallback. Cross-platform: macOS/Linux paths and Windows `%APPDATA%` / `%USERPROFILE%` paths both supported.

## Package Structure

Three new files added to repo root. Everything else unchanged.

```
vibeAudit/
├── cli.js                   ← new, single CLI entrypoint (~200 lines)
├── package.json             ← new
├── .claude-plugin/
├── .codex-plugin/
├── .cursor-plugin/          ← new, Cursor manifest
│   └── plugin.json
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

1. Detects installed AI tools by checking known config dirs (cross-platform):

| Tool | macOS / Linux | Windows |
|------|--------------|---------|
| Claude Code | `~/.claude/` | `%APPDATA%\Claude\` |
| Cursor | `~/.cursor/` | `%APPDATA%\Cursor\` |
| Gemini CLI | `~/.gemini/` | `%APPDATA%\gemini\` |
| Codex | `~/.codex/` | `%APPDATA%\Codex\` |

`cli.js` resolves paths via `os.homedir()` and `process.env.APPDATA` so no hardcoded Unix paths.

2. Shows `@clack/prompts` multi-select, pre-ticking detected tools. Final option: "All tools via `skills` CLI".

3. For each selected tool, copies manifest + skills into the tool's plugin directory:

| Tool | Source files | Destination |
|------|-------------|-------------|
| Claude Code | `.claude-plugin/` + `skills/` + `agents/` + `commands/` | `~/.claude/plugins/vibeaudit/` |
| Cursor | `.cursor-plugin/` + `skills/` | `~/.cursor/plugins/vibeaudit/` |
| Gemini CLI | `gemini-extension/` + `skills/` | `~/.gemini/extensions/vibeaudit/` |
| Codex | `.codex-plugin/` + `skills/` | `~/.codex/plugins/vibeaudit/` |

4. Fallback: if "All tools via skills CLI" selected, or no tools detected → spawns `npx skills add shankulkarni/vibeaudit --all`.

5. Records chosen tools to `~/.vibeaudit-config.json` for `update` to reference.

### `npx vibeaudit update`

Spawns `npm install -g vibeaudit@latest`, then silently re-runs install for tools listed in `~/.vibeaudit-config.json`.

### `npx vibeaudit uninstall`

1. Reads `~/.vibeaudit-config.json` to know which tools were installed.
2. Shows a multi-select (pre-ticking all installed tools) to confirm what to remove.
3. Deletes the plugin directory for each selected tool:

| Tool | Directory removed |
|------|------------------|
| Claude Code | `~/.claude/plugins/vibeaudit/` |
| Cursor | `~/.cursor/plugins/vibeaudit/` |
| Gemini CLI | `~/.gemini/extensions/vibeaudit/` |
| Codex | `~/.codex/plugins/vibeaudit/` |

4. Removes `~/.vibeaudit-config.json` if all tools are uninstalled.

### `npx vibeaudit status`

Checks each tool's plugin dir for vibeaudit presence. Compares installed version (reads `plugin.json`) against npm latest. Outputs a table:

```
vibeAudit v0.1.11

  Claude Code    ✓ installed   v0.1.11
  Cursor         ✗ not found
  Gemini CLI     ✓ installed   v0.1.9  (update available)
  Codex          ✗ not found
```

## Cursor Plugin Manifest

`.cursor-plugin/plugin.json` follows the same structure as `.codex-plugin/plugin.json`:

```json
{
  "name": "vibeaudit",
  "version": "0.1.11",
  "description": "Audits AI-generated (vibecoded) apps for security, quality, performance, and compliance gaps.",
  "author": {
    "name": "Shan Kulkarni",
    "url": "https://github.com/shankulkarni"
  },
  "homepage": "https://github.com/shankulkarni/vibeaudit",
  "repository": "https://github.com/shankulkarni/vibeaudit",
  "license": "MIT",
  "skills": "./skills/"
}
```

Version sync script (`scripts/bump-version.sh`) updated to include `.cursor-plugin/plugin.json` alongside the other three manifests.

## Versioning & Publish Workflow

Version is kept in sync across four files: `package.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`. A helper script `scripts/bump-version.sh <version>` updates all four with `sed`.

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
