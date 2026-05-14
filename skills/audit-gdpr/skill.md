---
name: audit-gdpr
description: Audit codebase for GDPR compliance violations — PII in logs, missing consent gates, no delete-account flow, unacknowledged data processors, and cross-border transfer signals.
triggers: [gdpr, privacy, consent, cookie, personal-data, pii, dpa, data-protection, gdpr-compliance]
compliance:
  standard: GDPR
  region: EU
  version: "2018"
---

# Audit: GDPR Compliance

## Purpose

The General Data Protection Regulation (GDPR) applies to any app that processes personal data of EU residents — regardless of where the company is based. AI-generated apps routinely violate GDPR in detectable, structural ways: analytics fire before consent is captured, PII lands in server logs, there is no mechanism for users to delete their data, and third-party processors are used without acknowledgement. This skill finds those violations in source code.

**Key invariant:** Only surface a finding after reading the full file context. A grep hit for `console.log` near `email` is not automatically a finding — verify the value being logged is actual user PII and not a redacted/hashed string.

---

## Severity Classification

| Severity | GDPR Article | When to use |
|---|---|---|
| 🔴 CRITICAL | Art. 5(1)(f), Art. 6 | PII directly exposed; tracking fires before consent |
| 🟠 HIGH | Art. 13-14, Art. 17, Art. 7 | Required flows missing (privacy page, delete account, unchecked consent) |
| 🟡 MEDIUM | Art. 28, ePrivacy | Processors without DPA warning; cookies set with no consent lib |
| ℹ️ INFO | Art. 33, Art. 44-49 | No breach monitoring; US-region endpoints |

---

## What to Look For

### 🔴 CRITICAL — PII in Logs

Scan all `console.log`, `console.error`, `console.warn`, `console.info`, and `logger.*` calls.

**Flag when:** The call directly logs a PII field name or dumps a user object:

```ts
// Flag — email in log
console.log('Login attempt:', user.email)

// Flag — full user object dump
console.log('Auth state:', JSON.stringify(user))
console.error('Failed request:', req.user)

// Flag — spread into log
console.log({ userId, email, phone })
```

**Do NOT flag:**
```ts
// Acceptable — no PII field
console.log('User logged in:', user.id)

// Acceptable — redacted helper
console.log('Auth:', redactPII(user))

// Acceptable — test file
// (skip files matching *.test.*, *.spec.*, __tests__/)
```

**Article:** Art. 5(1)(f) — integrity and confidentiality

**Finding format:**
```
🔴 CRITICAL | GDPR Art. 5(1)(f) | src/lib/auth.ts:42
User email logged to console — personal data must not appear in application logs.
Fix: Remove console.log(user.email). If logging is needed for debugging, use a redaction helper:
     const safe = { ...user, email: '[redacted]', phone: '[redacted]' }
     console.log('Auth:', safe)
```

---

### 🔴 CRITICAL — Analytics / Tracking Loaded Before Consent

Scan for calls to analytics and tracking libraries that fire at module level or unconditionally inside `useEffect`/`useLayoutEffect`.

**Flag when:** The call is NOT wrapped in a consent condition:

```ts
// Flag — unconditional at module level
gtag('config', 'GA-XXXXXXXX')

// Flag — useEffect with no consent check
useEffect(() => {
  mixpanel.init('token')
  analytics.track('page_view')
}, [])

// Flag — loaded at app root without gate
hotjar.initialize(HJID, HJSV)
```

**Do NOT flag:**
```ts
// Acceptable — gated on consent
if (cookieConsent === 'accepted') {
  gtag('config', 'GA-XXXXXXXX')
}

// Acceptable — server-side analytics with no PII
// (e.g., Plausible, Fathom — verify the library is privacy-first)
```

**Patterns to check:** `gtag(`, `fbq(`, `mixpanel.init(`, `analytics.track(`, `_paq.push(`, `hotjar.initialize(`, `Intercom(`

**Article:** Art. 6 (no lawful basis without consent) + ePrivacy Directive

**Finding format:**
```
🔴 CRITICAL | GDPR Art. 6 | src/app/layout.tsx:18
Google Analytics initialized unconditionally — tracking fires before user consent is captured.
Fix: Wrap the gtag() call inside a consent check:
     if (userConsent.analytics) { gtag('config', 'GA-XXXXXXXX') }
     Use a consent management library (react-cookie-consent, cookieyes) to gate this.
```

---

### 🟠 HIGH — No Privacy Policy Route

Scan all route definitions (Next.js app/pages router, React Router, Express routes) for any path that contains: `privacy`, `privacy-policy`, `privacy-notice`, `datenschutz` (German), `mentions-legales` (French).

**Flag when:** No such route exists anywhere in the codebase.

**Also check:** Footer components for an outbound `<a href="...privacy...">` link to an externally hosted policy (Notion, Termly, Iubenda). If that link exists, do NOT flag.

**Article:** Art. 13-14 — information obligations

**Finding format:**
```
🟠 HIGH | GDPR Art. 13 | (no file — missing route)
No privacy policy page or link detected. GDPR Art. 13 requires informing users what data you collect, why, and how to exercise their rights before or at the point of collection.
Fix: Add a /privacy-policy route or a footer link to a hosted privacy policy. Tools: termly.io, iubenda.com, or write your own covering: data collected, purposes, retention periods, user rights (access, erasure, portability), contact details.
```

---

### 🟠 HIGH — No Delete-Account Flow

Scan for any of: `DELETE /user`, `DELETE /account`, `deleteUser(`, `deleteAccount(`, `DELETE /api/user`, `DELETE /api/account`, or UI text matching "delete account", "close account", "remove account".

**Flag when:** None of these patterns exist anywhere.

**Do NOT flag when:** `deactivate`, `anonymize`, or `archive` functions exist AND they demonstrably remove PII fields (set email/phone to null or anonymized values).

**Article:** Art. 17 — right to erasure

**Finding format:**
```
🟠 HIGH | GDPR Art. 17 | (no file — missing endpoint)
No delete-account endpoint or UI flow detected. Users have a right to erasure — they must be able to permanently delete their account and all associated personal data.
Fix: Implement DELETE /api/user (or equivalent) that hard-deletes or fully anonymizes the user record and all related PII. Add a "Delete Account" option in account settings UI. Consider a 30-day grace period with anonymization on day 30.
```

---

### 🟠 HIGH — Pre-Ticked Consent Checkbox

Scan for `defaultChecked={true}` or `checked={true}` (without a user-state variable) on inputs near consent-related labels.

**Flag when:** The surrounding JSX includes any of: `newsletter`, `marketing`, `consent`, `subscribe`, `terms`, `agree`, `accept`.

```tsx
// Flag — pre-ticked marketing consent
<input
  type="checkbox"
  name="newsletter"
  defaultChecked={true}
/>

// Acceptable — pre-ticked "remember me" (not consent)
<input type="checkbox" name="remember_me" defaultChecked={true} />

// Acceptable — controlled by user state
<input type="checkbox" checked={userPrefs.newsletter} onChange={...} />
```

**Article:** Art. 7 + Recital 32 — consent must be unambiguous (no pre-ticked boxes)

**Finding format:**
```
🟠 HIGH | GDPR Art. 7 | src/components/SignupForm.tsx:67
Newsletter checkbox is pre-ticked — consent must be given by a clear affirmative act. Pre-ticked boxes are explicitly invalid under GDPR Recital 32.
Fix: Set defaultChecked={false} (or remove the prop). The user must actively check the box.
```

---

### 🟡 MEDIUM — Third-Party Processor Without DPA Warning

Scan `import` statements and `require()` calls for known data processors.

**Vendors to detect and their DPA link:**

| Import pattern | Vendor | DPA URL |
|---|---|---|
| `@sendgrid/` | SendGrid (Twilio) | twilio.com/legal/data-protection-addendum |
| `resend` | Resend | resend.com/legal/dpa |
| `@postmarkapp/` | Postmark | postmarkapp.com/dpa |
| `twilio` | Twilio | twilio.com/legal/data-protection-addendum |
| `openai` | OpenAI | openai.com/policies/data-processing-addendum |
| `@anthropic-ai/` | Anthropic | anthropic.com/legal/dpa |
| `@supabase/` | Supabase | supabase.com/privacy |
| `firebase` | Google Firebase | business.safety.google/adsprocessorterms |
| `mixpanel` | Mixpanel | mixpanel.com/legal/dpa |
| `@segment/` | Segment | twilio.com/legal/data-protection-addendum |
| `intercom` | Intercom | intercom.com/legal/data-processing-agreement |
| `mailchimp` | Mailchimp | mailchimp.com/legal/data-processing-addendum |

**Flag each detected vendor once** — do not repeat per import line.

**Article:** Art. 28 — processor must be bound by a written contract

**Finding format:**
```
🟡 MEDIUM | GDPR Art. 28 | package.json
Processor detected: SendGrid (email delivery). A Data Processing Agreement (DPA) is required before sharing personal data with this vendor.
Fix: Sign the DPA at twilio.com/legal/data-protection-addendum. No code change required — this is a legal/admin step. Keep a copy of the signed DPA.
```

When multiple processors are detected, group them in a single finding:

```
🟡 MEDIUM | GDPR Art. 28 | package.json
3 data processors detected requiring Data Processing Agreements:
  • OpenAI — openai.com/policies/data-processing-addendum
  • SendGrid — twilio.com/legal/data-protection-addendum
  • Mixpanel — mixpanel.com/legal/dpa
No code changes required. Sign each DPA and retain a copy.
```

---

### 🟡 MEDIUM — Cookies Set Without Consent Library

**Step 1:** Check for a cookie consent library import (absence is the signal):
- `react-cookie-consent`, `cookieyes`, `onetrust`, `osano`, `tarteaucitron`, `cookiehub`

**Step 2:** Check for raw cookie-setting:
- `document.cookie =`, `js-cookie`, `nookies.set(`, `cookies.set(`

**Flag when:** Cookie-setting is detected AND no consent library is present.

**Do NOT flag when:**
- Only strictly necessary cookies are set (session cookies, auth tokens with no tracking purpose)
- The app uses a privacy-preserving analytics tool with no cookies (Plausible, Fathom)

**Article:** ePrivacy Directive + GDPR Art. 6

**Finding format:**
```
🟡 MEDIUM | GDPR / ePrivacy | src/lib/analytics.ts:12
Cookies are set (js-cookie) but no cookie consent library is detected. Non-essential cookies (analytics, tracking) require user consent before being set.
Fix: Add a consent management library. Lightweight options: react-cookie-consent (npm), cookieyes.com (hosted). Gate all non-essential cookie writes behind consent state.
```

---

### ℹ️ INFO — No Error Monitoring Detected

Scan for: `@sentry/`, `datadog-`, `logrocket`, `rollbar`, `bugsnag`

**Flag when:** None found. Without error monitoring, detecting a data breach and reporting it within 72 hours (Art. 33) is operationally very difficult.

**Finding format:**
```
ℹ️ INFO | GDPR Art. 33 | (no file — missing dependency)
No error monitoring library detected. GDPR Art. 33 requires reporting personal data breaches to supervisory authorities within 72 hours. Without monitoring, detecting breaches in time is operationally difficult.
Fix: Add Sentry (sentry.io — free tier available), Datadog, or equivalent. Ensure PII is scrubbed from error payloads before sending.
```

---

### ℹ️ INFO — US-Region Endpoints With No Data Residency Config

Scan for: `us-east-1`, `us-west-2`, `us-central1`, hardcoded `openai.com`, `api.anthropic.com`, and `vercel.json` without a `regions` field.

**Flag when:** Found in non-test files with no adjacent EU-region config or SCCs reference.

**Article:** Art. 44-49 — transfers to third countries

**Finding format:**
```
ℹ️ INFO | GDPR Art. 44 | src/lib/openai.ts:3
OpenAI API calls route to US servers by default. Transferring EU personal data to the US requires safeguards (Standard Contractual Clauses or adequacy decision).
Fix: Sign OpenAI's DPA (openai.com/policies/data-processing-addendum) which includes SCCs. If EU data residency is required, evaluate EU-hosted alternatives or Azure OpenAI with EU region.
```

---

## Common False Positives

| Pattern | Why it's a false positive |
|---|---|
| `console.log(user.id)` | User ID (non-identifying numeric/UUID) is not PII by itself |
| `console.log('email sent to', redactEmail(addr))` | Redacted — not raw PII |
| Pre-ticked "Remember me" checkbox | Session preference, not consent to data processing |
| Supabase import in a project with EU region config | Cross-border transfer is handled — still flag DPA requirement |
| `document.cookie` for auth session token only | Strictly necessary cookie — no consent needed |
| No privacy page but `href="/privacy"` in footer link | Externally hosted policy covers the obligation |
