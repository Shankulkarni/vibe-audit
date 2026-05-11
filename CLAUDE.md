# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

vibeAudit is a **Claude Code plugin** — not an application. It ships as a plugin installable via `/plugin install vibeaudit@shankulkarni`. The codebase is entirely prompt-driven: skills, agents, commands, and scripts. There is no compiled code, no test suite, no build step.

## Plugin Structure

The plugin is declared in `.claude-plugin/plugin.json`. Claude Code reads this to register skills (from `skills/`), commands (from `commands/`), and agents (from `agents/`).

```
skills/          # 10 audit skill files — each a skill.md with frontmatter + rules
agents/          # 4 agent instruction files — orchestrator + 3 specialist reviewers
commands/        # 5 slash command definitions — each describes a full execution plan
scripts/         # Bash scripts for stack detection, grep scanning, caching, indexing
docs/            # Architecture reference
```

## Audit Flow (Critical to Understand)

The `/audit` command runs in 8 phases via `agents/audit-orchestrator.md`:

1. **Repo Index** — `build-index.sh` or `agent-toolkit` creates `.claude/vibeaudit/index.json` (symbol map)
2. **Stack Detection** — `detect-stack.sh` reads `package.json` and emits `STACK_*` flags
3. **Cache Check** — `cache-check.sh` compares git diff against last audit commit to produce `FILES_TO_AUDIT`
4. **Quick Scan** — `quick-scan.sh` greps 50+ patterns; output is `GREP_HITS` for Phase 6 verification, not direct findings
5. **Load Skills** — only skills matching detected stack flags are loaded (to save tokens)
6. **Deep Analysis** — Claude reads each file in `FILES_TO_AUDIT`, applies skill rules, classifies grep hits as true/false positives
7. **Report Compilation** — merges new findings + cached findings from unchanged files, sorts by severity
8. **Cache Update** — `cache-update.sh` persists hashes and state

**Key invariant**: Raw grep hits from Phase 4 are never surfaced directly. They must be confirmed or dismissed by Claude in Phase 6 after reading the full file context.

## Caching Architecture

Five layers prevent redundant token spend across repeat runs:

| Layer | Mechanism | Storage |
|-------|-----------|---------|
| Repo index | git-incremental symbol map | `.claude/vibeaudit/index.json` |
| Findings cache | per-file hash → findings | `.claude/vibeaudit/findings-cache.json` |
| Change detection | `git diff <lastAuditCommit> HEAD` | `.claude/vibeaudit/state.json` |
| Prompt cache | static skills loaded early as system context | Anthropic prefix cache |
| Full-mode pack | repomix compressed source | `.claude/vibeaudit/packed.xml` |

Do not edit any `.claude/vibeaudit/` files manually.

## Stack Detection → Skill Routing

`detect-stack.sh` sets `STACK_*` flags from `package.json` deps. Skills load conditionally:

| Flag | Skills loaded |
|------|--------------|
| Always | `audit-vibecode-patterns`, `audit-typescript-any-escape` |
| `STACK_NEXTJS` | `audit-nextjs-server-actions`, `audit-react-xss` |
| `STACK_REACT` (no Next) | `audit-react-xss` |
| `STACK_SUPABASE` | `audit-supabase-rls` |
| `STACK_STRIPE` | `audit-stripe-integration` |
| `STACK_REACT_NATIVE` | `audit-react-native-secure-storage` |
| `STACK_NODE_API` | `audit-node-api-auth` |
| `STACK_OPENAI` / `STACK_ANTHROPIC` | `audit-llm-prompt-injection` |
| `STACK_VERCEL` | `audit-vercel-deployment` |

## Commands

| Command | Mode | What it runs |
|---------|------|-------------|
| `/audit` | Incremental | Full orchestrator — cache-aware, only re-audits changed files |
| `/audit:full` | Full | Repomix-packs everything, bypasses cache, runs all three reviewer agents |
| `/audit:quick` | Grep-only | `quick-scan.sh` + `find-secrets.sh` — ~5s, zero AI tokens, unverified hits |
| `/audit:security` | Security-focused | Security skills only, outputs Critical + High only |
| `/audit:report` | Report only | Writes `AUDIT_REPORT.md` from current findings |

## Skill File Anatomy

Each skill lives in `skills/<name>/skill.md` with YAML frontmatter:

```yaml
---
name: audit-<name>
description: one-line summary
triggers: [list, of, keywords]
---
```

Followed by: purpose, what to look for (with code examples), severity classification table, finding format examples, and common false positives. When adding or editing a skill, maintain all these sections.

## Finding Format Standard

Every finding must follow:

```
🔴 CRITICAL | [Category] | path/to/file.ts:LINE
Description of the issue — what is wrong and why it matters.
Fix: specific remediation code or approach
```

Severity scale: `🔴 CRITICAL` → `🟠 HIGH` → `🟡 MEDIUM` → `🟢 LOW` → `ℹ️ INFO`

## Agents

| Agent | Role |
|-------|------|
| `audit-orchestrator.md` | Drives the 8-phase flow; the main brain behind `/audit` |
| `audit-security-reviewer.md` | Deep pass: auth, injection, secrets, crypto |
| `audit-quality-reviewer.md` | Patterns: error handling, dead code, AI slop |
| `audit-performance-reviewer.md` | Queries, bundle size, memoization, re-renders |

`/audit:full` runs all three reviewer agents in sequence after loading the repomix pack. `/audit:security` runs only the security reviewer.

## Scripts Reference

| Script | What it does |
|--------|-------------|
| `detect-stack.sh` | Reads `package.json`, emits `STACK_*` flags |
| `quick-scan.sh` | Greps 50+ patterns, outputs `[PATTERN_NAME] file:line: match` |
| `find-secrets.sh` | Looks for hardcoded credentials and API key patterns |
| `build-index.sh` | Lightweight fallback index builder (find + grep + jq) |
| `cache-check.sh` | Produces `FILES_TO_AUDIT` via git diff + content hash comparison |
| `cache-update.sh` | Persists new findings and file hashes after an audit |
| `pack-context.sh` | Runs repomix for `/audit:full` mode |
| `setup.sh` / `teardown.sh` | Plugin lifecycle hooks |

Scripts use `set -euo pipefail` and require no dependencies beyond bash, grep, and jq (with agent-toolkit as an optional enhancement for `build-index.sh`).

## Upstream Skill Sync

vibeAudit enriches its skills from 5 upstream repos (one per domain, no overlap). The system is defined in `sources.json` and runs via a weekly GitHub Action.

| Source | Domain | Enriches |
|--------|--------|----------|
| `trailofbits/skills` | Static analysis, supply chain, insecure defaults | `audit-vibecode-patterns`, `audit-node-api-auth` |
| `agamm/claude-code-owasp` | OWASP Top 10:2025, ASVS 5.0 | `audit-node-api-auth`, `audit-react-xss`, `audit-nextjs-server-actions` |
| `yoanbernabeu/supabase-pentest-skills` | Supabase RLS, auth, RPC | `audit-supabase-rls` |
| `callstackincubator/agent-skills` | React Native performance | `audit-react-native-secure-storage` |
| `hookdeck/webhook-skills` | Webhook signature patterns | `audit-stripe-integration` |

**How it works:**
- `scripts/sync-upstream.sh` fetches `.md` skill files from each upstream repo and vendors them into `upstream/<source>/`
- `.github/workflows/sync-upstream-skills.yml` runs weekly (Monday 6am UTC) or on manual dispatch
- When upstream changes are detected, the action opens a PR for review
- Vendored files in `upstream/` are reference material — the actual audit skills in `skills/` are maintained separately and updated manually after reviewing upstream changes
- Run locally: `bash scripts/sync-upstream.sh` (or `--dry-run` to preview)
