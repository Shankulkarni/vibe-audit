---
name: audit-nextjs-server-actions
description: Audit Next.js Server Actions for missing auth, unvalidated input, and CSRF gaps
triggers: [nextjs, next.js, server-actions, use-server, actions, app-router, server-action]
---

# Audit: Next.js Server Actions

## Purpose

Next.js Server Actions are functions marked `'use server'` that execute on the server and can be called directly from Client Components. AI code generators treat them like regular async functions and routinely omit authentication checks, input validation, and proper error handling. A Server Action without auth is effectively a public API endpoint — callable by anyone who can find the function reference or reproduce the POST request.

## What to Look For

### Server Actions Without Authentication

Any function in a `'use server'` file or with a top-level `'use server'` directive that performs data operations without first verifying the caller's identity:

```ts
// Flag: mutation with no auth check
'use server'

export async function updateProfile(data: ProfileData) {
  // No session check, no auth.uid(), no getServerSession()
  await db.profiles.update({ where: { id: data.id }, data })
}

// Flag: reading sensitive data without auth
export async function getUserPayments() {
  return await db.payments.findMany()  // returns ALL payments, no user filter
}
```

Auth checks that count as valid (do not flag if these appear before the first DB call):
- `getServerSession(authOptions)` from next-auth
- `auth()` from next-auth v5
- `getSession()` from any auth library with a subsequent null check
- `createServerClient` + `supabase.auth.getUser()` with a null check
- Custom `verifyToken()`, `requireAuth()`, `authenticate()` calls with early return/throw on failure

Pattern to detect: an `export async function` in a server action file where the first `await` is a database call rather than an auth call.

### Unvalidated Input in Server Actions

```ts
// Flag: FormData used directly without schema validation
export async function createPost(formData: FormData) {
  const title = formData.get('title')
  const content = formData.get('content')
  // No validation — title could be empty, XSS content, or exceed DB column size
  await db.posts.create({ data: { title, content } })
}

// Flag: plain object accepted without validation
export async function updateUser(data: { name: string; email: string; role: string }) {
  // No zod, no yup, no manual validation
  // Caller can set role: 'admin'
  await db.users.update({ where: { id: ... }, data })
}
```

Validation that counts as valid: `z.parse()`, `z.safeParse()`, `schema.validate()`, `schema.parse()`, manual checks on every field used in a DB operation.

### Exposed Internal Data — Over-fetching in Server Actions

```ts
// Flag: returning full DB object when only a subset is needed
export async function getUser(userId: string) {
  return await db.users.findUnique({ where: { id: userId } })
  // Returns: id, email, passwordHash, internalFlags, stripeCustomerId, createdAt, etc.
}

// Better: explicit field selection
export async function getUser(userId: string) {
  return await db.users.findUnique({
    where: { id: userId },
    select: { id: true, name: true, email: true }
  })
}
```

Flag: Server Actions that return full ORM model objects (no `select` clause) containing fields that should not reach the client.

### Unauthenticated Mutations — Database Writes Without Auth

Specifically for mutation operations (INSERT, UPDATE, DELETE):

```ts
// Flag: any of these without a preceding auth check
await db.something.create(...)
await db.something.update(...)
await db.something.delete(...)
await supabase.from('table').insert(...)
await supabase.from('table').update(...)
await supabase.from('table').delete()
prisma.model.create(...)
prisma.model.update(...)
prisma.model.delete(...)
```

### Missing revalidatePath / revalidateTag After Mutations

```ts
// Flag: mutation with no cache invalidation
export async function deletePost(postId: string) {
  const session = await auth()
  if (!session) throw new Error('Unauthorized')
  await db.posts.delete({ where: { id: postId } })
  // Missing: revalidatePath('/posts') or revalidateTag('posts')
  // UI will show stale data
}
```

This is a correctness issue, not a security issue — classify as Medium.

### Admin Client / Service Role in Server Actions Without Elevated Auth Check

```ts
// Flag: admin/service client used without checking if caller is admin
export async function adminDeleteUser(userId: string) {
  const session = await auth()
  if (!session) throw new Error('Unauthorized')
  // Session exists but is caller actually an admin? Not checked.
  
  const adminClient = createClient(url, serviceRoleKey)
  await adminClient.from('users').delete().eq('id', userId)
}
```

When an elevated client (service role, admin connection) is used, verify there is also a role/permission check, not just an authentication check.

### Error Messages Exposing Internals

```ts
// Flag: stack traces or DB errors returned to client
} catch (e) {
  return { error: (e as Error).message }
  // Could expose: DB connection string in error, table/column names, internal paths
}

// Flag: re-throwing raw errors from ORM
} catch (e) {
  throw e  // Prisma errors contain query details
}

// Acceptable: generic error messages
} catch (e) {
  console.error('Update failed:', e)  // log internally
  return { error: 'Update failed. Please try again.' }  // generic to client
}
```

### Missing Rate Limiting on Expensive Server Actions

```ts
// Flag: AI generation, email send, or payment operation with no rate limiting
export async function generateReport(params: ReportParams) {
  const session = await auth()
  if (!session) throw new Error('Unauthorized')
  // No rate limit check — user can call this in a loop
  const report = await openai.chat.completions.create({ ... })
  return report
}
```

Rate-sensitive operations: LLM API calls, email sends, SMS sends, payment processing, PDF generation, data exports.

### Insecure Redirects

```ts
// Flag: redirect to user-supplied URL
export async function loginAndRedirect(formData: FormData) {
  const redirectTo = formData.get('redirectTo') as string
  // No validation — could redirect to https://evil.com
  redirect(redirectTo)
}

// Safe: validate against allowlist
const ALLOWED_PATHS = ['/dashboard', '/profile', '/settings']
if (!ALLOWED_PATHS.includes(redirectTo)) redirect('/dashboard')
```

## Severity Classification

**Critical**
- Mutation Server Action (INSERT/UPDATE/DELETE) with no authentication check
- Admin/service client used in SA with only authentication check (no role/permission check)

**High**
- SA returning sensitive data (payments, tokens, PII) without auth
- Unvalidated input used directly in DB operations (allows type confusion, injection, privilege escalation via role field)
- User-supplied URL passed to `redirect()` without validation

**Medium**
- Missing `revalidatePath`/`revalidateTag` after mutations (stale data)
- Error messages exposing internal DB error details or stack traces
- Missing rate limiting on expensive operations (AI, email, payment)

**Low**
- SA returning slightly more data than needed (low sensitivity fields)
- Missing rate limiting on non-critical read operations

## Finding Format

```
🔴 CRITICAL | Unauthenticated Mutation | src/app/actions/posts.ts:12
Server Action 'deletePost' performs a DB delete without any authentication check.
Fix: Add const session = await auth(); if (!session) throw new Error('Unauthorized'); before the delete call.

🔴 CRITICAL | Admin Client Without Role Check | src/app/actions/admin.ts:34
Server Action uses service role client after checking authentication only. Any authenticated user can trigger admin operations.
Fix: Add a role check (e.g., if (session.user.role !== 'admin') throw new Error('Forbidden');) before using the elevated client.

🟠 HIGH | Unvalidated Input to DB | src/app/actions/profile.ts:18
FormData fields passed directly to db.update() without schema validation. Callers can set arbitrary fields including 'role'.
Fix: Parse input with zod: const data = profileSchema.parse(Object.fromEntries(formData)); before the DB call.

🟠 HIGH | Sensitive Data Returned Without Auth | src/app/actions/payments.ts:8
Server Action 'getPayments' returns full payment records without checking session. Any client can call this action.
Fix: Add session check. Filter by auth'd user: where: { userId: session.user.id }.

🟡 MEDIUM | Missing Cache Invalidation | src/app/actions/posts.ts:45
Post is deleted but revalidatePath('/posts') is not called. UI will show stale data.
Fix: Add revalidatePath('/posts') after the successful delete.

🟡 MEDIUM | Internal Error Exposed | src/app/actions/users.ts:67
catch block returns e.message which may contain Prisma error details including table/column names.
Fix: Log e internally, return a generic error string to the client.

🔵 LOW | Missing Rate Limit | src/app/actions/reports.ts:22
Server Action triggers an OpenAI API call with no per-user rate limiting.
Fix: Add rate limiting via upstash/ratelimit or equivalent before the API call.
```

## Common False Positives

Do NOT flag:
- Server Actions in `app/(admin)/` layouts that inherit admin middleware — verify the middleware actually enforces auth
- `redirect()` calls to hardcoded internal paths (not user-supplied)
- `revalidatePath` absence on read-only (GET-equivalent) Server Actions
- Auth checks that happen via middleware in `middleware.ts` covering the route — though note this doesn't protect direct SA invocation from other routes

## Stack-Specific Notes

**next-auth v4**: `getServerSession(authOptions)` is the correct auth check. The result is `null` if unauthenticated — flag if the null case is not handled.

**next-auth v5 / Auth.js**: `auth()` returns the session. Flag if result is not checked before use.

**Supabase + Next.js**: `createServerClient` from `@supabase/ssr` + `supabase.auth.getUser()` is correct. `getUser()` makes a network call to verify the token — prefer it over `getSession()` which reads from the cookie without verification.

**Clerk**: `auth()` or `currentUser()` from `@clerk/nextjs/server`. Both can return null — check for null before DB operations.

**File location heuristics**: Files in `app/actions/`, `actions/`, `app/**/actions.ts`, or any file with `'use server'` at the top are Server Action files. Functions exported from these files are the audit targets.
