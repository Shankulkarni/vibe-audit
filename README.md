# vibeAudit

> A Claude Code plugin that audits AI-generated ("vibecoded") apps for security, quality, performance, and compliance gaps — before they reach production.

---

## The Problem

AI coding assistants (Lovable, Bolt, v0, Cursor, Copilot) generate code that *looks right* but has systematic blind spots:

- Stripe webhooks wired up without signature verification
- Supabase tables created without Row Level Security policies
- Next.js Server Actions that skip authentication entirely
- React Native apps storing auth tokens in `AsyncStorage`
- TypeScript `any` types at every API boundary
- LLM apps that pass raw user input directly into prompts

These are not rare edge cases — they are the *default output* of AI code generators. vibeAudit catches them before they ship.

---

## What It Is

A **Claude Code plugin** bundling 10 audit skills, 4 specialist agents, and 5 slash commands. Installable in one command. Runs inside the same Claude Code environment developers already use.

Focused on the stacks AI tools generate most frequently:

`React` · `React Native` · `Next.js` · `TypeScript` · `Node.js` · `Supabase` · `PostgreSQL` · `Stripe` · `Vercel`

---

## Skill List

Ten audit skills, prioritized by demand and differentiation:

| # | Skill | Tier | What It Catches |
|---|-------|------|-----------------|
| 1 | `audit-vibecode-patterns` | AI-specific | Hardcoded URLs, mock data left in prod, exposed env vars, `console.log` with PII, copy-pasted `try/catch` swallowing errors, TODO comments referencing auth |
| 2 | `audit-llm-prompt-injection` | AI-specific | Unsanitized user input feeding LLM calls, missing system-prompt isolation, no output validation, exposed model API keys |
| 3 | `audit-supabase-rls` | Stack (high) | Missing RLS policies, `USING (true)` permissive policies, `service_role` key in client code, RLS bypass via security-definer RPC functions |
| 4 | `audit-nextjs-server-actions` | Stack (high) | Missing auth checks, unvalidated input, exposed internals, CSRF gaps, unauthenticated mutations |
| 5 | `audit-react-xss` | Stack (high) | `dangerouslySetInnerHTML` with user input, unsanitized URL handling (`href`, `src`), unsafe HTML rendering patterns |
| 6 | `audit-react-native-secure-storage` | Stack (high) | `AsyncStorage` for tokens/secrets, secrets in JS bundle, missing certificate pinning, unsafe deep link handling |
| 7 | `audit-typescript-any-escape` | Stack (high) | `any` types at API boundaries, untyped `fetch` responses, type assertions hiding real bugs, missing `strict` mode |
| 8 | `audit-node-api-auth` | Stack (high) | Unprotected routes, broken JWT verification, exposed admin endpoints, missing rate limiting |
| 9 | `audit-stripe-integration` | Stack (mid) | Missing webhook signature verification, customer ID leaks, missing idempotency keys, exposed secret keys |
| 10 | `audit-vercel-deployment` | Stack (mid) | Exposed env vars at build time, missing edge config, function timeout risks, source map exposure |

---

## Audit Dimensions

Each skill maps to one or more of the six standard audit dimensions:

| Dimension | Skills | What Gets Checked |
|-----------|--------|-------------------|
| **Security** | 1, 2, 3, 4, 5, 6, 8, 9 | Auth, injection, secrets, crypto, access control |
| **Quality** | 1, 7 | Error handling, dead code, AI slop patterns, type safety |
| **Performance** | 10 | Bundle size, edge config, function cold starts, query cost |
| **Compliance** | 3, 6, 9 | PCI-DSS (Stripe), App Store guidelines (RN), data access (Supabase) |
| **Documentation** | 1 | TODO/auth comments, undocumented security assumptions |
| **Testing** | 1 | Swallowed errors, untested auth paths, missing edge case coverage signals |

---

## Plugin Architecture

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
│   └── audit-report.md              # /audit:report — write AUDIT_REPORT.md
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

## Caching Architecture

Three-layer caching keeps token costs flat across repeat runs.

### Layer 1 — Repo Index

Builds a compact symbol map: file paths, imports, exports, line counts. Tells Claude *what's in each file* without reading them all.

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

Skills are static reference material. Loading them as early system context means Anthropic's prefix cache serves them at ~90% cost reduction after the first run. Claude Code's own architecture achieves 92% prefix reuse this way — vibeAudit uses the same pattern.

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

### Token Cost Comparison (50-file Next.js + Supabase app)

| Run | Without caching | With all layers |
|-----|-----------------|-----------------|
| First run | ~120k tokens | ~35k tokens |
| Repeat run (3 files changed) | ~120k tokens | ~8k tokens |
| Repeat run (no changes) | ~120k tokens | ~1k tokens |

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

## Finding Format

Every skill emits findings in this standardized format so the orchestrator can aggregate across skills:

```
🔴 CRITICAL | Security | src/app/api/webhooks/stripe/route.ts:23
Missing Stripe signature verification — any HTTP request can spoof a payment event
Fix: const sig = headers.get('stripe-signature'); await stripe.webhooks.constructEventAsync(body, sig, process.env.STRIPE_WEBHOOK_SECRET)
```

Severity scale: `🔴 Critical` (ship-blocker) → `🟠 High` → `🟡 Medium` → `🟢 Low` → `ℹ️ Info`

---

## Stack Detection

`detect-stack.sh` reads `package.json` and emits stack flags that control which skills load:

```
package.json dep       →  skill loaded
─────────────────────────────────────────────────────
"next"                 →  audit-nextjs-server-actions
"react-native"         →  audit-react-native-secure-storage
"@supabase/supabase-js"→  audit-supabase-rls
"stripe"               →  audit-stripe-integration
"openai" / "anthropic" →  audit-llm-prompt-injection

Always loaded:
  audit-vibecode-patterns
  audit-typescript-any-escape
  audit-react-xss
  audit-node-api-auth
```

---

## What Can Be Reused from Existing Repos

Research across the Claude Code skill ecosystem found the following reusable foundations:

### Strong coverage — reuse or wrap

| Area | Repo | What to Reuse |
|------|------|---------------|
| Supabase RLS | [yoanbernabeu/supabase-pentest-skills](https://github.com/yoanbernabeu/supabase-pentest-skills) | 24 dedicated skills: `supabase-audit-rls`, `supabase-audit-rpc`, `supabase-audit-auth-*`, key extraction, reporting. vibeAudit wraps these in an audit-mode orchestrator (not pentest mode). |
| Supabase (official) | [supabase/agent-skills](https://github.com/supabase/agent-skills) | Official RLS troubleshooting + migration patterns |
| Code quality dimensions | [levnikolaevich/claude-code-skills](https://github.com/levnikolaevich/claude-code-skills) | 9 parallel auditors: security, build errors, DRY/KISS, complexity, dead code, observability, concurrency, lifecycle, dependencies. Reference for the quality dimension structure. |
| Static analysis | [trailofbits/skills](https://github.com/trailofbits/skills) | `insecure-defaults`, `static-analysis` (CodeQL + Semgrep), `sharp-edges`, `supply-chain-risk-auditor` |
| Repo index | [agent-sh/agent-analyzer](https://github.com/agent-sh/agent-analyzer) | Rust binary — git-incremental symbol index. Already used by dotclaude. |
| Repo packing | [yamadashy/repomix](https://github.com/yamadashy/repomix) | Tree-sitter compression, ~70% token reduction. Used for `/audit:full` mode. |

### Partial coverage — reference patterns, build new skill

| Area | Repo | What to Reference | What vibeAudit Adds |
|------|------|-------------------|---------------------|
| General security patterns | [raroque/vibe-security-skill](https://github.com/raroque/vibe-security-skill) | 9 detection categories, stack-aware loading pattern | AI-slop specific patterns, quality + documentation angle |
| Stripe webhook implementation | [hookdeck/webhook-skills](https://github.com/hookdeck/webhook-skills) | Correct implementation patterns for Express/Next.js/FastAPI | *Audit* mode: scan existing code for the gaps |
| RN performance | [callstackincubator/agent-skills](https://github.com/callstackincubator/agent-skills) | JS/Native/bundle performance optimization | Secure storage, token handling, deep link audit |
| OWASP Mobile | [senaiverse/claude-code-reactnative-expo-agent-system](https://github.com/senaiverse/claude-code-reactnative-expo-agent-system) | OWASP Mobile Top 10 checklist | Tight RN-specific patterns: `AsyncStorage`, `SecureStore`, Expo deep links |
| Node.js OWASP | [netresearch/security-audit-skill](https://github.com/netresearch/security-audit-skill) | 80+ OWASP checkpoints (PHP-focused) | Node.js/Express/Hono version with JWT + middleware patterns |
| Compliance framework | [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents), [rohitg00/awesome-claude-code-toolkit](https://github.com/rohitg00/awesome-claude-code-toolkit) | Regulatory audit structure | PCI-DSS for Stripe, GDPR for Supabase, App Store for RN |

### Clear gaps — build from scratch

| Skill | Why No Existing Coverage |
|-------|--------------------------|
| `audit-typescript-any-escape` | TypeScript strict *coding* skills exist; no skill that specifically hunts `any` escape patterns at API/fetch boundaries |
| `audit-nextjs-server-actions` | Existing Next.js skills are dev guides (how to build); no security *audit* of Server Actions |
| `audit-llm-prompt-injection` (user apps) | Existing prompt-guard skills audit Claude *skills themselves*; nothing audits user-built LLM apps |
| `audit-vercel-deployment` | Generic deployment audit exists; nothing Vercel-specific (env leak at build, edge config, source maps) |

---

## Comparison with Similar Tools

| Tool | Type | Focus | vibeAudit difference |
|------|------|--------|----------------------|
| [raroque/vibe-security-skill](https://github.com/raroque/vibe-security-skill) | Skill | Security only | Adds quality, perf, compliance; AI-slop patterns; caching |
| [yoanbernabeu/supabase-pentest-skills](https://github.com/yoanbernabeu/supabase-pentest-skills) | Skills | Supabase pentesting | Multi-stack; audit mode not pentest mode |
| [trailofbits/skills](https://github.com/trailofbits/skills) | Skills | Crypto/blockchain/smart contracts | Vibecoded web app stacks; developer-friendly output |
| [levnikolaevich/claude-code-skills](https://github.com/levnikolaevich/claude-code-skills) | Skills | General code quality | Vibecode-specific patterns; caching; stack-aware loading |
| GitHub Actions security scanners | CI/CD | Static analysis | Developer-first; works in Claude Code; explains + fixes |

---

## Build Roadmap

| Phase | What | Output |
|-------|------|--------|
| **1** | Plugin shell: `plugin.json`, `CLAUDE.md`, `detect-stack.sh` | Installable plugin, stack detection works |
| **2** | `quick-scan.sh` + `audit-vibecode-patterns` skill | First working audit, zero-dependency |
| **3** | Caching layer: `build-index.sh`, `cache-check.sh`, `cache-update.sh` | Incremental runs, token cost drops |
| **4** | `audit-supabase-rls` (wrap supabase-pentest-skills) + `audit-nextjs-server-actions` | Highest-demand stacks covered |
| **5** | `audit-orchestrator` agent + `/audit` command | Full wired flow |
| **6** | Remaining 7 skills | Full skill coverage |
| **7** | `/audit:report`, `setup.sh`, plugin marketplace listing | Distribution-ready |

---

## Installation (target UX)

```bash
# Add the marketplace source
claude plugin marketplace add vibeaudit/claude-toolkit

# Install
claude plugin install vibeaudit

# One-time setup
/vibeaudit:setup

# Run your first audit
/audit
```

---

## Inspired By

- [dotclaude](https://github.com/harryy2510/claude-toolkit) — plugin architecture and conventions pattern
- [agent-sh/agent-analyzer](https://github.com/agent-sh/agent-analyzer) — git-incremental repo indexing
- [yamadashy/repomix](https://github.com/yamadashy/repomix) — token-efficient repo packing
- [aider repo map](https://aider.chat/docs/repomap.html) — graph-ranked symbol indexing
- [Anthropic Claude Code caching](https://blog.lmcache.ai/en/2025/12/23/context-engineering-reuse-pattern-under-the-hood-of-claude-code/) — 92% prefix reuse architecture
- [sapient.pro audit framework](https://sapient.pro/blog/how-to-conduct-a-code-quality-audit) — six audit dimensions
