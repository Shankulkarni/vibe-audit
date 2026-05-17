# Command: /audit:full

Run a complete, cache-bypassing audit of the entire codebase. This is the most thorough audit mode — it ignores the cache, packs the full codebase into a compressed context, and applies all relevant skills.

## Usage

```
/audit:full
```

## When to Use

- Initial audit of a new project
- Before a major release or security review
- When you suspect cached findings are stale or incomplete
- After a large refactor that touched many files

This mode costs more tokens than `/audit` but provides the most thorough coverage.

## `.env` File Rules

- **Never read `.env` file contents** (`.env`, `.env.local`, `.env.production`, `.env.*`). These contain secrets — reading them leaks secrets into the LLM context.
- **Do check if `.env` files are tracked by git.** If any `.env` file is committed, emit a 🔴 CRITICAL finding about it being in git history — but never read or display its contents.

---

## Auto-Update

Before anything else, pull the latest plugin code:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/auto-update.sh"
```

This is silent and non-blocking — if the network is unavailable or the pull fails, the audit continues with the current version.

---

## Execution

### Step 1 — Stack Detection

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/detect-stack.sh"
```

Record stack flags: `HAS_NEXTJS`, `HAS_SUPABASE`, `HAS_STRIPE`, `HAS_REACT_NATIVE`, `HAS_NODE_API`, `HAS_LLM`, `HAS_VERCEL`.

### Step 2 — Pack Full Codebase Context

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/pack-context.sh"
```

This uses repomix to create a compressed, token-efficient snapshot of the entire codebase. Read the output file it produces. This is the primary input for analysis.

### Step 3 — Load All Applicable Skills

Based on stack flags, load every relevant skill directory. In full mode, do not skip skills — load all that match any detected flag:

| Stack flag | Skills to load |
|---|---|
| Always | `skills/audit-vibecode-patterns/`, `skills/audit-typescript-any-escape/` |
| `HAS_NEXTJS` | `skills/audit-nextjs-server-actions/` |
| `HAS_SUPABASE` | `skills/audit-supabase-rls/` |
| `HAS_STRIPE` | `skills/audit-stripe-integration/` |
| `HAS_REACT_NATIVE` | `skills/audit-react-native-secure-storage/`, `skills/audit-react-xss/` |
| `HAS_NODE_API` | `skills/audit-node-api-auth/` |
| `HAS_LLM` | `skills/audit-llm-prompt-injection/` |
| `HAS_VERCEL` | `skills/audit-vercel-deployment/` |

### Step 4 — Deep Analysis

Apply all loaded skills to the packed codebase context. For each skill:
- Identify every file in the packed context that is in scope for this skill
- Apply the skill's rules
- Emit findings in standard finding format (see below)

Run all three reviewer agents in sequence:
1. Load `agents/audit-security-reviewer.md` — security pass
2. Load `agents/audit-quality-reviewer.md` — quality pass
3. Load `agents/audit-performance-reviewer.md` — performance pass

#### Standard Finding Format (all findings MUST use this)

```
🔴 CRITICAL | Security | path/to/file.ts:23
Description of the issue — what is wrong and why it matters.
Fix: specific remediation code or approach
```

Every finding must have: severity emoji + level, category, file:line, description, and fix.

### Step 5 — Compile and Deduplicate Findings

After all three reviewer agents have completed:

1. **Collect** all findings from skills + all three reviewers into a single list
2. **Deduplicate** — if two reviewers flagged the same file:line, keep the higher severity and merge the descriptions
3. **Classify** — ensure every finding uses the correct severity per the calibration rules (Critical = exploitable without auth; High = exploitable with user access; etc.)
4. **Sort** — Critical → High → Medium → Low → Info, then by category (Security → Performance → Quality), then by file path alphabetically within each group

This compiled list is the single source of truth for both the terminal display and the report.

### Step 6 — Display Findings in Terminal

Print findings using the Terminal Display Format defined below. This step happens BEFORE the cache update and report generation, so the user sees results immediately.

### Step 7 — Update Cache

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/cache-update.sh"
```

Persist all findings and current file hashes before generating the report. This ensures `/audit:report` can read findings from the cache.

### Step 8 — Write AUDIT_REPORT.md

Invoke the `/audit:report` command to write `AUDIT_REPORT.md` to the project root. This ensures the report uses the same structured format (derived titles, grouping rules, blockquote locations, severity emojis, summary table) as the incremental audit.

**Important**: The report MUST include severity emojis (🔴, 🟠, 🟡, 🟢, ℹ️) on all section headings and in the summary table. Never omit emojis.

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
  Files: N (full scan, cache bypassed)

  AUDIT_REPORT.md written to project root.

  Next steps:
    1. Fix N Critical findings before deploy       (if any Critical)
    2. Address N High findings before next release (if any High)
    3. Schedule Medium findings for this sprint    (if any Medium)
```

Omit next-steps lines for severity levels with zero findings.
