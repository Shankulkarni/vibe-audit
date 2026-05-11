# vibeAudit — Agent Audit Guidelines

These rules apply when running vibeAudit audit workflows from any agent host (Claude Code, Codex, Gemini CLI, or other platforms).

## What vibeAudit Does

vibeAudit audits AI-generated (vibecoded) codebases for security vulnerabilities, quality issues, and performance regressions before they reach production. It combines static grep scanning with deep AI analysis to produce verified, severity-classified findings — never raw grep output.

## Audit Flow

Run in this order. Never skip a phase — each gates the next.

1. **Stack Detection** — `bash scripts/detect-stack.sh` emits `STACK_*` flags from `package.json`.
2. **Cache Check** — `bash scripts/cache-check.sh` produces `FILES_TO_AUDIT`. Unchanged files reuse cached findings.
3. **Quick Scan** — `bash scripts/quick-scan.sh` produces `GREP_HITS`. These are **unverified** — never surface them directly as findings.
4. **Load Skills** — Load only skills whose `STACK_*` flag matched. Loading all skills wastes tokens.
5. **Deep Analysis** — Read each file in `FILES_TO_AUDIT`. Apply loaded skill rules. Classify every grep hit from Step 3 as a true or false positive using full file context.
6. **Report** — Merge new findings with cached findings for unchanged files. Sort by severity.
7. **Cache Update** — `bash scripts/cache-update.sh` persists hashes and findings for the next run.

**Key invariant:** Raw grep hits from Step 3 are never surfaced. Every finding must be confirmed by reading full file context in Step 5.

## Skill Routing by Stack

| Stack Flag | Load These Skills |
|------------|-------------------|
| Always | `audit-vibecode-patterns`, `audit-typescript-any-escape` |
| `STACK_NEXTJS` | `audit-nextjs-server-actions`, `audit-react-xss` |
| `STACK_REACT` (no Next.js) | `audit-react-xss` |
| `STACK_SUPABASE` | `audit-supabase-rls` |
| `STACK_STRIPE` | `audit-stripe-integration` |
| `STACK_REACT_NATIVE` | `audit-react-native-secure-storage` |
| `STACK_NODE_API` | `audit-node-api-auth` |
| `STACK_OPENAI` / `STACK_ANTHROPIC` | `audit-llm-prompt-injection` |
| `STACK_VERCEL` | `audit-vercel-deployment` |

## Finding Format

Every finding must follow this format exactly:

```
🔴 CRITICAL | [Category] | path/to/file.ts:LINE
Description — what is wrong and why it matters.
Fix: specific remediation code or approach
```

Severity scale: `🔴 CRITICAL` → `🟠 HIGH` → `🟡 MEDIUM` → `🟢 LOW` → `ℹ️ INFO`

Surface findings in severity order. Never invent severity levels.

## Hard Rules

- **No false positives.** Every finding requires full file context, not just a grep match.
- **No unverified hits.** Classify every grep hit as true or false positive before reporting.
- **No irrelevant skills.** Load only skills matching the detected stack.
- **No stale reads.** Always run `cache-check.sh` before analyzing files.
- **No manual edits.** Never touch `.claude/vibeaudit/` files directly.

## Host Capability Notes

- **Claude Code** — Native plugin. Use `/audit`, `/audit:full`, `/audit:quick`, `/audit:security`, `/audit:ci`, `/audit:report` slash commands. Full agent orchestration with `agents/audit-orchestrator.md`.
- **Codex** — Skills loaded from `.codex-plugin/`. Run the audit flow via bash scripts above. Role profiles in `agents/` are guidance, not native Codex agents.
- **Gemini CLI** — Extension provides this `AGENTS.md` as context and symlinks `skills/`. Run bash scripts directly. Load relevant `skills/*/skill.md` files as reference for your analysis.
- **Other hosts** — Follow the 7-step flow above. Load skill markdown files manually as context. Run bash scripts for scanning and caching.

## Severity Triage

1. `🔴 CRITICAL` — Exploitable now; block merge/deploy
2. `🟠 HIGH` — Likely exploitable; fix before production
3. `🟡 MEDIUM` — Risk present; fix in current sprint
4. `🟢 LOW` — Hardening opportunity; fix when touching the file
5. `ℹ️ INFO` — Awareness only; no action required
