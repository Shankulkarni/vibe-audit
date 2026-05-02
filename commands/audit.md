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

## Auto-Update

Before anything else, pull the latest plugin code:

```bash
bash scripts/auto-update.sh
```

This is silent and non-blocking — if the network is unavailable or the pull fails, the audit continues with the current version.

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

## `.env` File Rules

- **Never read `.env` file contents**. These contain secrets — reading them leaks secrets into the LLM context.
- **Do check if `.env` files are tracked by git.** If any `.env` file is committed, emit a 🔴 CRITICAL finding — but never read or display its contents.

---

## Report Output (--report flag)

If `--report` is passed, after printing findings to the terminal, invoke `/audit:report` to write `AUDIT_REPORT.md`.

---

## Terminal Display Format

Print findings grouped by severity. Each severity level gets a banner divider. Findings are indented under it with a blank line between each one.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━  🔴 CRITICAL  ━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [Security]  src/app/api/stripe/route.ts:23
  Missing Stripe signature verification — any HTTP request can spoof a payment event
  Fix → const sig = headers.get('stripe-signature')
         await stripe.webhooks.constructEventAsync(body, sig, env.STRIPE_WEBHOOK_SECRET)

  [Security]  src/lib/auth.ts:45
  JWT secret hardcoded — anyone with repo access can forge tokens
  Fix → Replace with process.env.JWT_SECRET; add to .env.example

━━━━━━━━━━━━━━━━━━━━━━━━━━━  🟠 HIGH  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [Performance]  src/api/feed.ts:112
  N+1 query in activity feed — fires one SELECT per user row
  Fix → Add .select('*, profiles(*)') to batch the join

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Omit banners for severity levels with zero findings
- Within each section, group by category (Security → Performance → Quality), then sort by file path
- For multi-line fixes, indent continuation lines to align with the first line

## Summary Table (always printed at end)

```
  Audit Summary
  ┌────────────────┬───────┐
  │ 🔴  Critical   │   2   │
  │ 🟠  High       │   1   │
  │ 🟡  Medium     │   5   │
  │ 🟢  Low        │   8   │
  │ ℹ️   Info       │   2   │
  ├────────────────┼───────┤
  │    Total       │  18   │
  └────────────────┴───────┘

  Stack: Next.js · Supabase · Stripe
  Files: 12 new + 34 cached

  Next steps:
    1. Fix N Critical findings before deploy       (if any Critical)
    2. Address N High findings before next release (if any High)
    3. Schedule Medium findings for this sprint    (if any Medium)
```

Omit next-steps lines for severity levels with zero findings.
