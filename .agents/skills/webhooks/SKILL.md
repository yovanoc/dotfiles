---
name: webhooks
description: Use when the user is receiving webhooks (Stripe, GitHub, Slack, Clerk, Polar, Resend, Linear, Polar, custom), building a webhook endpoint, or signing webhooks for someone else. Catches missing signature verification, missing idempotency, sync handlers that time out, and replay vulnerabilities.
---

# Webhooks

> A webhook URL is a public endpoint that strangers will POST to. The sender is whoever can guess the URL — until you verify the signature.

## When to use
- Building a webhook receiver: `POST /api/webhooks/stripe`, `/api/webhooks/github`, etc.
- Adding a new third-party integration that calls back
- Reviewing a webhook handler before launch
- Sending webhooks *out* (your service notifying customer servers)

## When to skip
- Pure outbound API calls (you call them, they don't call you back asynchronously)

## The five rules every webhook receiver must follow

1. **Verify the signature.** Reject if absent or wrong.
2. **Check the timestamp.** Reject if too old (replay protection).
3. **Idempotent by event ID.** Same event delivered twice → no double effects.
4. **Acknowledge fast (`200` quickly), process async.** Don't do heavy work inside the handler.
5. **Don't echo the payload back.** It's not your data; don't log secrets it carries.

Every receiver, every time. No exceptions.

## The patterns

### 1. Signature verification — use the provider's library, not your own.

Each provider has subtle rules about what's signed (raw body? headers? URL?), what hash, what header name. Roll-your-own gets it wrong.

```ts
// Stripe (Next.js Route Handler)
import Stripe from 'stripe'
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

export async function POST(req: Request) {
  const sig = req.headers.get('stripe-signature')
  if (!sig) return new Response('No sig', { status: 400 })

  const rawBody = await req.text() // RAW body, not parsed JSON
  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET!)
  } catch {
    return new Response('Bad sig', { status: 400 })
  }
  // ...
}
```

The critical detail: **raw bytes**. If you `await req.json()` first and re-serialize, the signature won't match — JSON serialization isn't byte-stable. Always work from `req.text()` for the verification.

### 2. Reject too-old events — replay protection.

Even with a valid signature, an attacker who captured a webhook delivery (e.g. via misconfigured logging) can replay it. Most providers include a timestamp; reject if outside a window.

```ts
const now = Math.floor(Date.now() / 1000)
if (Math.abs(now - event.created) > 5 * 60) { // 5-minute tolerance
  return new Response('Stale event', { status: 400 })
}
```

### 3. Idempotent by event ID. Persist the dedup record.

Webhooks are at-least-once. The same event will arrive twice. Sometimes hours apart.

```ts
const seen = await db.processedWebhook.findUnique({ where: { id: event.id } })
if (seen) return new Response(null, { status: 200 })

await db.$transaction(async (tx) => {
  await processEvent(tx, event)
  await tx.processedWebhook.create({ data: { id: event.id, source: 'stripe', at: new Date() } })
})

return new Response(null, { status: 200 })
```

Dedup record + business write **in the same transaction**, otherwise a crash mid-transaction causes either double-processing or "we said we processed it but didn't."

### 4. Acknowledge fast. Process async.

Many providers retry if you don't respond in <5–10 seconds. If your handler does heavy work synchronously, retries pile up, you process the same event multiple times concurrently, and inboxes fill with "did this ship?" emails.

```ts
export async function POST(req: Request) {
  const event = verify(req) // signature + timestamp + parse

  // Enqueue a background job; return immediately
  await queue.send({ kind: 'stripe.event', payload: event })
  return new Response(null, { status: 200 })
}
```

The worker does the heavy lifting, with full retry semantics (see `jobs-and-queues`). The handler is small and fast.

### 5. Don't trust the payload's `customer_id`. Look it up.

Even with a valid signature, never trust IDs that should map to your data without checking. Look them up; reject events for unknown / wrong-tenant IDs.

```ts
const sub = await db.subscription.findUnique({ where: { stripeCustomerId: event.data.object.customer } })
if (!sub) return new Response('Unknown customer', { status: 200 }) // 200 so Stripe doesn't retry
```

### 6. 2xx tells the sender "stop retrying." Use it deliberately.

| Situation | Status |
|---|---|
| Processed (or already-processed dedup hit) | `200` |
| Bad signature | `400` |
| Body malformed | `400` |
| Unknown event type you ignore on purpose | `200` (or `202`), with a log |
| Transient internal failure (DB down) | `5xx` — let the sender retry |
| Permanent internal failure (data inconsistent, terminal) | `200` + alert; do not loop forever |

Returning `5xx` for "we don't care about this event type" causes the sender to retry forever, eventually filling their internal DLQ and getting your endpoint disabled.

### 7. Order is not guaranteed.

Webhooks can arrive out of order: `subscription.deleted` before `subscription.updated`. Don't assume the latest delivered = latest reality. Either:
- Re-fetch from the provider's API to get current state
- Store a `version` / `seq` on the event and ignore older versions

For Stripe specifically, the docs explicitly say to fetch state from their API rather than rely on event order.

### 8. Webhook secret rotation. Plan for it.

Most providers let you rotate the signing secret with overlap (old + new both valid for a window). Use it: deploy new secret env var, both verify, rotate via provider, remove old. **Test the rotation in staging first**.

### 9. Per-source endpoints. Don't multiplex.

```
POST /api/webhooks/stripe
POST /api/webhooks/github
POST /api/webhooks/clerk
```

Not `/api/webhooks` that branches on a body field. Per-source URLs let each have its own secret, signature scheme, and handler — without scary `if-else` logic.

### 10. Edge runtime needs a body-stable read.

Some edge runtimes parse `request.json()` lazily; reading body twice fails. Always: `const raw = await req.text()`, verify on `raw`, parse with `JSON.parse(raw)` if you need the object after.

## Sending webhooks (you → customer)

If you're the sender:

- Sign with HMAC-SHA256 of the body + a timestamp; expose the secret in their dashboard
- Include a unique `event_id` and `created_at` in every payload
- Retry on `5xx` and timeouts with exponential backoff
- Stop after N attempts; record in a DLQ; surface in the customer's dashboard
- Set a tight timeout (5–10s); customer endpoints that hang shouldn't pin your workers
- Document the IPs you send from (so customers can allowlist) — or use a fixed proxy

## War story

A vibe-coded SaaS took Stripe webhooks and credited account balances in the handler. They forgot to verify the signature ("Stripe wouldn't fake their own webhooks, right?"). A bad actor noticed the URL in their HAR file, crafted a fake `payment_intent.succeeded` payload, and credited their own account $50,000. The fix was 6 lines (Stripe's `constructEvent`). The cost was 2 days of account-by-account reconciliation and a public-facing apology.

## Quick checklist

- [ ] Signature verified using the provider's library on the **raw body**
- [ ] Timestamp / event-age check rejects replays
- [ ] Idempotency dedup by event ID, persisted alongside the business write
- [ ] Heavy work moved to a queue; handler is small and fast
- [ ] Resource IDs in the payload are looked up + scoped (not trusted)
- [ ] Status codes used deliberately (200 for "don't retry", 5xx only for transient)
- [ ] Out-of-order delivery handled (re-fetch or version check)
- [ ] Webhook secrets are server-only env vars; rotation tested
- [ ] One endpoint per source; no multiplexing
- [ ] Body read once via `req.text()`; verified, then parsed
