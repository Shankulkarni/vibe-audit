---
name: audit-vercel-deployment
description: Audit Vercel deployments for env var exposure, security headers, function risks, and source map exposure
triggers: [vercel, next.js, nextjs, deployment, next-config, vercel-json, NEXT_PUBLIC, edge-runtime, source-maps]
---

# Audit: Vercel Deployment

## Purpose

Vercel deployments from AI generators have a consistent class of misconfiguration: secrets end up in the browser bundle (via `NEXT_PUBLIC_` prefix), source maps are enabled in production (exposing business logic), and security headers are missing entirely. These are deployment-time errors that are invisible in local development and only become exploitable in production.

## What to Look For

### NEXT_PUBLIC_ Prefix on Secret Variables

`NEXT_PUBLIC_` variables are inlined into the JavaScript bundle at build time and delivered to every browser that loads the app. They are not secret.

```ts
// Flag: CRITICAL — secret or private key with NEXT_PUBLIC_ prefix
// In .env or .env.production:
NEXT_PUBLIC_STRIPE_SECRET_KEY=sk_live_...    // exposed in bundle
NEXT_PUBLIC_OPENAI_API_KEY=sk-proj-...       // exposed in bundle
NEXT_PUBLIC_DATABASE_URL=postgresql://...    // exposed in bundle
NEXT_PUBLIC_SUPABASE_SERVICE_KEY=eyJ...      // exposed in bundle
NEXT_PUBLIC_SENDGRID_API_KEY=SG....          // exposed in bundle

// Flag: usage in source code
process.env.NEXT_PUBLIC_STRIPE_SECRET        // referenced in component
import.meta.env.NEXT_PUBLIC_DB_PASSWORD      // vite equivalent

// Safe NEXT_PUBLIC_ variables (do not flag):
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_...  // publishable key, intended to be public
NEXT_PUBLIC_SUPABASE_URL=https://....supabase.co  // URL, not a secret
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...            // anon key, limited permissions (context-dependent)
NEXT_PUBLIC_APP_URL=https://myapp.com           // public URL
```

Variable names that suggest secrets (always flag with `NEXT_PUBLIC_`):
`SECRET`, `KEY` (where not "publishable" or "anon"), `TOKEN`, `PASSWORD`, `DATABASE_URL`, `DB_URL`, `CONNECTION_STRING`, `API_KEY` (for private APIs).

### Server-Only Environment Variables Accessed in Client Components

```ts
// Flag: HIGH — server-only env var in a Client Component
'use client'
import { createClient } from 'some-client'

export function DataComponent() {
  const client = createClient({
    url: process.env.DATABASE_URL,   // server-only var in client component
    key: process.env.SECRET_API_KEY, // only available server-side, will be undefined in browser
  })
}

// Also flag: env vars in page.tsx or layout.tsx that could be statically analyzed into the bundle
// Check if the file has 'use client' directive OR if it uses client-only hooks

// Flag: env var in a file that is imported by both server and client code
// (shared utilities used on both sides may bundle the var reference)
export const config = {
  dbUrl: process.env.DATABASE_URL,  // if this file is imported by client components
}
```

### Source Maps in Production

Source maps expose your original TypeScript/JSX source code to anyone with browser DevTools. This reveals business logic, algorithm implementations, and makes reverse engineering trivial:

```ts
// Flag: CRITICAL — source maps enabled in next.config.js/ts
// next.config.ts:
const nextConfig = {
  productionBrowserSourceMaps: true,  // exposes full source in production
}

// Flag: source map generation in webpack config override
webpack: (config) => {
  config.devtool = 'source-map'  // source maps enabled in production webpack
  return config
}

// Safe (default): productionBrowserSourceMaps is false by default in Next.js
// If source maps are needed for error monitoring (Sentry), use:
// - Sentry's source map upload (uploads to Sentry, not served to browsers)
// - Hidden source maps: devtool: 'hidden-source-map' (not publicly accessible)
```

### Missing Security Headers

Check `next.config.js`/`ts` and `vercel.json` for security headers:

```ts
// Flag: no headers() function in next.config.ts

// Flag: headers() configured but missing critical headers
async headers() {
  return [{
    source: '/(.*)',
    headers: [
      // Missing: Content-Security-Policy
      // Missing: X-Frame-Options or frame-ancestors in CSP
      // Missing: X-Content-Type-Options
      // Missing: Referrer-Policy
      // Missing: Permissions-Policy
    ]
  }]
}

// Minimum required security headers:
{
  key: 'X-Content-Type-Options',
  value: 'nosniff',
},
{
  key: 'X-Frame-Options',
  value: 'DENY',
},
{
  key: 'Referrer-Policy',
  value: 'strict-origin-when-cross-origin',
},
{
  key: 'X-XSS-Protection',
  value: '1; mode=block',
},
```

### Vercel Function Timeout Not Configured for Expensive Operations

```ts
// Flag: expensive operations (AI, DB migrations, reports) with default 10s timeout
// Route file with no maxDuration export:
// src/app/api/generate-report/route.ts — calls OpenAI, no timeout config

// The 10-second default Vercel function timeout will kill long-running operations
// without a clear error, leading to partial work and confusing failures

// Correct: configure timeout per route
// src/app/api/generate-report/route.ts:
export const maxDuration = 60  // seconds (Pro plan allows up to 300s)

// Also flag: expensive operations in edge runtime where max is 30s
export const runtime = 'edge'  // edge max timeout varies by plan
// If the operation can take > 25 seconds, it shouldn't be edge runtime
```

### vercel.json With Overly Permissive CORS Headers

```json
// Flag: wildcard CORS in vercel.json headers
{
  "headers": [
    {
      "source": "/api/(.*)",
      "headers": [
        { "key": "Access-Control-Allow-Origin", "value": "*" },
        { "key": "Access-Control-Allow-Credentials", "value": "true" }
      ]
    }
  ]
}
// wildcard + credentials is invalid — browsers block it
// wildcard alone on authenticated API endpoints is a security concern
```

### Preview Deployment URLs Accessing Production Data

```ts
// Flag: no preview deployment protection for apps with sensitive data
// Look for: absence of password protection in vercel.json or Vercel project settings
// AND: preview deployments that use production environment variables

// In vercel.json:
// No "protection" or "bypassForRobots" configuration
// No password protection for preview URLs

// Sensitive preview deployments allow:
// - Scrapers to index unfinished features
// - Anyone with the URL to access production-adjacent data
```

### Build-Time Env Vars That Should Be Runtime

```ts
// Flag: secrets accessed during static generation or build phase
// In a generateStaticParams or getStaticProps equivalent:
export async function generateStaticParams() {
  const data = await fetch('https://api.example.com', {
    headers: { Authorization: `Bearer ${process.env.API_SECRET}` }
  })
  // This runs during `next build` — the secret is embedded in the build output
}

// Flag: env vars accessed in top-level module scope (runs at build time)
const STRIPE = new Stripe(process.env.STRIPE_SECRET_KEY)  // module-level initialization
// This runs when the module is bundled, which happens at build time
// Correct: initialize inside request handlers
```

### Missing output: 'standalone' or Incorrect ISR Config

```ts
// Flag: ISR revalidation set to 0 or missing for pages that should be cached
// page.tsx or route segment config:
export const revalidate = 0  // disables ISR — every request hits the origin
// On high-traffic pages this is a performance issue

// Flag: output: 'standalone' missing when self-hosting
// next.config.ts with no output config when the project is deployed to Docker/custom infra
```

### .env Files Committed to Git

Scan for:
- `.env.local`, `.env.production`, `.env.development` present in the repository (not gitignored)
- `.gitignore` that doesn't exclude `.env*` files
- `git log --all -- .env` history showing past commits of env files

```
// Flag: .env files in repository root without gitignore exclusion
// Check .gitignore for:
.env
.env.local
.env.*.local
.env.production
```

## Severity Classification

**Critical**
- `NEXT_PUBLIC_` prefix on any variable whose name suggests it is a private key or secret
- `productionBrowserSourceMaps: true` — full source code exposed in production
- `.env.production` committed to git containing real secrets

**High**
- Server-only env vars accessed in files with `'use client'` directive
- `.env` files committed to git (even without live keys — establishes bad practice and may contain secrets in history)
- Missing `X-Frame-Options` or CSP `frame-ancestors` (clickjacking)

**Medium**
- Missing security headers (`X-Content-Type-Options`, `Referrer-Policy`, CSP)
- No function timeout configured for AI/LLM or report-generation routes
- Wildcard CORS in vercel.json on authenticated endpoints
- Preview deployments without password protection for apps with user data

**Low**
- Missing ISR revalidation on cacheable pages (performance, not security)
- Missing `output: 'standalone'` for self-hosted Next.js (deployment correctness)
- Build-time env var access that doesn't expose secrets but creates fragile builds

## Finding Format

```
🔴 CRITICAL | Secret in NEXT_PUBLIC_ | .env.production:4
NEXT_PUBLIC_STRIPE_SECRET_KEY=sk_live_... — NEXT_PUBLIC_ variables are embedded in the browser bundle. Your Stripe secret key is visible to anyone who opens DevTools.
Fix: Rename to STRIPE_SECRET_KEY (no NEXT_PUBLIC_ prefix). Move all Stripe API calls to Server Actions or API routes. Use NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY (pk_) for client-side Stripe.js only.

🔴 CRITICAL | Source Maps in Production | next.config.ts:8
productionBrowserSourceMaps: true exposes your full TypeScript source code in production. Business logic, algorithms, and internal API structure are visible to anyone.
Fix: Remove this setting (false is the default). For error monitoring, use Sentry's source map upload feature instead — it sends maps to Sentry, not to browsers.

🟠 HIGH | .env Committed to Git | .env.local
.env.local is tracked in git. Even if current values are safe, this trains contributors to commit env files and may expose secrets added in the future.
Fix: Add .env* to .gitignore immediately. Rotate any secrets that were ever committed. Use: git rm --cached .env.local

🟠 HIGH | Server Env in Client Component | src/components/DataFetcher.tsx:12
process.env.DATABASE_URL accessed in a 'use client' component. This env var is server-only — it will be undefined in the browser, silently breaking the component.
Fix: Move data fetching to a Server Component, Server Action, or API route. Pass only the data (not the connection config) to the client component.

🟡 MEDIUM | Missing Security Headers | next.config.ts
No headers() configuration found. Missing: X-Content-Type-Options, X-Frame-Options, Referrer-Policy. These protect against MIME sniffing, clickjacking, and referrer leakage.
Fix: Add a headers() export to next.config.ts with the standard security header set.

🟡 MEDIUM | No Function Timeout | src/app/api/generate/route.ts
Route calls OpenAI API with no maxDuration export. Default Vercel timeout is 10 seconds. LLM calls regularly exceed this, causing 504 errors with no indication to the user.
Fix: Add export const maxDuration = 60 at the top of the route file. Ensure your Vercel plan supports the timeout duration.

🔵 LOW | Preview Deployments Unprotected | vercel.json
No preview deployment protection configured. Preview URLs are publicly accessible and indexed by search engines.
Fix: Enable Vercel's deployment protection in project settings, or add a password in vercel.json: "protection": { "deploymentType": "preview" }
```

## Common False Positives

Do NOT flag:
- `NEXT_PUBLIC_SUPABASE_URL` — the Supabase project URL is meant to be public
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — the anon key is designed for public client-side use (RLS enforces access)
- `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` or `NEXT_PUBLIC_STRIPE_KEY` starting with `pk_` — publishable keys are meant to be client-side
- `NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_BASE_URL` — these are public configuration
- `NEXT_PUBLIC_POSTHOG_KEY`, `NEXT_PUBLIC_GA_MEASUREMENT_ID`, `NEXT_PUBLIC_MIXPANEL_TOKEN` — analytics keys are public by design
- `productionBrowserSourceMaps: false` or absence of the setting (false is the default — safe)
- Source map upload to Sentry using `@sentry/nextjs` — this uploads maps to Sentry, not to the browser
- `revalidate = 0` on pages that are explicitly dynamic and should not be cached

## Stack-Specific Notes

**Next.js App Router vs Pages Router**: Both use the same env var conventions. `NEXT_PUBLIC_` is always bundled to the client in both routers. In App Router, Server Components can safely access server-only env vars — but only if the file does NOT have `'use client'`.

**Vercel Edge Runtime**: Edge functions have stricter timeout limits than Node.js functions. They also cannot use Node.js APIs (no `fs`, no `crypto` module in some cases). Flag when CPU-intensive operations are deployed to edge without justification.

**Vercel ISR (Incremental Static Regeneration)**: Pages with `revalidate = 3600` are cached for 1 hour — this is correct for static-ish content. Flag only when sensitive user-specific data might be cached and served to other users.

**Environment variable scoping in Vercel**: Vercel lets you set env vars for Production, Preview, and Development separately. Verify that production secrets are not set for Preview environments (which deploy on every PR).

**Sentry Integration**: `withSentryConfig()` in `next.config.ts` can automatically upload source maps to Sentry using `hideSourceMaps: true`. This is safe — the maps go to Sentry, not to browsers. Do not flag this pattern.

**Turborepo / Monorepos**: In monorepos, env vars may be defined in the root `.env` and shared. Check that shared env files are gitignored and that `NEXT_PUBLIC_` vars in shared packages don't inadvertently expose secrets.
