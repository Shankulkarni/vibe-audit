---
name: audit-typescript-any-escape
description: Audit TypeScript codebases for any escapes that eliminate type safety at API and data boundaries
triggers: [typescript, any, ts-ignore, ts-nocheck, strict, json-parse, type-assertion, as-any]
---

# Audit: TypeScript any Escape

## Purpose

TypeScript's type system is only as strong as its boundaries. AI code generators systematically use `any` to avoid inference complexity at exactly the places where types matter most: API response boundaries, JSON parsing, route handlers, and event callbacks. A codebase can have 100% TypeScript coverage and zero meaningful type safety if `any` is used at every data ingress point.

This skill finds `any` escapes that create real runtime risk — not pedantic stylistic issues.

## What to Look For

### any at Fetch / HTTP Response Boundaries

```ts
// Flag: fetch response typed as any
const res = await fetch('/api/user')
const data = await res.json() as any  // all type safety lost from here

// Flag: axios with any
const { data } = await axios.get<any>('/api/payments')

// Flag: untyped json() call
const data = await response.json()  // no type annotation — TypeScript infers `any`

// Correct patterns:
const data: UserResponse = await res.json()
// or with runtime validation:
const raw = await res.json()
const data = UserResponseSchema.parse(raw)  // zod validates at runtime
```

### any in API Route Handler Parameters

```ts
// Flag: Express/Hono/Fastify handlers with any-typed req/res
app.get('/users', (req: any, res: any) => { ... })

app.post('/payment', async (req: any, res: any) => {
  const { amount } = req.body  // req.body is any, amount is any
  await chargeCustomer(amount)  // no type safety on amount
})

// Correct:
interface PaymentBody { amount: number; currency: string }
app.post('/payment', async (req: Request<{}, {}, PaymentBody>, res: Response) => { ... })
```

### Type Assertions Through any — Accessing Properties

```ts
// Flag: casting to any to access a property (avoiding type error instead of fixing the type)
const id = (user as any).internalId
const secret = (config as any).secretValue
const result = (response as any).data.items

// This pattern indicates the type is wrong — fix the type, don't cast around it
```

### Untyped JSON.parse

```ts
// Flag: JSON.parse without type annotation or validation
const config = JSON.parse(configString)  // infers any
const user = JSON.parse(localStorage.getItem('user'))  // any
const payload = JSON.parse(req.body)  // any

// Correct patterns:
// Option 1: type assertion with known shape (still no runtime check)
const config = JSON.parse(configString) as AppConfig

// Option 2: runtime validation (preferred for external data)
const config = AppConfigSchema.parse(JSON.parse(configString))
```

### @ts-ignore Without Explanatory Comment

```ts
// Flag: ts-ignore with no reason
// @ts-ignore
doSomething(value)

// Flag: ts-expect-error with no reason
// @ts-expect-error
legacyFunction(data)

// Acceptable (do not flag):
// @ts-ignore — third-party type definition missing optional overload
doSomething(value)

// @ts-expect-error — testing that this input correctly produces a type error
expectType<string>(42)
```

### @ts-nocheck at File Level

```ts
// Flag: entire file opted out of type checking
// @ts-nocheck

// This is almost never acceptable in production code.
// The only valid use case is auto-generated files that cannot be manually typed.
```

### as unknown as TargetType — Double Assertion

```ts
// Flag: double assertion pattern that bypasses type compatibility
const typed = value as unknown as SpecificType
const element = ref.current as unknown as HTMLInputElement

// Double assertions are a sign that the developer couldn't satisfy the type checker
// legitimately. In most cases, the type needs to be fixed, not asserted around.
```

### Missing strict: true in tsconfig.json

```json
// Flag: strict mode disabled
{
  "compilerOptions": {
    "strict": false
  }
}

// Flag: individual strict checks disabled
{
  "compilerOptions": {
    "noImplicitAny": false,
    "strictNullChecks": false,
    "strictFunctionTypes": false
  }
}
```

`strict: true` enables: `noImplicitAny`, `strictNullChecks`, `strictFunctionTypes`, `strictBindCallApply`, `strictPropertyInitialization`, `noImplicitThis`, `alwaysStrict`. Disabling any of these creates systematic type safety holes.

### Generic Functions With Unconstrained any

```ts
// Flag: transform functions that use any as input and output
function transform(data: any): any {
  return data.items.map((item: any) => item.value)
}

// Flag: generic with any default
function processResponse<T = any>(response: T): T {
  return response
}

// Correct:
function transform<T extends { items: Array<{ value: string }> }>(data: T): string[] {
  return data.items.map(item => item.value)
}
```

### React Component Props Typed as any or object

```ts
// Flag: component props typed as any
function UserCard(props: any) {
  return <div>{props.name}</div>
}

// Flag: props typed as object (barely better than any — no property access safety)
function ProductList(props: object) {
  return <div>{(props as any).items}</div>  // forced to cast
}

// Correct:
type UserCardProps = { name: string; email: string; avatarUrl?: string }
function UserCard({ name, email, avatarUrl }: UserCardProps) { ... }
```

### Event Handlers Typed as any

```ts
// Flag: event handler with any
const handleClick = (e: any) => {
  e.target.value  // no type safety
}

const handleChange = (event: any) => {
  setName(event.target.value)
}

// Correct:
const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => { ... }
const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
  setName(e.target.value)
}
```

### any in Auth/Payment Boundaries

Pay special attention to `any` at security-critical boundaries:

```ts
// Flag: auth middleware where user type is any
declare global {
  namespace Express {
    interface Request {
      user?: any  // auth user typed as any — all downstream access is untyped
    }
  }
}

// Flag: payment amount untyped
async function createCharge(amount: any, currency: any) {
  // No type safety on financial values
}
```

## Severity Classification

**High**
- `strict: false` in tsconfig.json — affects entire codebase
- `noImplicitAny: false` in tsconfig.json
- `any` at auth or payment route handler boundaries
- Untyped API responses at auth endpoints (`fetch('/api/login').then(r => r.json())` with no type)
- `@ts-nocheck` at file level in production source files

**Medium**
- `as any` type assertions to access properties (indicates broken type definition)
- `as unknown as TargetType` double assertions
- `JSON.parse()` without type annotation or runtime validation
- Generic functions with `any` input/output in business logic
- React component props typed as `any`
- `@ts-ignore` or `@ts-expect-error` without explanatory comment

**Low**
- `any` in internal utility functions with limited scope
- Event handler `(e: any)` where event type is complex but low risk
- Untyped API responses on non-sensitive endpoints (correctness issue, lower security risk)

## Finding Format

```
🟠 HIGH | strict: false in tsconfig | tsconfig.json:8
strict mode is disabled. This silently allows implicit any, missing null checks, and loose function types throughout the codebase.
Fix: Set "strict": true. Address any new errors — they represent real type gaps that were previously hidden.

🟠 HIGH | Untyped Auth Response | src/lib/auth.ts:34
const data = await res.json() — response from /api/login has no type annotation. Session tokens and user data are typed as any throughout this flow.
Fix: Define a LoginResponse type and annotate: const data: LoginResponse = await res.json(). Add runtime validation with zod for external data.

🟡 MEDIUM | any Type Assertion | src/api/handlers/users.ts:67
(response as any).internalId bypasses type checking. If the response shape changes, this fails at runtime with no compile-time warning.
Fix: Update the Response type to include internalId, or use a type guard to safely access it.

🟡 MEDIUM | Untyped JSON.parse | src/config/loader.ts:12
JSON.parse(configString) infers any. If the config shape is wrong, errors surface at runtime.
Fix: Validate with zod: const config = AppConfigSchema.parse(JSON.parse(configString)) or add a type annotation.

🟡 MEDIUM | @ts-ignore Without Reason | src/utils/legacy.ts:89
// @ts-ignore with no explanation. Unknown what error is suppressed — may be hiding a real bug.
Fix: Add a comment explaining why this suppression is necessary. If no good reason exists, fix the underlying type error.

🔵 LOW | Event Handler any | src/components/SearchBar.tsx:23
(e: any) in onChange handler. Loses type safety for event.target.value.
Fix: Type as (e: React.ChangeEvent<HTMLInputElement>) => void
```

## Common False Positives

Do NOT flag:
- `any` in `.d.ts` declaration files for third-party library compatibility shims
- `any` in test files (`*.test.*`, `*.spec.*`) used for mocking
- `// @ts-ignore` or `// @ts-expect-error` with a clear comment explaining the third-party issue
- `as unknown as TargetType` in well-typed test utilities (type test infrastructure)
- `eslint-disable @typescript-eslint/no-explicit-any` with a documented reason
- `any` in auto-generated files (database type generators, protobuf outputs, OpenAPI codegen)
- `JSON.parse` with an immediate type annotation on the variable: `const config: AppConfig = JSON.parse(str)` — not ideal but better than bare any

## Stack-Specific Notes

**Next.js App Router**: `params` and `searchParams` in page components are typed by Next.js — do not add `any` to them. `req.json()` in Route Handlers should be typed: `const body: RequestBody = await req.json()`.

**tRPC**: The point of tRPC is end-to-end type safety. `any` in a tRPC router input or output type defeats this entirely. Flag immediately.

**Prisma**: `prisma.$queryRaw` returns `unknown[]` (correct) — do not cast to `any[]`. Use `Prisma.validator()` for typed raw queries.

**React Query / TanStack Query**: `useQuery<DataType>` should always have the generic type parameter specified. `useQuery({ queryFn: () => fetch(...).then(r => r.json()) })` without a type infers `any` for the data field.

**Zod**: If the project uses zod, untyped `JSON.parse` is especially egregious — the team has already bought into runtime validation and is inconsistently applying it.

**GraphQL codegen**: Auto-generated types from GraphQL codegen are the correct source of truth. If developers add `any` assertions over generated types, flag it — the correct fix is to update the query or the codegen config.
