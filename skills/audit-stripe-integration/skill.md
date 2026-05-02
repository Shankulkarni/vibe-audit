---
name: audit-stripe-integration
description: Audit Stripe integrations for webhook security, key management, and payment integrity gaps
triggers: [stripe, stripe-js, webhook, payment, checkout, subscription, billing, sk_live, sk_test, stripe-webhook]
---

# Audit: Stripe Integration

## Purpose

Stripe integrations from AI generators fail in two consistent ways: webhook handling is missing signature verification (allowing fake events to trigger fulfillment), and payment amounts are set client-side or not verified server-side (enabling price manipulation). These are not theoretical — they are the most common real-world payment vulnerabilities in production apps.

## What to Look For

### Missing Webhook Signature Verification

The most critical Stripe integration flaw. Any webhook endpoint that does not call `stripe.webhooks.constructEvent()` or `constructEventAsync()` before processing the event is vulnerable to forged webhooks:

```ts
// Flag: CRITICAL — webhook handler with no signature verification
app.post('/webhooks/stripe', express.json(), async (req, res) => {
  const event = req.body  // trusting unverified event payload
  
  if (event.type === 'checkout.session.completed') {
    await fulfillOrder(event.data.object.metadata.orderId)  // fraud possible
  }
  res.json({ received: true })
})

// Correct pattern:
app.post('/webhooks/stripe', express.raw({ type: 'application/json' }), async (req, res) => {
  const sig = req.headers['stripe-signature']
  let event: Stripe.Event
  
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET)
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${(err as Error).message}`)
  }
  
  switch (event.type) {
    case 'checkout.session.completed':
      await fulfillOrder(event.data.object)
      break
  }
  res.json({ received: true })
})
```

### express.json() Before Webhook Route — Raw Body Problem

Stripe signature verification requires the raw, unmodified request body. If `express.json()` or `bodyParser.json()` middleware runs before the webhook route, it parses the body into an object and signature verification will always fail (or you lose the raw body):

```ts
// Flag: json middleware applied globally before webhook route
app.use(express.json())  // runs for all routes including /webhook

app.post('/webhook', async (req, res) => {
  // req.body is now a parsed object, not the raw buffer
  const event = stripe.webhooks.constructEvent(
    req.body,  // WRONG: should be raw Buffer, not parsed object
    req.headers['stripe-signature'],
    process.env.STRIPE_WEBHOOK_SECRET
  )
})

// Correct: apply raw body parser specifically to webhook route
app.post('/webhook', express.raw({ type: 'application/json' }), webhookHandler)
// And either don't use global json() or exclude the webhook path from it
```

### Stripe Secret Key in Client-Side Code

```ts
// Flag: CRITICAL — sk_live_ or sk_test_ in browser-executed code
// In a React component, Next.js client component, or any browser file:
const stripe = new Stripe(process.env.NEXT_PUBLIC_STRIPE_SECRET_KEY)  // exposed in bundle

// Flag: NEXT_PUBLIC_ prefix on secret key
// .env file:
// NEXT_PUBLIC_STRIPE_SECRET_KEY=sk_live_...  → embedded in browser bundle

// Secret keys (sk_) must only appear in server-side code
// Publishable keys (pk_) are safe for client-side use

// Correct server-side:
import Stripe from 'stripe'
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)  // server-only file
```

### Customer ID Not Tied to Authenticated User

```ts
// Flag: user can manipulate customer ID to access another user's data
app.get('/api/subscription', authenticate, async (req, res) => {
  const { customerId } = req.body  // user-supplied customer ID!
  const subscription = await stripe.subscriptions.list({ customer: customerId })
  res.json(subscription)
})

// Correct: always look up customer ID from your own DB using authenticated user's ID
app.get('/api/subscription', authenticate, async (req, res) => {
  const user = await db.users.findById(req.user.id)
  const subscription = await stripe.subscriptions.list({ customer: user.stripeCustomerId })
  res.json(subscription)
})
```

### Missing Idempotency Keys on Payment Operations

```ts
// Flag: charge creation without idempotency key
const paymentIntent = await stripe.paymentIntents.create({
  amount: 2000,
  currency: 'usd',
})
// If the network request fails and retries, this can create duplicate charges

// Correct: use idempotency key tied to the order/operation
const paymentIntent = await stripe.paymentIntents.create(
  { amount: 2000, currency: 'usd' },
  { idempotencyKey: `order_${orderId}_payment` }
)
```

Flag absence of idempotency keys on: `stripe.paymentIntents.create()`, `stripe.charges.create()`, `stripe.subscriptions.create()`, `stripe.invoices.pay()`.

### Price/Amount Set Client-Side

```ts
// Flag: CRITICAL — amount determined by client and sent to server
// Client-side code:
const response = await fetch('/api/create-payment', {
  method: 'POST',
  body: JSON.stringify({ amount: cartTotal, items: cart })
})

// Server-side:
app.post('/api/create-payment', async (req, res) => {
  const { amount } = req.body  // trusting client-reported amount!
  const paymentIntent = await stripe.paymentIntents.create({
    amount,  // price manipulation: client sends amount: 1 for a $99 item
    currency: 'usd',
  })
})

// Correct: calculate amount server-side from order data
app.post('/api/create-payment', authenticate, async (req, res) => {
  const { items } = req.body
  const amount = await calculateOrderTotal(items)  // server-side calculation
  const paymentIntent = await stripe.paymentIntents.create({ amount, currency: 'usd' })
})
```

### Payment Intent Not Verified Server-Side Before Fulfillment

```ts
// Flag: trusting client-reported payment success
// Client sends: { paymentIntentId: 'pi_...', status: 'succeeded' }
app.post('/api/confirm-order', async (req, res) => {
  if (req.body.status === 'succeeded') {  // trusting client!
    await fulfillOrder(req.body.orderId)
  }
})

// Correct: verify payment intent status server-side
app.post('/api/confirm-order', authenticate, async (req, res) => {
  const paymentIntent = await stripe.paymentIntents.retrieve(req.body.paymentIntentId)
  if (paymentIntent.status !== 'succeeded') {
    return res.status(400).json({ error: 'Payment not confirmed' })
  }
  await fulfillOrder(req.body.orderId)
})
```

### Missing Stripe Webhook Secret in Environment

```ts
// Flag: webhook handler that uses an empty or undefined webhook secret
stripe.webhooks.constructEvent(
  payload,
  sig,
  process.env.STRIPE_WEBHOOK_SECRET  // may be undefined in misconfigured environment
)
// If undefined, constructEvent may succeed with any signature

// Check: is STRIPE_WEBHOOK_SECRET validated at startup?
if (!process.env.STRIPE_WEBHOOK_SECRET) {
  throw new Error('STRIPE_WEBHOOK_SECRET is required')
}
```

### Test Keys in Production Code or Committed to Git

```ts
// Flag: test key in source code
const stripe = new Stripe('sk_test_...')  // hardcoded test key in source

// Flag: .env files committed to git with Stripe keys
// Check .gitignore for .env exclusion

// Flag: test key as default fallback in production config
const STRIPE_KEY = process.env.STRIPE_SECRET_KEY || 'sk_test_abc123'
```

### Missing Event Type Checking in Webhook Handler

```ts
// Flag: webhook handler that processes events without checking the type
app.post('/webhook', rawBodyMiddleware, async (req, res) => {
  const event = stripe.webhooks.constructEvent(...)
  
  // No event.type switch — processes all events the same way
  await fulfillOrder(event.data.object.metadata.orderId)
  // What if event.type is 'payment_intent.payment_failed'?
})

// Correct: always handle specific event types
switch (event.type) {
  case 'checkout.session.completed':
    await handleCheckoutComplete(event.data.object as Stripe.Checkout.Session)
    break
  case 'payment_intent.payment_failed':
    await handlePaymentFailed(event.data.object as Stripe.PaymentIntent)
    break
  default:
    console.log(`Unhandled event type: ${event.type}`)
}
```

### Subscription Status Not Checked on Protected Routes

```ts
// Flag: premium feature accessible to all authenticated users, not just active subscribers
app.get('/api/premium/export', authenticate, async (req, res) => {
  // No subscription status check
  const data = await getExportData(req.user.id)
  res.json(data)
})

// Correct: verify subscription is active
app.get('/api/premium/export', authenticate, async (req, res) => {
  const subscription = await db.subscriptions.findByUserId(req.user.id)
  if (!subscription || subscription.status !== 'active') {
    return res.status(403).json({ error: 'Active subscription required' })
  }
  const data = await getExportData(req.user.id)
  res.json(data)
})
```

## Severity Classification

**Critical**
- Webhook handler with no signature verification (`constructEvent` not called)
- `sk_live_` secret key in client-side code or with `NEXT_PUBLIC_` prefix
- Price/amount sent from client and used without server-side recalculation

**High**
- `express.json()` parsing body before webhook route (breaks signature verification)
- Customer ID from user request without DB lookup validation
- Missing idempotency keys on charge/payment creation
- Payment intent status not verified server-side before fulfillment

**Medium**
- Test keys hardcoded in source code
- `STRIPE_WEBHOOK_SECRET` env var not validated at startup
- Missing event type switch/check in webhook handler

**Low**
- Subscription status not checked on gated routes (may be intentional)
- Missing webhook event handling for failure/refund events (correctness, not security)

## Finding Format

```
🔴 CRITICAL | No Webhook Signature Verification | src/app/api/webhooks/stripe/route.ts:8
Webhook handler processes Stripe events without calling stripe.webhooks.constructEvent(). Attackers can send forged events to trigger fulfillment without payment.
Fix: Parse the raw body, verify the stripe-signature header:
  const event = stripe.webhooks.constructEvent(rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET)

🔴 CRITICAL | Secret Key in Client | src/components/Checkout.tsx:3
NEXT_PUBLIC_STRIPE_SECRET_KEY is used to initialize Stripe client-side. sk_ keys are embedded in the browser bundle and visible to anyone.
Fix: Move Stripe API calls to server routes. Use NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY (pk_) for client-side Stripe.js initialization only.

🔴 CRITICAL | Client-Side Price | src/app/api/create-payment/route.ts:15
amount from req.body is used directly in stripe.paymentIntents.create(). Clients can set amount: 1 to pay $0.01 for any item.
Fix: Calculate amount server-side using the item IDs from the request: const amount = await calculateTotal(itemIds)

🟠 HIGH | Raw Body Destroyed | src/app.ts:8
app.use(express.json()) is applied globally before the webhook route. The raw body needed for signature verification is lost.
Fix: Move the webhook route above the global json middleware, or exclude it: app.use((req, res, next) => req.path === '/webhook' ? next() : express.json()(req, res, next))

🟠 HIGH | User-Supplied Customer ID | src/api/subscription.ts:22
customerId from request body is used to fetch subscription data. Any user can access any customer's subscription by guessing an ID.
Fix: Look up stripeCustomerId from your database using the authenticated user's ID: const user = await db.users.findById(req.user.id)

🟡 MEDIUM | Missing Idempotency Key | src/services/billing.ts:45
stripe.paymentIntents.create() called without idempotencyKey. Network failures during charge creation can result in duplicate charges.
Fix: Add idempotency key: stripe.paymentIntents.create(params, { idempotencyKey: `charge_${orderId}` })

🟡 MEDIUM | No Webhook Event Type Check | src/webhooks/handler.ts:34
Webhook handler calls fulfillOrder() without checking event.type. Failed payment events will also trigger fulfillment.
Fix: Add event.type switch before processing and only fulfill on 'checkout.session.completed' or 'payment_intent.succeeded'.
```

## Common False Positives

Do NOT flag:
- `stripe.webhooks.constructEvent()` with a variable name that doesn't literally say `STRIPE_WEBHOOK_SECRET` — check the actual value source, not the variable name
- `sk_test_` keys in test files, `.env.test`, or local development configs that are gitignored
- Client-side use of `Stripe()` constructor with a publishable key (`pk_live_` or `pk_test_`) — this is correct
- `stripe.customers.retrieve(customerId)` in admin/internal tools where admin auth is already verified
- Metadata amounts stored on PaymentIntent — the amount is on the PaymentIntent object itself which is authoritative; metadata is acceptable for order reference data

## Stack-Specific Notes

**Next.js App Router**: Webhook routes should use `export const runtime = 'nodejs'` — the Edge Runtime does not support reading raw request bodies via `req.body` as a Buffer. Use `await req.text()` or `await req.arrayBuffer()` and convert to Buffer for signature verification.

**Next.js Pages Router**: In `pages/api/webhook.ts`, disable the default body parser: `export const config = { api: { bodyParser: false } }`. Then read the raw body manually.

**Express**: Use `express.raw({ type: 'application/json' })` on the webhook route specifically. Do NOT use `express.json()` before the webhook route.

**Vercel Functions**: `req.body` in Vercel serverless functions may already be parsed. Access the raw body via Vercel's raw body handling or use the `stripe` library's `constructEventFromPayload` if available.

**Stripe CLI for local testing**: `stripe listen --forward-to localhost:3000/api/webhooks` generates a local signing secret. Using this secret in development is correct — but the corresponding production secret must be in production env vars, not hardcoded.

**Stripe Checkout vs Payment Intents**: With Stripe Checkout, the amount is set server-side when creating the Session — this is inherently safe. Flag client-side amounts only for direct PaymentIntents or custom checkout flows.
