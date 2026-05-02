---
name: audit-node-api-auth
description: Audit Node.js API routes for missing auth, broken JWT verification, exposed admin endpoints, and missing rate limiting
triggers: [express, hono, fastify, koa, node, api, jwt, middleware, routes, auth-middleware, bearer-token]
---

# Audit: Node.js API Authentication

## Purpose

Node.js API routes from AI generators have a consistent failure mode: auth middleware is added to the app but routes are created before or outside the middleware scope, or the middleware is skipped for specific paths that turn out to be sensitive. JWT verification is especially error-prone — AI generators use `jwt.decode()` instead of `jwt.verify()`, which is a catastrophic difference (decode is unauthenticated).

## What to Look For

### Unprotected Routes — No Auth Middleware in Chain

Scan every route handler and trace whether auth middleware is in its middleware chain:

```ts
// Flag: route with no auth middleware
app.get('/api/users', async (req, res) => {
  const users = await db.users.findMany()
  res.json(users)
})

// Flag: router mounted after auth middleware but with unprotected routes defined on app
app.use('/api', authMiddleware)

// BEFORE the above line:
app.get('/api/admin/data', handler)  // unprotected! defined before authMiddleware

// Flag: auth middleware applied to a path prefix but sensitive route uses different prefix
app.use('/api/v1', authMiddleware, router)
app.get('/api/admin/delete-all', adminHandler)  // /api/admin not covered by /api/v1 middleware
```

Auth middleware names to recognize (do not flag routes that include these):
`authenticate`, `requireAuth`, `verifyToken`, `checkAuth`, `isAuthenticated`, `authGuard`, `authorize`, `requireSession`, `withAuth`, `protected`, `ensureLoggedIn`, `passport.authenticate`, `auth`, `authMiddleware`.

### Broken JWT Verification — decode() Instead of verify()

This is the most critical JWT mistake:

```ts
// Flag: CRITICAL — jwt.decode() does NOT verify the signature
import jwt from 'jsonwebtoken'

const decoded = jwt.decode(token)  // skips signature verification entirely
const userId = decoded.userId      // attacker can forge any payload

// Correct:
const decoded = jwt.verify(token, process.env.JWT_SECRET, {
  algorithms: ['HS256'],  // always specify algorithm
})
```

`jwt.decode()` is only appropriate when you need to read the payload of a token you are about to verify through another mechanism (e.g., extracting the `kid` to look up the public key). It is never a substitute for `jwt.verify()`.

### Missing Algorithm Specification in jwt.verify()

```ts
// Flag: HIGH — no algorithm specified (algorithm confusion attack)
jwt.verify(token, process.env.JWT_SECRET)
// An attacker can switch the token header to alg:none or alg:HS256 with a known public key

// Correct:
jwt.verify(token, process.env.JWT_SECRET, {
  algorithms: ['HS256'],  // explicit allowlist, rejects alg:none automatically
})

// Or with asymmetric keys:
jwt.verify(token, publicKey, {
  algorithms: ['RS256'],
})
```

### alg: 'none' Not Explicitly Rejected

```ts
// Flag: verify options do not include algorithms list
// (alg: 'none' is accepted by default in some older jsonwebtoken versions)
jwt.verify(token, secret)  // no algorithms option

// Correct — algorithms option implicitly rejects 'none':
jwt.verify(token, secret, { algorithms: ['HS256'] })
```

### Empty or Unvalidated JWT Secret

```ts
// Flag: JWT secret not validated — empty string secret accepts any token in some libraries
const secret = process.env.JWT_SECRET  // could be undefined or empty string in misconfigured env
jwt.verify(token, secret)

// Correct: validate secret exists at startup
const JWT_SECRET = process.env.JWT_SECRET
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET must be set and at least 32 characters')
}
jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] })
```

### Hardcoded JWT Secrets

```ts
// Flag: CRITICAL — hardcoded JWT secret
jwt.sign(payload, 'secret')
jwt.sign(payload, 'my-secret-key')
jwt.verify(token, 'mysecretpassword')
jwt.sign(payload, process.env.JWT_SECRET || 'fallback-secret')  // fallback is hardcoded
```

### Admin/Internal Routes Without Role Check

```ts
// Flag: route path suggests admin but only checks authentication (not role)
app.delete('/admin/users/:id', authenticate, async (req, res) => {
  // authenticate runs but doesn't check if user is admin
  await db.users.delete({ where: { id: req.params.id } })
})

// Flag: /internal or /debug routes without elevated auth
app.get('/internal/metrics', async (req, res) => { ... })
app.get('/debug/dump-state', async (req, res) => { ... })

// Routes containing these path segments always need admin/internal role check:
// /admin/, /internal/, /debug/, /dev/, /management/, /system/

// Correct:
app.delete('/admin/users/:id', authenticate, requireRole('admin'), async (req, res) => { ... })
```

### Missing Rate Limiting on Auth Endpoints

```ts
// Flag: login endpoint with no rate limiter
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body
  const user = await db.users.findByEmail(email)
  // No rate limiting — brute force attack possible
})

// Endpoints that always need rate limiting:
// /login, /signin, /register, /signup, /forgot-password, /reset-password,
// /verify-email, /resend-otp, /api/* (general API rate limit)

// Flag: rate limiter configured but not applied to auth routes
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 100 })
app.use('/api', limiter)
app.post('/login', handler)  // /login is outside /api — not rate limited
```

### CORS Misconfiguration

```ts
// Flag: wildcard CORS on endpoints that use cookies or session auth
app.use(cors({ origin: '*' }))
// Wildcard CORS prevents cookies from being sent, but if using Bearer tokens,
// it means any website can make authenticated requests on behalf of your users

// Flag: CORS origin set to * while also using credentials: true
app.use(cors({
  origin: '*',
  credentials: true,  // invalid combination — browsers reject this
}))

// Flag: reflecting origin without validation
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', req.headers.origin)  // any origin allowed
  res.header('Access-Control-Allow-Credentials', 'true')
  next()
})
```

### Unvalidated Input — req.body Directly in DB Queries

```ts
// Flag: direct use of req.body values in queries without validation
app.post('/users', async (req, res) => {
  const user = await db.users.create({ data: req.body })
  // req.body can contain any fields — including role: 'admin'
})

// Flag: req.params used directly in queries without validation
app.get('/users/:id', async (req, res) => {
  const user = await db.users.findById(req.params.id)
  // No type checking, no format validation on id
})
```

### Oversized Payload Limit

```ts
// Flag: excessively large payload limit
app.use(express.json({ limit: '50mb' }))
app.use(express.json({ limit: '100mb' }))
// Large limits enable denial-of-service attacks via body size

// Reasonable defaults:
app.use(express.json({ limit: '1mb' }))
// Increase only for specific routes that genuinely need it (e.g., file upload routes)
```

### Session Fixation — Not Regenerating Session After Login

```ts
// Flag: session not regenerated after login
app.post('/login', async (req, res) => {
  const user = await authenticate(req.body)
  req.session.userId = user.id  // same session ID before and after login
  // Attacker can fixate a session ID and hijack it after the user logs in
})

// Correct:
app.post('/login', async (req, res) => {
  const user = await authenticate(req.body)
  req.session.regenerate((err) => {  // new session ID after login
    req.session.userId = user.id
    res.json({ success: true })
  })
})
```

### Missing HTTPS Enforcement

```ts
// Flag: no HTTPS redirect in production
// Express app with no helmet() or manual HTTPS redirect

// Flag: helmet installed but hsts not enabled
app.use(helmet({ hsts: false }))

// Correct for production:
app.use(helmet())  // includes HSTS by default
// or:
app.use((req, res, next) => {
  if (req.headers['x-forwarded-proto'] !== 'https') {
    return res.redirect(301, 'https://' + req.headers.host + req.url)
  }
  next()
})
```

## Severity Classification

**Critical**
- `jwt.decode()` used instead of `jwt.verify()` — signature verification bypassed
- Hardcoded JWT secret (string literal passed to `jwt.sign` or `jwt.verify`)
- Admin route (`/admin/`, `/internal/`) with no auth middleware at all

**High**
- Auth middleware missing on data mutation routes (POST, PUT, PATCH, DELETE)
- No algorithm specified in `jwt.verify()` options (algorithm confusion attack surface)
- Admin route with authentication but no role/permission check
- CORS reflecting arbitrary origins with `credentials: true`

**Medium**
- Missing rate limiting on `/login`, `/register`, `/forgot-password`
- `origin: '*'` on API endpoints using Bearer token auth (CSRF risk with certain patterns)
- Direct `req.body` spread into DB operations without validation
- Oversized payload limit (`50mb+`)

**Low**
- Session fixation risk (not regenerating session after login)
- Missing HTTPS enforcement in production
- Missing Helmet or security header middleware

## Finding Format

```
🔴 CRITICAL | jwt.decode() Used | src/middleware/auth.ts:18
jwt.decode(token) is used instead of jwt.verify(). decode() does not verify the signature — any token payload can be forged by an attacker.
Fix: Replace with jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] })

🔴 CRITICAL | Hardcoded JWT Secret | src/lib/tokens.ts:5
jwt.sign(payload, 'my-secret-key') uses a hardcoded string. Anyone who reads the source has the signing key.
Fix: Use jwt.sign(payload, process.env.JWT_SECRET) and set a strong random secret in your deployment environment.

🔴 CRITICAL | Admin Route Without Auth | src/routes/admin.ts:34
DELETE /admin/users/:id has no auth middleware in the chain. Any unauthenticated request can delete users.
Fix: Add authenticate middleware: router.delete('/users/:id', authenticate, requireRole('admin'), handler)

🟠 HIGH | No Algorithm in jwt.verify | src/middleware/verify.ts:22
jwt.verify(token, secret) without algorithms option is vulnerable to algorithm confusion attacks.
Fix: Add algorithms option: jwt.verify(token, secret, { algorithms: ['HS256'] })

🟠 HIGH | Auth Endpoint Without Rate Limit | src/routes/auth.ts:8
POST /login has no rate limiting middleware. Brute force attacks are possible.
Fix: Apply rate limiter: router.post('/login', loginRateLimiter, handler) using express-rate-limit or similar.

🟡 MEDIUM | Oversized Payload Limit | src/app.ts:12
express.json({ limit: '50mb' }) allows very large request bodies, enabling denial-of-service via memory exhaustion.
Fix: Use a smaller limit (1mb default). Apply higher limits only to specific upload routes.

🔵 LOW | Session Not Regenerated | src/routes/auth.ts:45
After successful login, session ID is reused. This creates a session fixation vulnerability.
Fix: Call req.session.regenerate() before setting session data after login.
```

## Common False Positives

Do NOT flag:
- `jwt.decode()` used specifically to extract the `kid` (key ID) header before a separate `jwt.verify()` call with the correct key
- Public/unauthenticated routes that are intentionally public: `/api/health`, `/api/version`, `/robots.txt`, `GET /api/products` for public catalogs
- Rate limiting on routes that have it through a parent middleware (`app.use('/api', rateLimiter)`) — trace the full chain
- CORS `origin: '*'` on genuinely public, stateless API endpoints that don't use cookies or sensitive operations
- `express.json({ limit: '10mb' })` on file upload routes where the limit is justified

## Stack-Specific Notes

**Hono**: Route-level middleware in Hono is applied via `.use()` before route handlers or via `app.use('/path/*', middleware)`. Check that protected route groups are covered. Hono's `bearerAuth()` middleware from `hono/bearer-auth` is a valid auth check.

**Fastify**: Plugins and hooks are the auth mechanism. `fastify.addHook('preHandler', authenticate)` scoped to a plugin is correct. Check that the hook is registered before the routes it should protect.

**tRPC**: Procedures should use `protectedProcedure` (or equivalent) for authenticated operations. `publicProcedure` for mutations is always a flag.

**Next.js API Routes (`pages/api/`)**: Auth must be checked inside the handler function — there is no global middleware equivalent to Express. Each handler that needs auth must call `getServerSession()` or similar at the top.

**Next.js Route Handlers (`app/api/route.ts`)**: Same as above — auth check must be inside the `GET`/`POST` etc. export. `middleware.ts` can add headers but cannot replace per-route auth checks for data access control.

**JWT libraries**: `jose` (npm package) is a modern alternative to `jsonwebtoken` with better defaults. `jose.jwtVerify()` requires algorithm specification — it is harder to misconfigure. Flag `jwt.decode()` from `jsonwebtoken` but `jose.decodeJwt()` has slightly different semantics — verify usage context.
