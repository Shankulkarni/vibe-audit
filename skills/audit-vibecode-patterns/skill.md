---
name: audit-vibecode-patterns
description: Catch AI-specific slop patterns that code generators systematically produce
triggers: [vibecode, ai-generated, scaffold, copilot, cursor, chatgpt, codegen, slop]
---

# Audit: Vibe Code Patterns

## Purpose

AI code generators produce a recognizable class of mistakes. They confidently write code that looks complete but contains structural holes: swallowed errors, leftover scaffolding, hardcoded values that were supposed to be replaced, and dead code from iterative generation. This skill finds those patterns before they reach production.

The riskiest AI slop is invisible at a glance — it compiles, it runs, and it fails silently or dangerously under real conditions.

## What to Look For

### Hardcoded URLs

Scan all string literals for URLs that should not be in source code:

- `localhost` or `127.0.0.1` in any non-test, non-dev-server file
- Staging URLs: strings containing `staging.`, `-staging`, `.staging`, `stg.`, `-stg`
- Hardcoded production URLs in config files or constants that should read from env: `https://api.myapp.com` as a raw string literal

```ts
// Flag this:
const API_URL = 'https://api.myapp.com/v2'
const BASE = 'http://localhost:3001'

// Not this (acceptable):
const DEV_ONLY_URL = process.env.NODE_ENV === 'development' ? 'http://localhost:3000' : ''
```

### Mock / Stub / Fake Data Outside Test Files

- Variables named `mockData`, `fakeData`, `stubData`, `dummyData`, `testData`, `sampleData`
- Constants with `MOCK_` prefix
- Arrays of fake users, fake products, fake orders inline in component or route files
- `faker.js` imports outside `*.test.*`, `*.spec.*`, `__tests__/`, `__mocks__/`, `fixtures/`

### Exposed Environment Variables in Client-Side Code

- `process.env.SECRET_KEY`, `process.env.DATABASE_URL`, `process.env.JWT_SECRET` accessed in files that run in the browser
- In Next.js: non-`NEXT_PUBLIC_` env vars in page/component files are server-safe — but verify they are actually server components
- In Vite: `import.meta.env.VITE_SECRET` where the variable name suggests it is private

### console.log with PII or Sensitive Data

Scan `console.log`, `console.info`, `console.debug`, `console.warn` calls for argument patterns that include:

- `token`, `password`, `secret`, `key`, `credential`, `auth`
- `email`, `ssn`, `phone`, `dob`, `dateOfBirth`, `creditCard`, `cardNumber`
- `req.body`, `req.headers`, `request.body` logged wholesale
- User objects logged entirely: `console.log(user)` where `user` likely contains PII fields

### PII Sent to External LLM APIs

When user PII (personally identifiable information) flows into an external LLM API call, you are sending sensitive data to a third party — potentially violating GDPR, CCPA, HIPAA, and your own privacy policy. AI code generators frequently wire user data directly into prompts without any consideration for data minimisation.

```ts
// Flag: CRITICAL — government IDs sent to external LLM
await openai.chat.completions.create({
  messages: [{ role: 'user', content: `Process this: SSN ${user.ssn}` }],
})
await anthropic.messages.create({
  messages: [{ role: 'user', content: user.nationalId }],
})

// Flag: CRITICAL — financial data sent to external LLM
messages.push({ role: 'user', content: `Card: ${user.creditCardNumber}` })
messages.push({ role: 'user', content: `Bank account: ${user.iban}` })

// Flag: HIGH — full user object with PII fields sent to LLM
const response = await llm.complete({ context: JSON.stringify(user) })  // user has .email, .phone, .dob

// Flag: HIGH — health or biometric data sent to external LLM
await openai.chat.completions.create({
  messages: [{ role: 'user', content: patient.medicalHistory }],
})

// Flag: MEDIUM — email or phone in prompt without necessity
const response = await llm.complete(`Send a welcome message to ${user.email}`)
// Is the email actually needed in the prompt, or just the first name?

// Flag: MEDIUM — LLM response containing PII stored unencrypted
const reply = await llm.complete(prompt)
await db.insert('conversations', { userId, content: reply })  // reply may echo back PII, stored plaintext
```

Look for: user field accesses (`.ssn`, `.email`, `.phone`, `.dob`, `.dateOfBirth`, `.creditCard`, `.cardNumber`, `.iban`, `.passport`, `.nationalId`, `.medicalHistory`, `.diagnosis`) appearing inside LLM `messages` arrays, prompt template strings, or context objects passed to AI SDK functions (`generateText`, `streamText`, `complete`, `chat`).

### Swallowed Errors — Empty or Log-Only Catch Blocks

```ts
// Flag: empty catch
try { ... } catch (e) {}

// Flag: catch that only logs and continues as if nothing happened
try {
  await chargeCustomer(amount)
} catch (e) {
  console.error(e) // no rethrow, no return, no error state set
}

// Flag: catch that returns undefined/null silently
try { ... } catch { return null }
```

Look for catch blocks where:
1. No error is re-thrown
2. No error state is set
3. No meaningful fallback is executed
4. Execution continues as if the try succeeded

### TODO/FIXME/HACK Comments Referencing Security-Sensitive Areas

Search for comment patterns:

```
// TODO.*auth
// FIXME.*auth
// TODO.*payment
// HACK.*permission
// TODO.*security
// TODO.*implement.*auth
// TODO: add authorization
```

Flag any TODO/FIXME/HACK that touches: auth, authorization, permissions, payment, billing, security, validation, encryption, token.

### Dead Code Markers

- Commented-out `console.log` lines: `// console.log(`
- Commented-out code blocks of 3+ lines
- Unreachable code after `return`, `throw`, `break`, or `continue`
- Unused imports: `import { Foo } from './foo'` where `Foo` never appears in the file body
- Variables declared but never read

### AI Scaffolding Markers — Unimplemented Function Bodies

```ts
// Flag these:
function processPayment(amount: number) {
  throw new Error('Not implemented')
}

async function sendEmail(to: string) {
  // TODO: implement
}

function validateUser(user: User) {
  return true // placeholder
}
```

Functions whose entire body is: a `throw new Error('Not implemented')`, a lone `// TODO: implement` comment, or an unconditional `return true`/`return null` with a comment indicating it is placeholder.

### Hardcoded Credentials

Scan string literals for patterns that resemble real secrets:

- Strings starting with known key prefixes: `sk_live_`, `sk_test_`, `pk_live_`, `rk_`, `ghp_`, `xoxb-`, `AIza`, `AKIA`
- Strings of 32+ characters that are hex or base64 assigned to variables named `key`, `secret`, `password`, `token`, `apiKey`
- Passwords as string literals: `password = 'hunter2'`, `const DB_PASS = 'mypassword123'`

### eval() and Function() Constructor

Any usage of:
- `eval(`
- `new Function(`
- `setTimeout(string,` or `setInterval(string,` — string-based timer callbacks execute as eval

### Suppressed Linter Rules Without Justification

AI generators frequently silence type errors and lint warnings rather than fix them. Flag these patterns when there is no accompanying comment explaining the suppression:

```ts
// Flag: blanket file-level suppression
// @ts-nocheck

// Flag: ts-ignore without reason
// @ts-ignore
const result = dangerousOperation()

// Acceptable: ts-ignore with a real reason
// @ts-ignore: third-party type definition is wrong, upstream issue #1234
const result = dangerousOperation()

// Flag: eslint-disable without reason
/* eslint-disable no-explicit-any */
/* eslint-disable-next-line @typescript-eslint/no-unsafe-call */

// Flag: noqa without code or reason (Python/other mixed toolchains)
```

Patterns to grep: `@ts-nocheck`, `@ts-ignore(?!\s*:)`, `eslint-disable(?!\s.*--\s)`.

### Placeholder Text in User-Facing Content

```ts
// Flag: lorem ipsum left in production strings
const description = 'Lorem ipsum dolor sit amet...'
const placeholder = 'test test test'
const message = 'Replace this with actual content'
const title = 'TODO: replace with real title'
```

Not a security issue but a signal that the file was AI-scaffolded and not reviewed. Any placeholder text outside test/fixture files should be flagged as Info.

### Inconsistent Error Handling Within the Same Function

A function that has multiple code paths where some throw, some return `null`, and some return `undefined` or swallow errors — with no documented reason for the difference.

```ts
// Flag: inconsistent within the same function
async function getUser(id: string) {
  if (!id) return null           // silent null
  try {
    const user = await db.find(id)
    if (!user) throw new Error('Not found')  // throws
    return user
  } catch (e) {
    console.log(e)               // swallows
    return undefined             // silent undefined
  }
}
```

## Severity Classification

**Critical**
- Hardcoded live API keys or secrets in source (any `sk_live_`, `AKIA`, or similar prefix)
- Unimplemented function bodies in auth, payment, or permission-critical paths
- Government IDs (SSN, passport, national ID) or financial data (credit card, IBAN) sent to external LLM APIs

**High**
- `console.log` with PII (tokens, passwords, emails, full user objects)
- TODO comments referencing auth or payment as unimplemented
- Exposed non-public env vars in client-side code
- Swallowed errors in payment, auth, or data-integrity paths
- Full user objects with PII fields passed to external LLM API calls
- Health, medical, or biometric data sent to external LLM APIs
- LLM conversation responses containing PII stored in plaintext (no encryption)

**Medium**
- Mock/fake data variables outside test files
- Empty catch blocks in non-critical paths
- Inconsistent error handling patterns
- `eval()` or `new Function()` usage
- `@ts-ignore` or `eslint-disable` without a reason comment

**Low**
- Hardcoded localhost URLs (dev only)
- Dead code: commented-out console.logs, unused imports
- Unreachable code
- TODO/FIXME comments on non-security concerns
- `@ts-nocheck` at file level (suppress entirely rather than fix)
- Placeholder text in user-facing strings

## Finding Format

```
🔴 CRITICAL | Hardcoded Secret | src/lib/stripe.ts:12
String literal matches live Stripe secret key pattern (sk_live_...).
Fix: Remove from source. Use process.env.STRIPE_SECRET_KEY and add to .env (gitignored).

🔴 CRITICAL | Unimplemented Auth | src/api/payments/route.ts:34
Function 'authorizePayment' body is 'throw new Error("Not implemented")' — called in payment flow.
Fix: Implement authorization logic before this route handles real traffic.

🟠 HIGH | PII in Console | src/hooks/useAuth.ts:67
console.log(user) logs full user object including email and session token.
Fix: Remove or replace with console.log(user.id) for non-sensitive identifier only.

🟠 HIGH | Swallowed Error | src/services/billing.ts:89
catch block in chargeCustomer() only calls console.error — no rethrow, no error state.
Fix: Re-throw or set error state so callers know the charge failed.

🟡 MEDIUM | Mock Data in Production | src/components/Dashboard.tsx:15
mockUsers array with fake data imported directly into production component.
Fix: Move to __mocks__/ or remove. Fetch real data from API.

🟡 MEDIUM | Empty Catch | src/utils/cache.ts:44
try/catch with empty catch block silently swallows cache write failures.
Fix: At minimum log the error. Consider propagating if callers need to know.

🔵 LOW | Dead Import | src/pages/profile.tsx:3
'import { formatDate } from ../utils/date' — formatDate is never used in this file.
Fix: Remove the import.

🔴 CRITICAL | SSN Sent to External LLM | src/lib/document-processor.ts:31
user.ssn is interpolated directly into an OpenAI prompt. Government ID is transmitted to a third-party API, violating data minimisation requirements.
Fix: Remove PII from the prompt. Use only non-sensitive identifiers (user ID) and process sensitive data server-side without sending it to an LLM.

🟠 HIGH | Full User Object in LLM Context | src/agents/support-agent.ts:18
JSON.stringify(user) is passed as LLM context, sending email, phone, and dateOfBirth to the external API.
Fix: Pass only the fields the LLM needs for the task (e.g., { name: user.name, accountTier: user.tier }). Never serialize entire user records into prompts.

🟠 HIGH | LLM Response Stored Plaintext | src/services/chat-history.ts:55
LLM reply is stored in the conversations table without encryption. Replies may echo back user PII (email, addresses) in plaintext.
Fix: Encrypt conversation content at rest. Use column-level encryption or a KMS-backed encryption layer before inserting.

🟡 MEDIUM | Suppressed Type Error | src/api/payment.ts:18
// @ts-ignore on the line before a Stripe call with no explanation. Type errors on payment code must be understood, not silenced.
Fix: Resolve the underlying type mismatch. If the suppression is genuinely needed, add a comment: // @ts-ignore: stripe types outdated, see issue #42

ℹ️ INFO | Placeholder Text | src/components/Hero.tsx:7
description = 'Lorem ipsum dolor sit amet...' — placeholder text in a production component.
Fix: Replace with real content before shipping.
```

## Common False Positives

Do NOT flag:
- `mockData`, `fakeData`, etc. inside `*.test.*`, `*.spec.*`, `__tests__/`, `__mocks__/`, `fixtures/`, `*.stories.*`
- `localhost` inside `devServer`, `vite.config`, webpack config, or jest config
- `throw new Error('Not implemented')` in abstract base class stubs that are documented as requiring override
- `console.log` in files that are explicitly dev-only scripts (not in `src/`)
- `eval` in test runner configuration files
- Commented-out code in migration files (historical context)
- LLM calls that pass `user.email` where email is the explicit task subject (e.g., an email composition feature that drafts a message *to* a user — the email address is necessary)
- Self-hosted or on-premise LLM endpoints (Ollama, private inference servers) — data doesn't leave your infrastructure; still flag if PII handling is otherwise sloppy

## Stack-Specific Notes

**Next.js**: `process.env.DATABASE_URL` in a Server Component is safe — flag only if the file is a Client Component (`'use client'` directive) or could be statically bundled.

**React Native**: `console.log` in production builds is a real performance hit and a log-scraping vector on jailbroken devices — treat as High, not Low.

**Expo**: Watch for secrets in `app.json` / `app.config.js` — these are embedded in the app bundle.

**Vite**: `import.meta.env.VITE_` variables are always public (bundled into client). Any secret with a `VITE_` prefix is Critical.

**tRPC / GraphQL**: Unimplemented resolvers that return `null` without error are a variant of the scaffold marker pattern — flag them.
