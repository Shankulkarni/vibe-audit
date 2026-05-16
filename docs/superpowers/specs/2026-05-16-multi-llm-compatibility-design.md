---
title: Multi-LLM Compatibility — End-to-End Audit
date: 2026-05-16
status: implemented
---

## Problem

`npx vibe-code-audit install` did not produce a working end-to-end experience for any of the three target tools (Claude Code, Gemini CLI, Codex). The README described install commands that were either incorrect or incomplete.

## Findings Per Tool

### Claude Code

**Root cause:** The installer copied files to `~/.claude/plugins/vibeaudit/` but Claude Code only loads plugins registered in `installed_plugins.json`. It does not auto-scan the plugins directory. Commands were never visible as slash commands.

**Fix:** Installer now also copies all command `.md` files to `~/.claude/commands/`, which Claude Code reads unconditionally. Existing installation patched by direct copy.

**Status after fix:** `npx vibe-code-audit install → Claude Code → /audit` works end-to-end.

### Gemini CLI

**Root cause:** `gemini-extension/` uses symlinks (`AGENTS.md → ../AGENTS.md`, `skills → ../skills`). npm does not resolve symlinks during pack — only `gemini-extension.json` (83B) was included in the published package. Installing via npm left the extension directory without `AGENTS.md` or skills, so Gemini CLI had no audit context.

**Fix:** Added `resolveIntoExtension: ['AGENTS.md', 'skills']` to the Gemini tool config. `copyFiles()` now explicitly copies the real files into `<dest>/gemini-extension/` at install time, bypassing the symlink limitation.

**Note:** `gemini extension install Shankulkarni/vibe-audit` (GitHub install) was already working because git resolves symlinks on clone.

**Status after fix:** Both npm install and GitHub install paths work end-to-end.

### Codex

**Root cause (install command):** README showed `codex plugin add vibeaudit@shankulkarni` — this is not a valid Codex CLI subcommand. Codex CLI has no `plugin add` subcommand.

**Root cause (missing context):** Installer sources for Codex did not include `AGENTS.md`, so Codex had no instructions for running the audit flow.

**Fix:** Added `AGENTS.md` to Codex installer sources. Updated README to use `npx vibe-code-audit install` as the install path and provide the correct prompt for triggering an audit (Codex has no slash commands).

**Status after fix:** `npx vibe-code-audit install → Codex → prompt` works with correct context available.

## Changes Made

| File | Change |
|------|--------|
| `cli.js` | Claude: copy commands to `~/.claude/commands/` on install/uninstall |
| `cli.js` | Gemini: resolve symlinks by copying `AGENTS.md` + `skills/` into extension dest |
| `cli.js` | Codex: add `AGENTS.md` to copied sources |
| `README.md` | Gemini: show npm install as primary, GitHub install as option 2 |
| `README.md` | Codex: replace invalid `codex plugin add` with `npx vibe-code-audit install` + correct prompt |
| `README.md` | Claude Code: clear 2-step flow, marketplace as alternative |

## Remaining Limitations

- **Cursor**: installer copies to `~/.cursor/plugins/vibeaudit/` but Cursor's plugin discovery mechanism has not been audited. Out of scope for this session.
- **Codex detect dir**: installer detects Codex by checking `~/.codex/` — if Codex CLI uses a different config path on the user's system, detection may fail. Fallback is manual selection in the install prompt.
- **Gemini CLI `contextFileName` symlink resolution**: the GitHub install path leaves `AGENTS.md` as a symlink inside the extension dir. Whether Gemini CLI resolves symlinks when reading `contextFileName` is untested. The npm install path now copies a real file, so this only affects the GitHub install.
