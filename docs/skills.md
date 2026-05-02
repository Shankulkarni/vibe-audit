# Audit Skills Reference

10 audit skills loaded based on your stack — only what's relevant.

## Skills

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

## Stack Detection

Skills load automatically based on your `package.json` dependencies:

| Dependency | Skill loaded |
|-----------|-------------|
| `next` | `audit-nextjs-server-actions` |
| `react-native` | `audit-react-native-secure-storage` |
| `@supabase/supabase-js` | `audit-supabase-rls` |
| `stripe` | `audit-stripe-integration` |
| `openai` / `anthropic` | `audit-llm-prompt-injection` |

**Always loaded** regardless of stack:
- `audit-vibecode-patterns`
- `audit-typescript-any-escape`
- `audit-react-xss`
- `audit-node-api-auth`
