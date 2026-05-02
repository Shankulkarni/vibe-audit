# Vibe Audit

> A Claude Code plugin that audits AI-generated ("vibecoded") apps for security, quality, performance, and compliance gaps - before they reach production.

**OWASP Top 10:2025** · **ASVS 5.0** · **PCI-DSS** · **App Store Guidelines** · **AI-Specific Patterns**

---

AI coding assistants generate code that *looks right* but has systematic blind spots. These are not rare edge cases - they are the **default output** of AI code generators:

- Stripe webhooks with no signature verification
- Supabase tables with no Row Level Security
- Next.js Server Actions that skip auth entirely
- React Native apps storing tokens in `AsyncStorage`
- `any` types at every API boundary
- LLM apps passing raw user input directly into prompts
- Insecure defaults, supply chain risks, and agentic AI safety gaps

vibeAudit catches them before they ship.

---

## What It Is

A **Claude Code plugin** bundling 10 audit skills, 4 specialist agents, and 5 slash commands. Runs inside the Claude Code environment developers already use - no new tools to learn.

Covers the stacks AI tools generate most frequently:

`React` · `React Native` · `Next.js` · `TypeScript` · `Node.js` · `Supabase` · `Stripe` · `Vercel`

---

## Coverage

Audits against industry standards and AI-specific patterns:

| Standard | What It Covers |
|----------|----------------|
| **OWASP Top 10:2025** | Injection, broken auth, SSRF, security misconfiguration, cryptographic failures |
| **OWASP ASVS 5.0** | Application Security Verification Standard - auth, session, access control, validation |
| **PCI-DSS** | Payment data handling, Stripe webhook verification, secret key exposure |
| **App Store Guidelines** | Secure storage, certificate pinning, deep link validation (React Native) |
| **AI-Specific Patterns** | Prompt injection, insecure defaults from code generators, mock data left in prod, agentic safety |
| **Supply Chain** | Dependency risks, lockfile integrity, typosquatting signals |

## Audit Dimensions

Every finding is tagged with one of six dimensions:

| Dimension | What Gets Checked |
|-----------|-------------------|
| **Security** | Auth, injection, secrets, crypto, access control |
| **Quality** | Error handling, dead code, AI slop patterns, type safety |
| **Performance** | Bundle size, edge config, function cold starts, query cost |
| **Compliance** | PCI-DSS (Stripe), App Store guidelines (RN), data access (Supabase) |
| **Documentation** | TODO/auth comments, undocumented security assumptions |
| **Testing** | Swallowed errors, untested auth paths, missing edge case coverage signals |

---

## Findings Look Like This

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━  🔴 CRITICAL  ━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [Security]  src/app/api/webhooks/stripe/route.ts:23
  Missing Stripe signature verification — any HTTP request can spoof a payment event
  Fix → const sig = headers.get('stripe-signature')
         await stripe.webhooks.constructEventAsync(body, sig, env.STRIPE_WEBHOOK_SECRET)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Audit Summary
  ┌────────────────┬───────┐
  │ 🔴  Critical   │   1   │
  │ 🟠  High       │   3   │
  │ 🟡  Medium     │   5   │
  │ 🟢  Low        │   8   │
  │ ℹ️   Info       │   2   │
  ├────────────────┼───────┤
  │    Total       │  19   │
  └────────────────┴───────┘
```

Severity scale: `🔴 Critical` (ship-blocker) → `🟠 High` → `🟡 Medium` → `🟢 Low` → `ℹ️ Info`

---

## Skills

10 audit skills loaded based on your stack - only what's relevant:

| Skill | What It Catches |
|-------|-----------------|
| `audit-vibecode-patterns` | Hardcoded URLs, mock data in prod, exposed env vars, PII in logs, swallowed errors, insecure defaults |
| `audit-llm-prompt-injection` | Unsanitized user input in LLM calls, missing system-prompt isolation, agentic action safety gaps |
| `audit-supabase-rls` | Missing RLS policies, permissive `USING (true)`, `service_role` in client code, RPC bypass, storage bucket exposure |
| `audit-nextjs-server-actions` | Missing auth checks, unvalidated input, CSRF gaps, OWASP Top 10 violations in server actions |
| `audit-react-xss` | `dangerouslySetInnerHTML` with user input, unsafe URL handling, OWASP injection patterns |
| `audit-react-native-secure-storage` | Tokens in `AsyncStorage`, secrets in JS bundle, unsafe deep links, certificate pinning |
| `audit-typescript-any-escape` | `any` at API boundaries, untyped fetch responses, missing `strict` mode |
| `audit-node-api-auth` | Unprotected routes, broken JWT verification, OWASP auth/access control, missing rate limiting |
| `audit-stripe-integration` | Missing webhook signature verification, exposed secret keys, PCI-DSS compliance gaps |
| `audit-vercel-deployment` | Env vars leaked at build time, source map exposure, function timeout risks |

Skills for `next`, `react-native`, `supabase`, `stripe`, `openai`/`anthropic` load automatically based on your `package.json`. Four skills always load regardless of stack.

---

## Quick Start

```
# Add the marketplace source
/plugin marketplace add Shankulkarni/claude-plugin-marketplace

# Install the plugin
/plugin install vibeaudit@shankulkarni

# Restart Claude Code to load the plugin
# Then run your first audit
/audit
```

### Commands

| Command | What It Does                                                          |
|---------|-----------------------------------------------------------------------|
| `/audit` | Full incremental audit - only re-audits changed files                 |
| `/audit:quick` | Bash grep scan only, ~5s, no AI tokens. Results marked `[UNVERIFIED]` |
| `/audit:full` | Full re-audit of every file, bypasses cache                           |
| `/audit:security` | Security dimension only - faster and more focused                     |
| `/audit:report` | Write findings to `AUDIT_REPORT.md`                                   |

---

## How It Works

Three phases run in order:

1. **Discovery** - bash scripts detect your stack, build a file index, and grep for 50+ known patterns (~5s, zero AI tokens)
2. **Deep Analysis** - Claude loads only the relevant skills, reads changed files, classifies findings with severity and a concrete fix
3. **Report** - merges new findings with cached results from unchanged files, writes the report, persists state

Repeat runs only re-audit files that changed. A 50-file app typically costs ~8k tokens on the second run vs ~120k without caching.

For a detailed look at the architecture, caching layers, and plugin structure, see [docs/architecture.md](docs/architecture.md).

---
