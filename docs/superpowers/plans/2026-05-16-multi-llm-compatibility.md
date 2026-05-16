# Multi-LLM Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `npx vibe-code-audit install` produce a working end-to-end audit experience for Claude Code, Gemini CLI, and Codex.

**Architecture:** All fixes live in `cli.js` (installer logic) and `README.md` (user-facing instructions). No new files, no new dependencies. The installer now resolves issues at copy time: commands go to `~/.claude/commands/` for Claude Code, real files replace broken symlinks for Gemini CLI, and `AGENTS.md` is included for Codex.

**Tech Stack:** Node.js ESM, `fs` built-ins (`cpSync`, `mkdirSync`, `readdirSync`), bash for verification.

---

### Task 1: Verify Claude Code fix in cli.js

**Files:**
- Verify: `cli.js:22-29` (claude tool config)
- Verify: `cli.js:82-94` (copyFiles commandsDest block)
- Verify: `cli.js:165-183` (uninstall commandsDest cleanup)

- [ ] **Step 1: Confirm `commandsDest` is present on the claude tool config**

```bash
grep -n "commandsDest" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/cli.js
```

Expected output: 3 lines — one in the tool config definition, one in `copyFiles`, one in the uninstall loop.

- [ ] **Step 2: Confirm commands were already copied to ~/.claude/commands/**

```bash
ls ~/.claude/commands/
```

Expected: `audit.md  audit-ci.md  audit-full.md  audit-quick.md  audit-report.md  audit-security.md`

---

### Task 2: Verify Gemini CLI fix in cli.js

**Files:**
- Verify: `cli.js:39-47` (gemini tool config with `resolveIntoExtension`)
- Verify: `cli.js:84-94` (copyFiles resolveIntoExtension block)

- [ ] **Step 1: Confirm `resolveIntoExtension` is present on the gemini tool config**

```bash
grep -n "resolveIntoExtension" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/cli.js
```

Expected: 2 lines — one in config definition, one in `copyFiles`.

- [ ] **Step 2: Confirm the copyFiles block copies real files, not symlinks**

```bash
grep -A 10 "resolveIntoExtension" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/cli.js | grep "cpSync"
```

Expected: line containing `cpSync(src, join(extDir, name), { recursive: true })`

---

### Task 3: Verify Codex fix in cli.js

**Files:**
- Verify: `cli.js:48-55` (codex tool config sources)

- [ ] **Step 1: Confirm AGENTS.md is in the codex sources array**

```bash
grep -A 6 "value: 'codex'" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/cli.js
```

Expected: `sources: ['.codex-plugin', 'skills', 'AGENTS.md']`

---

### Task 4: Verify README accuracy

**Files:**
- Verify: `README.md` (Install & Use section)

- [ ] **Step 1: Confirm invalid codex command is gone**

```bash
grep "codex plugin add" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/README.md
```

Expected: no output (line removed).

- [ ] **Step 2: Confirm Gemini section shows both install paths**

```bash
grep -n "gemini" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/README.md
```

Expected: lines for both `npx vibe-code-audit install` (option 1) and `gemini extension install` (option 2).

- [ ] **Step 3: Confirm Codex section has the audit prompt**

```bash
grep -A 5 "### Codex" /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/README.md
```

Expected: `npx vibe-code-audit install` instruction and a natural-language audit prompt.

---

### Task 5: Bump version to 0.1.29

**Files:**
- Modify: `package.json` (version field)
- Modify: `.claude-plugin/plugin.json` (version field)
- Modify: `.codex-plugin/plugin.json` (version field)
- Modify: `gemini-extension/gemini-extension.json` (version field)

- [ ] **Step 1: Update package.json**

In `package.json`, change:
```json
"version": "0.1.28",
```
to:
```json
"version": "0.1.29",
```

- [ ] **Step 2: Update .claude-plugin/plugin.json**

In `.claude-plugin/plugin.json`, change:
```json
"version": "0.1.28",
```
to:
```json
"version": "0.1.29",
```

- [ ] **Step 3: Update .codex-plugin/plugin.json**

In `.codex-plugin/plugin.json`, change:
```json
"version": "0.1.28",
```
to:
```json
"version": "0.1.29",
```

- [ ] **Step 4: Update gemini-extension/gemini-extension.json**

In `gemini-extension/gemini-extension.json`, change:
```json
"version": "0.1.28",
```
to:
```json
"version": "0.1.29",
```

- [ ] **Step 5: Verify all four are in sync**

```bash
grep '"version"' \
  /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/package.json \
  /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/.claude-plugin/plugin.json \
  /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/.codex-plugin/plugin.json \
  /Users/shan/Documents/ssd/Projects/libraries/vibeAudit/gemini-extension/gemini-extension.json
```

Expected: all four lines show `"version": "0.1.29"`.

---

### Task 6: Commit

**Files:** all modified files

- [ ] **Step 1: Stage all changes**

```bash
git add cli.js README.md package.json \
  .claude-plugin/plugin.json \
  .codex-plugin/plugin.json \
  gemini-extension/gemini-extension.json \
  docs/superpowers/specs/2026-05-16-multi-llm-compatibility-design.md \
  docs/superpowers/plans/2026-05-16-multi-llm-compatibility.md
```

- [ ] **Step 2: Commit**

```bash
git commit -m "fix: end-to-end installer for Claude Code, Gemini CLI, and Codex

- Claude Code: copy commands to ~/.claude/commands/ so /audit is
  immediately available (Claude Code ignores plugins/ without registry entry)
- Gemini CLI: resolve AGENTS.md + skills/ symlinks at install time;
  npm pack does not follow symlinks so extension was missing context
- Codex: add AGENTS.md to copied sources; fix README to remove invalid
  'codex plugin add' command and add correct natural-language prompt
- Bump version to 0.1.29"
```

- [ ] **Step 3: Verify commit**

```bash
git log --oneline -3
```

Expected: top commit contains "fix: end-to-end installer".
