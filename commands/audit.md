# Command: /audit

Run an incremental audit of the current project. Reads only changed files, loads only relevant skills, merges with cached findings from unchanged files.

## Usage

```
/audit
/audit --report
```

- `/audit` — runs the audit and prints findings to the terminal.
- `/audit --report` — additionally writes `AUDIT_REPORT.md` to the project root.

---

## Pre-flight Check

Before starting, check whether `.claude/vibeaudit/state.json` exists:

```bash
test -f .claude/vibeaudit/state.json && echo "EXISTS" || echo "MISSING"
```

If it is missing, print:

```
vibeAudit has not been set up for this project yet.
Run the setup flow first to initialize the cache and state file.
```

Then stop. Do not proceed with the audit.

---

## Execution

Load the `audit-orchestrator` agent and instruct it to run the full audit flow:

1. **Phase 1 — Discovery** (bash scripts, ~5 seconds, 0 AI tokens)
   - `scripts/detect-stack.sh` — identify stack flags
   - `scripts/cache-check.sh` — get list of files needing audit
   - `scripts/quick-scan.sh` — grep-based pattern hits across the whole codebase

2. **Phase 2 — Deep Analysis** (Claude + skills, reads only changed/uncached files)
   - Load skills relevant to detected stack only
   - Read and analyze each file flagged by the cache check
   - Classify grep hits as true or false positives using full file context
   - Emit findings in standard format

3. **Phase 3 — Report** (merge + display)
   - Merge new findings with cached findings for unchanged files
   - Sort by severity: Critical → High → Medium → Low → Info
   - Print all findings
   - Print audit summary table

---

## Efficiency Directive

Tell the orchestrator:
- Use the cache. Do not re-analyze files that have not changed.
- Only load skills for the detected stack. Do not read skills for Supabase if there is no Supabase dependency.
- Do not read files not flagged by the cache check.
- Classify grep hits in context — do not surface raw grep output as findings.

---

## Report Output (--report flag)

If `--report` is passed, after printing findings to the terminal, invoke `/audit:report` to write `AUDIT_REPORT.md`.

---

## Finding Format

```
🔴 CRITICAL | Security | path/to/file.ts:23
Description of the issue — what is wrong and why it matters.
Fix: specific remediation

🟠 HIGH | Performance | src/api/users.ts:87
...
```

## Summary Table (always printed at end)

```
## Audit Summary
| Severity | Count |
|----------|-------|
| 🔴 Critical | N |
| 🟠 High | N |
| 🟡 Medium | N |
| 🟢 Low | N |
| ℹ️ Info | N |

Stack detected: Next.js, Supabase, Stripe
Files audited: 12 new + 34 cached
```
