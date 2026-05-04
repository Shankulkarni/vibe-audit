# 🛡️ Vibe Audit: Production-grade checks for AI-generated code

[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://claude.ai/code)
[![OWASP Top 10](https://img.shields.io/badge/OWASP-Top_10:2025-orange)](https://owasp.org/Top10/)
[![PCI-DSS](https://img.shields.io/badge/PCI--DSS-Compliant-blue)](https://www.pcisecuritystandards.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

> 🔍 Find security risks, scaling issues, and hidden bugs in AI-generated code before they hit production.

![Vibe Audit Pillars](vibe-audit-pillars-light.png#gh-dark-mode-only)
![Vibe Audit Pillars](vibe-audit-pillars.png#gh-light-mode-only)

A structured audit across the risks that actually break products:

- 🔐 **Security** — auth flaws, exposed secrets, injection risks, LLM prompt injection, RAG document injection, PII in AI calls, unsafe agent tool use
- ✅ **Quality** — dead code, weak typing, AI anti-patterns
- ⚡ **Performance** — slow queries, cold starts, heavy bundles
- 📋 **Compliance** — Stripe, App Store, data access risks
- 🧪 **Testing** — missing coverage in critical flows

Built specifically for AI-generated code, not generic linting.

---

## 🎯 See exactly what's wrong and where

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━  🔴 CRITICAL  ━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [Security]  src/app/api/webhooks/stripe/route.ts:23
  Missing Stripe signature verification — any HTTP request can spoof a payment event
  Fix → const sig = headers.get('stripe-signature')
         await stripe.webhooks.constructEventAsync(body, sig, env.STRIPE_WEBHOOK_SECRET)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- ✏️ Clear issue descriptions
- 🚦 Severity levels (critical, high, medium, low)
- 📍 Exact file and line references
- 🔧 Actionable fixes, not generic advice

**No vague suggestions. Only concrete problems you can fix.**


---

## 🚀 Quickstart

Run Vibe Audit in under a minute:

```bash
# Add the marketplace source
/plugin marketplace add Shankulkarni/claude-plugin-marketplace

# Install the plugin
/plugin install vibeaudit@shankulkarni

# Restart Claude Code to load the plugin
# Then run your first audit
/audit
```

### 💻 Commands

| Command | What It Does |
|---------|-------------|
| `/audit` | Full incremental audit — only re-audits changed files |
| `/audit:quick` | Bash grep scan, ~5s, no AI tokens. Results marked `[UNVERIFIED]` |
| `/audit:full` | Full re-audit of every file, bypasses cache |
| `/audit:security` | Security dimension only — faster and more focused |
| `/audit:ci` | CI gate — outputs JSON, exits `1` on Critical findings (blocks merge) |
| `/audit:report` | Write findings to `AUDIT_REPORT.md` |

---

## 🧰 Stacks supported

Audits the stacks AI tools generate most frequently:

<table>
  <tr>
    <td align="center"><img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/react/react-original.svg" width="36" /><br /><b>React</b></td>
    <td align="center"><img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/react/react-original.svg" width="36" /><br /><b>React Native</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/nextdotjs/ffffff" /><img src="https://cdn.simpleicons.org/nextdotjs/000000" width="36" alt="Next.js" /></picture><br /><b>Next.js</b></td>
    <td align="center"><img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/typescript/typescript-original.svg" width="36" /><br /><b>TypeScript</b></td>
  </tr>
  <tr>
    <td align="center"><img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nodejs/nodejs-original.svg" width="36" /><br /><b>Node.js</b></td>
    <td align="center"><img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/supabase/supabase-original.svg" width="36" /><br /><b>Supabase</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/stripe/ffffff" /><img src="https://cdn.simpleicons.org/stripe/635BFF" width="36" alt="Stripe" /></picture><br /><b>Stripe</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/vercel/ffffff" /><img src="https://cdn.simpleicons.org/vercel/000000" width="36" alt="Vercel" /></picture><br /><b>Vercel</b></td>
  </tr>
  <tr>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/openai/ffffff" /><img src="https://cdn.simpleicons.org/openai/412991" width="36" alt="OpenAI" /></picture><br /><b>OpenAI</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/anthropic/ffffff" /><img src="https://cdn.simpleicons.org/anthropic/D97757" width="36" alt="Anthropic" /></picture><br /><b>Anthropic</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/langchain/ffffff" /><img src="https://cdn.simpleicons.org/langchain/1C3C3C" width="36" alt="LangChain" /></picture><br /><b>LangChain</b></td>
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.simpleicons.org/vercel/ffffff" /><img src="https://cdn.simpleicons.org/vercel/000000" width="36" alt="AI SDK" /></picture><br /><b>AI SDK</b></td>
  </tr>
</table>

Skills load automatically based on your `package.json` — only what's relevant.

---

## 📚 Technical details

For architecture, caching layers, audit skills, and plugin internals:

- 🏗️ [Architecture & caching](docs/architecture.md)
- 🔎 [Audit skills reference](docs/skills.md)
- 📊 [Coverage & standards](docs/coverage.md)
