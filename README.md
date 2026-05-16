# 🛡️ Vibe Audit: Production-grade checks for AI-generated code

[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://claude.ai/code)
[![Codex Plugin](https://img.shields.io/badge/Codex-Plugin-412991)](https://platform.openai.com/codex)
[![Gemini CLI Extension](https://img.shields.io/badge/Gemini_CLI-Extension-4285F4)](https://github.com/google-gemini/gemini-cli)
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

## 🚀 Install & Use

### Claude Code

**Step 1 — Install the plugin files:**

```bash
npx vibe-code-audit install
# Select "Claude Code" when prompted
```

**Step 2 — Open a project in Claude Code and run your first audit:**

```bash
/audit
```

That's it. The commands are copied to `~/.claude/commands/` and are available immediately — no restart needed.

> **Alternative:** Install via the Claude Code plugin marketplace instead:
> ```
> /plugin marketplace add Shankulkarni/claude-plugin-marketplace
> /plugin install vibeaudit@shankulkarni
> ```

---

### Gemini CLI

**Option 1 — via npm (recommended):**

```bash
npx vibe-code-audit install
# Select "Gemini CLI" when prompted
```

Skills and `AGENTS.md` are copied to `~/.gemini/gemini/extensions/vibeaudit/`. Open Gemini CLI and ask:

```
Run a vibeAudit security audit on this codebase.
```

**Option 2 — install directly from GitHub:**

```bash
gemini extension install Shankulkarni/vibe-audit
```

---

### Codex

**Step 1 — Install the plugin files:**

```bash
npx vibe-code-audit install
# Select "Codex" when prompted
```

Skills and `AGENTS.md` are copied to `~/.codex/Codex/plugins/vibeaudit/`. Codex has no slash commands — trigger the audit with a prompt:

```
Run a vibeAudit on this codebase. Follow the 7-step flow in AGENTS.md:
detect stack → check cache → quick scan → load skills → deep analysis → report → cache update.
```

---

### Manage your installation

| Command | What it does |
|---------|-------------|
| `npx vibe-code-audit install` | Install into Claude Code, Gemini CLI, Codex, or Cursor |
| `npx vibe-code-audit status` | Show which tools have vibeAudit installed and their version |
| `npx vibe-code-audit update` | Pull latest from npm and re-sync plugin files |
| `npx vibe-code-audit uninstall` | Remove vibeAudit from selected tools |

---

### 💻 Commands (Claude Code)

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
    <td align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/-%20-412991?logo=openai&logoColor=white&style=flat-square" /><img src="https://img.shields.io/badge/-%20-f0f0f0?logo=openai&logoColor=412991&style=flat-square" height="36" alt="OpenAI" /></picture><br /><b>OpenAI</b></td>
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
