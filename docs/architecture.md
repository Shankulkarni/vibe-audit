# vibeAudit — Architecture

Technical reference for the plugin structure, audit flow, caching layers, and stack detection.

---

## Plugin Structure

```
vibeAudit/
├── .claude-plugin/
│   └── plugin.json                   # name, version, description
│
├── CLAUDE.md                         # Audit output format + skill routing table
│
├── skills/                           # 10 on-demand audit skills (loaded only when relevant)
│   ├── audit-vibecode-patterns/
│   ├── audit-llm-prompt-injection/
│   ├── audit-supabase-rls/
│   ├── audit-nextjs-server-actions/
│   ├── audit-react-xss/
│   ├── audit-react-native-secure-storage/
│   ├── audit-typescript-any-escape/
│   ├── audit-node-api-auth/
│   ├── audit-stripe-integration/
│   └── audit-vercel-deployment/
│
├── agents/
│   ├── audit-orchestrator.md         # Detects stack → loads skills → drives audit → collects report
│   ├── audit-security-reviewer.md    # Deep: auth, injection, secrets, crypto
│   ├── audit-quality-reviewer.md     # Patterns: error handling, dead code, AI slop
│   └── audit-performance-reviewer.md # Queries, bundle, memoization, re-renders
│
├── commands/
│   ├── audit.md                      # /audit — full incremental audit
│   ├── audit-full.md                 # /audit:full — repomix pack, bypass cache
│   ├── audit-quick.md                # /audit:quick — bash grep scan only (~5s)
│   ├── audit-security.md             # /audit:security — security reviewer only
│   └── audit-report.md               # /audit:report — write AUDIT_REPORT.md
│
└── scripts/
    ├── setup.sh / teardown.sh
    ├── detect-stack.sh               # Reads package.json → emits stack flags
    ├── quick-scan.sh                 # Tier 1: grep for 50+ vibecode patterns
    ├── find-secrets.sh               # Hardcoded keys, .env values in source
    ├── build-index.sh                # agent-analyzer OR lightweight fallback
    ├── cache-check.sh                # git diff + hash check → files to audit
    ├── cache-update.sh               # Persist new findings + update state
    └── pack-context.sh               # repomix focused pack for full-audit mode
```

---

## Three-Phase Audit Flow

```
/audit
  │
  ├─ Phase 1 — Discovery (bash, ~5s, 0 AI tokens)
  │   build-index.sh    → update repo index (incremental via git)
  │   cache-check.sh    → git diff + hash check → list of files to audit vs. cached
  │   detect-stack.sh   → which skills to load (only relevant ones)
  │   quick-scan.sh     → grep 50+ patterns → raw hits with file + line
  │
  ├─ Phase 2 — Deep Analysis (Claude + skills, ~2–5 min)
  │   Load skills        → Anthropic cache hit on repeat runs
  │   Read changed files → guided by index.json, not blindly scanning
  │   Classify findings  → severity, category, file, line, fix suggestion
  │   Filter false positives from Phase 1 grep hits
  │
  └─ Phase 3 — Report
      Merge new findings + cached findings from unchanged files
      Write AUDIT_REPORT.md
      cache-update.sh → persist hashes + state.json
```

---

## Stack Detection

`detect-stack.sh` reads `package.json` and emits stack flags that control which skills load:

```
package.json dep        →  skill loaded
──────────────────────────────────────────────────────
"next"                  →  audit-nextjs-server-actions
"react-native"          →  audit-react-native-secure-storage
"@supabase/supabase-js" →  audit-supabase-rls
"stripe"                →  audit-stripe-integration
"openai" / "anthropic"  →  audit-llm-prompt-injection

Always loaded:
  audit-vibecode-patterns
  audit-typescript-any-escape
  audit-react-xss
  audit-node-api-auth
```

---

## Caching Architecture

Five layers keep token costs flat across repeat runs.

### Layer 1 — Repo Index

Builds a compact symbol map: file paths, imports, exports, line counts. Tells Claude what's in each file without reading them all.

- **Primary**: `agent-analyzer repo-intel update` — git-commit-hash incremental, processes only new commits
- **Fallback**: lightweight `build-index.sh` using `find` + `grep` + `jq` — no binary dependency

```json
// .claude/vibeaudit/index.json
{
  "gitCommit": "abc123",
  "files": {
    "src/app/api/webhooks/route.ts": {
      "imports": ["stripe", "next/server"],
      "exports": ["POST"],
      "lines": 67
    }
  }
}
```

### Layer 2 — Findings Cache

Per-file audit results keyed by content hash. Unchanged files return cached findings at zero token cost.

```json
// .claude/vibeaudit/findings-cache.json
{
  "src/app/api/webhooks/route.ts": {
    "hash": "sha256:e3b0c44...",
    "auditedAt": "2026-05-01T12:00:00Z",
    "skills": ["audit-stripe-integration"],
    "findings": [
      {
        "severity": "critical",
        "category": "Security",
        "line": 23,
        "message": "Missing Stripe signature verification",
        "fix": "const sig = headers.get('stripe-signature'); await stripe.webhooks.constructEventAsync(body, sig, process.env.STRIPE_WEBHOOK_SECRET)"
      }
    ]
  }
}
```

### Layer 3 — Git-Incremental Change Detection

Tracks the git commit of the last audit. On re-run, `git diff <lastAuditCommit> HEAD --name-only` identifies exactly which files changed. Cascade rule: if file A changes, all files that import A are also queued (via import graph from Layer 1).

```json
// .claude/vibeaudit/state.json
{
  "lastAuditCommit": "abc123...",
  "auditedAt": "2026-05-01T12:00:00Z",
  "stackDetected": ["nextjs", "supabase", "stripe"],
  "summary": { "critical": 2, "high": 4, "medium": 8 }
}
```

### Layer 4 — Anthropic Prompt Cache

Skills are static reference material. Loading them as early system context means Anthropic's prefix cache serves them at ~90% cost reduction after the first run.

```
Turn 1: [skills: ~15k tokens] + "Start audit"   → cache WRITE (~1.25× cost)
Turn 2: [skills: cache hit]   + file contents   → cache READ (~0.1× cost)
Turn 3: [skills: cache hit]   + more files      → cache READ (~0.1× cost)
```

### Layer 5 — Repomix Focused Pack (full-audit mode)

For `/audit:full`, repomix packs only relevant source files with tree-sitter compression (~70% token reduction vs. reading files individually).

```bash
bunx repomix \
  --include "src/**,app/**,server/**" \
  --ignore "**/*.test.*,node_modules" \
  --compress \
  --output .claude/vibeaudit/packed.xml
```

### Token Cost Summary (50-file Next.js + Supabase app)

| Run | Without caching | With all layers |
|-----|-----------------|-----------------|
| First run | ~120k tokens | ~35k tokens |
| Repeat run (3 files changed) | ~120k tokens | ~8k tokens |
| Repeat run (no changes) | ~120k tokens | ~1k tokens |

---

## Cache Files

| File | Purpose |
|------|---------|
| `.claude/vibeaudit/state.json` | Last audit commit, summary counts, stack detected |
| `.claude/vibeaudit/findings-cache.json` | Per-file findings keyed by content hash |
| `.claude/vibeaudit/index.json` | Repo symbol index (imports, exports, line counts) |
| `.claude/vibeaudit/packed.xml` | Repomix-compressed source (full-audit mode only) |

Do not edit these files manually.

---

## Finding Format

Every skill emits findings in this standardized format:

```
🔴 CRITICAL | Security | src/app/api/webhooks/stripe/route.ts:23
Missing Stripe signature verification — any HTTP request can spoof a payment event
Fix: const sig = headers.get('stripe-signature'); await stripe.webhooks.constructEventAsync(body, sig, process.env.STRIPE_WEBHOOK_SECRET)
```

### Severity Scale

| Emoji | Level | Meaning |
|-------|-------|---------|
| 🔴 | CRITICAL | Ship-blocker. Do not deploy until fixed. |
| 🟠 | HIGH | Fix before next release. Real exploit path exists. |
| 🟡 | MEDIUM | Fix this sprint. Low-effort attack or data leak. |
| 🟢 | LOW | Fix when convenient. Best practice gap. |
| ℹ️ | INFO | Observation. No direct risk. May warrant a decision. |
