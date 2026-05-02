---
name: audit-supabase-rls
description: Audit Supabase Row Level Security policies for gaps AI code generators commonly miss
triggers: [supabase, rls, postgres, row-level-security, supabase-js, createClient, auth.uid]
---

# Audit: Supabase Row Level Security

## Purpose

Supabase uses PostgreSQL Row Level Security to enforce data access rules at the database layer. AI code generators routinely scaffold Supabase projects with RLS disabled or with permissive catch-all policies that grant access to everyone. This is catastrophic: any authenticated (or unauthenticated) user can read, write, or delete any row in the database.

This skill audits both the SQL migration files (where policies are defined) and the application code (where the Supabase client is configured and used).

## What to Look For

### Tables Without Any RLS Policies

In SQL migration files, check for:

```sql
-- Flag: RLS explicitly disabled
ALTER TABLE users DISABLE ROW LEVEL SECURITY;

-- Flag: table created without enabling RLS (default is disabled)
CREATE TABLE profiles (
  id uuid PRIMARY KEY,
  user_id uuid,
  bio text
);
-- No accompanying: ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
```

Cross-reference: every table that stores user data, business data, or anything not meant to be globally public should have `ENABLE ROW LEVEL SECURITY` and at least one policy.

Tables that always require RLS: `users`, `profiles`, `accounts`, `sessions`, `orders`, `payments`, `subscriptions`, `invoices`, `documents`, `messages`, `notifications`, `settings`.

### Permissive Catch-All Policies

```sql
-- Flag: grants all authenticated users access to all rows
CREATE POLICY "allow_all" ON users
  USING (true);

-- Flag: allows anyone to insert anything
CREATE POLICY "allow_insert" ON posts
  WITH CHECK (true);

-- Flag: named "authenticated" but no uid check — all auth'd users see all rows
CREATE POLICY "authenticated_access" ON documents
  FOR SELECT
  TO authenticated
  USING (true);
```

The fix requires replacing `USING (true)` with an actual ownership/permission check:

```sql
-- Correct pattern
CREATE POLICY "users_own_rows" ON profiles
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

### service_role Key Used in Client-Side Code

The `service_role` key bypasses ALL RLS policies entirely. It must never appear in browser-executed code:

```ts
// Flag: service_role used in a component, page, or any client-side file
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!  // CRITICAL: this bypasses RLS
)

// Flag: NEXT_PUBLIC_ prefix on service role key
// NEXT_PUBLIC_SUPABASE_SERVICE_KEY=eyJ... — embedded in browser bundle
```

The `service_role` key is only acceptable in:
- Server-side code: API routes, Server Actions, server-only utility files
- Migration scripts
- Admin CLI tools

### Security-Definer RPC Functions Without Internal Auth Checks

```sql
-- Flag: SECURITY DEFINER without an explicit auth check inside
CREATE OR REPLACE FUNCTION admin_delete_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
BEGIN
  DELETE FROM users WHERE id = target_user_id;
  -- No check: is the calling user actually an admin?
END;
$$;

-- Correct pattern: check inside the function
CREATE OR REPLACE FUNCTION admin_delete_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  DELETE FROM users WHERE id = target_user_id;
END;
$$;
```

Grep migrations for `SECURITY DEFINER` and verify each function has a `auth.uid()` check or equivalent authorization logic inside.

### Missing RLS on Sensitive Tables

Scan migration files for table creation and check for corresponding RLS enablement and policies:

Tables that are always sensitive:
- `users`, `profiles`, `accounts` — identity data
- `payments`, `charges`, `invoices`, `subscriptions` — financial data
- `orders`, `cart`, `checkout` — transaction data
- `messages`, `conversations`, `threads` — communication data
- `documents`, `files`, `uploads` — content data
- `api_keys`, `tokens`, `sessions` — credential data

### Policies Missing auth.uid() Check

```sql
-- Flag: policy on sensitive table that doesn't check uid
CREATE POLICY "authenticated_can_read" ON payments
  FOR SELECT
  TO authenticated
  USING (auth.role() = 'authenticated');
  -- This allows ANY authenticated user to see ALL payments

-- Correct:
CREATE POLICY "own_payments" ON payments
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
```

### Storage Bucket Policies That Are Public

In storage configuration or migration files:

```sql
-- Flag: public bucket for private user files
INSERT INTO storage.buckets (id, name, public)
VALUES ('user-documents', 'user-documents', true);  -- public = true means no auth needed

-- Flag: overly permissive storage policy
CREATE POLICY "public_access" ON storage.objects
  FOR SELECT USING (true);
```

Check bucket definitions for `public: true` on buckets containing: avatars, documents, invoices, medical records, private uploads.

### Missing Policies for INSERT, UPDATE, DELETE

A common pattern from AI generators: only the SELECT policy is defined. This can mean:
- No one can insert (breaks the app)
- Or the default is to allow all (if RLS is misconfigured)

```sql
-- Flag: only SELECT policy, no INSERT/UPDATE/DELETE
CREATE POLICY "users_read_own" ON profiles
  FOR SELECT USING (auth.uid() = user_id);
-- Missing: INSERT, UPDATE, DELETE policies
```

Verify that tables have policies covering all relevant operations (`FOR ALL` is acceptable if it covers the right operations).

### Wrong Supabase Client for the Context

Supabase has three distinct client types with very different trust levels. Using the wrong one is a common AI generator mistake:

| Client | Key Used | RLS | Where It Belongs |
|--------|----------|-----|-----------------|
| Browser / anon client | `anon` key | Enforced | Auth state listening only |
| Server client (SSR) | `anon` key + user cookies | Enforced as the user | All data fetching and mutations |
| Admin client | `service_role` key | **Bypassed entirely** | Migration scripts, admin-only server routes |

```ts
// Flag: browser client used for data fetching
// Browser client only knows if a user is logged in — it can't impersonate them for DB queries
const supabase = createBrowserClient(url, anonKey)
const { data } = await supabase.from('orders').select('*')  // runs as anon, not as user

// Correct: use server client for data operations
import { createServerClient } from '@supabase/ssr'
const supabase = createServerClient(url, anonKey, { cookies })
const { data } = await supabase.from('orders').select('*')  // runs as authenticated user

// Flag: admin client used in a route handler that normal users can reach
export async function GET(req: Request) {
  const supabase = createAdminClient()  // bypasses RLS — all users see all rows
  return supabase.from('profiles').select('*')
}

// Admin client is only acceptable when:
// 1. The route itself enforces admin-role auth before reaching the DB call
// 2. It's a server-only migration/seed script
```

Grep for `createClient(` and `createAdminClient(` in files under `app/`, `pages/`, `components/`, `hooks/` — these should never use `service_role`.

### SQL Function search_path Injection

`SECURITY DEFINER` functions run with the privileges of the function owner, not the caller. An attacker who can control the `search_path` can substitute their own objects for the ones the function references:

```sql
-- Flag: SECURITY DEFINER function without SET search_path
CREATE OR REPLACE FUNCTION get_user_balance(user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER AS $$
BEGIN
  -- search_path not fixed — vulnerable to schema injection
  RETURN (SELECT balance FROM accounts WHERE id = user_id);
END;
$$;

-- Correct: always set search_path on SECURITY DEFINER functions
CREATE OR REPLACE FUNCTION get_user_balance(user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public  -- fixes the schema, prevents injection
AS $$
BEGIN
  RETURN (SELECT balance FROM accounts WHERE id = user_id);
END;
$$;
```

Grep migrations for `SECURITY DEFINER` and verify each function has `SET search_path = public` (or the appropriate schema).

### RLS Policy Performance Pitfalls

Poorly written RLS policies cause full sequential scans on every query. Two common mistakes from AI generators:

```sql
-- Flag: subquery inside USING — re-evaluated for every row
CREATE POLICY "user_owns_document" ON documents
  USING (
    auth.uid() = (SELECT user_id FROM document_owners WHERE document_id = id)
  );
-- This subquery runs once per row — O(n) for a table scan

-- Better: foreign key on the table itself, direct comparison
CREATE POLICY "user_owns_document" ON documents
  USING (auth.uid() = user_id);  -- user_id is a column on documents, direct comparison

-- Flag: calling a non-stable function inside USING
CREATE POLICY "authenticated" ON data
  USING (auth.uid() IS NOT NULL);
-- auth.uid() is fine — it's stable per transaction
-- But custom functions that do DB lookups inside USING are expensive

-- Correct pattern: keep USING conditions to direct column comparisons
-- Join tables if needed, but index the foreign key columns used in policies
```

For tables expected to have >10k rows: verify that the columns referenced in `USING` conditions are indexed, and that the policy doesn't force a full table scan.

Grep the codebase for these patterns and cross-check against RLS configuration:

```ts
// Check every .from() call — is RLS expected on this table?
supabase.from('users')
supabase.from('payments')
supabase.from('profiles')

// Flag: service role client creation in non-server files
createClient(supabaseUrl, supabaseServiceKey)

// Flag: .rpc() calls — check if the function is SECURITY DEFINER
supabase.rpc('admin_function')

// Flag: public storage URL construction for private content
supabase.storage.from('user-documents').getPublicUrl(path)  // on a private bucket
```

## Severity Classification

**Critical**
- `service_role` key used in client-side code or with `NEXT_PUBLIC_` prefix
- `USING (true)` policy on payments, users, or other sensitive tables
- No RLS at all on payments, orders, or user PII tables
- Admin client (`service_role`) used in a route that unauthenticated or regular users can reach

**High**
- Missing RLS on any table containing user-specific data
- `SECURITY DEFINER` function without internal authorization check
- `SECURITY DEFINER` function without `SET search_path` (schema injection risk)
- Policy using `auth.role() = 'authenticated'` without `auth.uid()` check on sensitive tables
- Browser client used for data fetching instead of server client (anon-level access)

**Medium**
- Missing INSERT, UPDATE, or DELETE policies (app may break or be unintentionally open)
- Public storage bucket for content that should be private
- Storage policies with `USING (true)` for non-public buckets
- RLS policy with subquery inside `USING` on high-row-count tables (performance)

**Low**
- Overly permissive policies on genuinely non-sensitive, public-read tables
- Missing anon-role restrictions on tables that should be authenticated-only
- RLS policy columns not indexed (performance at scale)

## Finding Format

```
🔴 CRITICAL | service_role in Client | src/lib/supabase/client.ts:8
supabaseServiceKey used to initialize the Supabase client in a file that runs in the browser. service_role bypasses all RLS policies — any user can read/write any row.
Fix: Move service_role usage to server-only files (API routes, Server Actions). Use anon key for client-side initialization.

🔴 CRITICAL | USING(true) on Payments | supabase/migrations/001_init.sql:45
Policy "allow_all" on payments table uses USING(true) — every authenticated user can read every payment record.
Fix: Replace with USING(auth.uid() = user_id) to scope access to the row owner.

🔴 CRITICAL | No RLS on Users Table | supabase/migrations/001_init.sql:12
users table created without ENABLE ROW LEVEL SECURITY — all rows are globally readable and writable.
Fix: Add ALTER TABLE users ENABLE ROW LEVEL SECURITY; and define appropriate policies.

🟠 HIGH | SECURITY DEFINER No Auth Check | supabase/migrations/003_functions.sql:28
Function admin_wipe_data() is SECURITY DEFINER but contains no auth.uid() or role check — any authenticated user can call it.
Fix: Add an authorization check at the top of the function before any destructive operations.

🟡 MEDIUM | Public Bucket for User Docs | supabase/migrations/002_storage.sql:5
Bucket 'user-documents' created with public=true. User-uploaded documents should not be publicly accessible.
Fix: Set public=false. Use signed URLs (createSignedUrl) for controlled access.

🟡 MEDIUM | Missing DELETE Policy | supabase/migrations/001_init.sql:67
profiles table has SELECT and INSERT policies but no DELETE policy. Behavior depends on default — verify intended.
Fix: Add an explicit DELETE policy or FOR ALL policy that covers the full ownership check.

🔴 CRITICAL | Admin Client in User Route | src/app/api/profile/route.ts:5
createAdminClient() called in a GET handler with no admin role check — all authenticated users bypass RLS and see every profile row.
Fix: Replace with createServerClient() (uses anon key + user session cookies, respects RLS). Reserve admin client for routes that explicitly verify admin role first.

🟠 HIGH | SECURITY DEFINER Missing search_path | supabase/migrations/004_functions.sql:12
Function process_refund() is SECURITY DEFINER without SET search_path. A malicious user who can create schemas could shadow the public.accounts table.
Fix: Add SET search_path = public to the function definition.

🟡 MEDIUM | RLS Subquery Performance | supabase/migrations/001_init.sql:88
Policy on messages table uses a subquery inside USING: (SELECT user_id FROM threads WHERE id = thread_id). This re-runs the subquery for every row scanned.
Fix: Add user_id as a direct column on messages (denormalize) and use USING (auth.uid() = user_id).
```

## Common False Positives

Do NOT flag:
- `USING (true)` on tables that are genuinely meant to be publicly readable (e.g., `public_posts`, `product_catalog`, `pricing_plans`)
- `service_role` in `supabase/functions/` (Edge Functions run server-side)
- `service_role` in migration scripts or seed scripts
- `SECURITY DEFINER` functions that only read public data and have no sensitive operations
- Public storage buckets for genuinely public assets (logos, marketing images, public avatars)

## Stack-Specific Notes

**Next.js App Router**: `createServerClient` from `@supabase/ssr` is the correct server-side client using the anon key + user cookies. Only `createAdminClient` with `service_role` is elevated — and only in Server Actions or API routes.

**Expo / React Native**: `createClient` with anon key is correct. The service_role key must never be in the mobile app bundle (it would be extractable from the APK/IPA).

**Supabase Edge Functions**: `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` is acceptable here — Edge Functions are server-side.

**Drizzle or Prisma on top of Supabase**: If using an ORM that bypasses Supabase client and connects directly to the Postgres connection string, RLS may be bypassed entirely. Flag direct `postgres://` connection string usage in application code — it needs its own authorization layer.
