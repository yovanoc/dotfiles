---
name: api-route-hardening
description: Use when the user creates a route handler, Server Action, RPC endpoint, or any HTTP endpoint that mutates state or accepts user input. Covers rate limiting, body-size caps, request timeouts, idempotency keys, error response contracts, and method/CORS hygiene.
---

# API Route Hardening

> Every endpoint is a tiny program that strangers can run as many times as they want. Treat it that way.

## When to use
- Creating a new `route.ts`, Server Action, or HTTP endpoint
- Adding a public-facing API
- Reviewing existing endpoints before launch
- Anywhere a `POST`/`PUT`/`PATCH`/`DELETE` exists without rate limits

## When to skip
- Static page rendering with no endpoint
- Internal-only endpoints behind a private network *with* mTLS or VPC enforcement (rare)

## The hardening stack

Every endpoint that mutates or costs money goes through this in order:

1. **Method check** → reject anything other than the intended verb
2. **Body size limit** → reject before parsing
3. **Authentication** → who is the caller
4. **Authorization** → may they do this (see `authorization`)
5. **Rate limit** → per-IP and/or per-user, before expensive work
6. **Input validation** → Zod parse (see `input-validation`)
7. **Idempotency check** (mutations) → has this exact request already been processed?
8. **The actual work**
9. **Structured response** → consistent error/success contract

## The rules

### 1. Rate limit every mutating endpoint. And every expensive read.

Use Upstash Ratelimit, Cloudflare Rate Limiting, or your platform's built-in. **Sliding window** for general endpoints, **token bucket** for bursty workloads.

```ts
import { Ratelimit } from '@upstash/ratelimit'
import { Redis } from '@upstash/redis'

const limiter = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(20, '60 s'), // 20 req / min / key
  analytics: true,
})

export async function POST(req: Request) {
  const ip = req.headers.get('x-forwarded-for') ?? 'anonymous'
  const { success } = await limiter.limit(`signup:${ip}`)
  if (!success) return new Response('Too many requests', { status: 429 })
  // ...
}
```

Limit by **the most specific identifier you have**: user ID > session ID > IP. Per-route, not global. Stricter limits on auth/reset/invite endpoints (see `auth-and-sessions`).

### 2. Cap request body size. Before parsing.

The default in many frameworks is 1MB or larger. For a `POST /api/notes` you probably want 100KB.

```ts
// Next.js Route Handler
const MAX = 100 * 1024
const len = Number(req.headers.get('content-length') ?? 0)
if (len > MAX) return new Response('Payload too large', { status: 413 })
```

For uploads, use signed URLs (see `file-uploads`) — never proxy the bytes through your server.

### 3. Set a request timeout. The platform default is too long.

A handler that hangs on a slow third-party call holds a connection slot until something kills it. Set per-request timeouts; use `AbortSignal.timeout(ms)` for outbound calls (see `reliability-patterns`).

### 4. Idempotency keys on every mutating endpoint that costs money or sends a side effect.

```ts
// Client sends Idempotency-Key: <uuid>
const key = req.headers.get('Idempotency-Key')
if (!key) return new Response('Missing Idempotency-Key', { status: 400 })

const existing = await db.idempotencyKey.findUnique({ where: { key } })
if (existing) return Response.json(existing.response, { status: existing.status })

// ... do the work ...

await db.idempotencyKey.create({
  data: { key, status: 200, response: result, expiresAt: addDays(new Date(), 1) },
})
```

Why: client retries (network blip, user double-click, queue redelivery) must not double-charge, double-send, or double-create. Stripe-style — they made this the norm because they had to.

### 5. Reject the wrong method. Explicitly.

```ts
// Next.js: only export the verbs you support; others auto-405. Good.
// Express: add an explicit `app.all('/path', methodNotAllowed)`.
```

A `GET` to a `POST`-only endpoint should never reach business logic. Same with `OPTIONS` preflights — let the framework handle CORS, don't hand-roll.

### 6. Stable error contract. JSON, not strings.

```ts
// BAD
return new Response('something went wrong', { status: 500 })

// GOOD
return Response.json(
  { error: { code: 'invoice_not_found', message: 'No invoice with that ID.' } },
  { status: 404 },
)
```

Codes are stable identifiers your client can branch on. Messages are human-readable but **never include internals** (stack traces, SQL, secrets — see `secrets-and-env`).

### 7. CORS: allowlist, not `*`.

```ts
// BAD
'Access-Control-Allow-Origin': '*'
'Access-Control-Allow-Credentials': 'true' // browsers actually reject this combo, but people try

// GOOD — allowlist of known origins, or omit if same-origin
const ALLOWED = new Set(['https://app.example.com', 'https://example.com'])
const origin = req.headers.get('origin')
if (origin && ALLOWED.has(origin)) {
  headers.set('Access-Control-Allow-Origin', origin)
  headers.set('Vary', 'Origin')
}
```

### 8. Pagination: cursor-based, not offset-based, for anything that grows.

```ts
// BAD — offset gets slower as N grows, drifts when rows are inserted
db.post.findMany({ skip: 1000, take: 20 })

// GOOD — cursor is stable and fast
db.post.findMany({
  take: 20,
  ...(cursor && { skip: 1, cursor: { id: cursor } }),
  orderBy: { id: 'desc' },
})
```

Always cap `limit` (e.g., `max 100`). See `database-query-safety`.

### 9. Don't return raw DB rows.

Map DB → DTO at the response boundary. Otherwise adding a field to the schema (`internalNotes`, `passwordHash`, `stripeCustomerId`) silently leaks it to clients.

```ts
return Response.json({
  id: user.id,
  name: user.name,
  email: user.email,
  // not: ...user
})
```

### 10. Add a `request_id` to every response and every log.

```ts
const requestId = crypto.randomUUID()
logger.info({ requestId, route: '/api/x', userId })
return Response.json(data, { headers: { 'x-request-id': requestId } })
```

When a user reports a bug, they paste the request ID and you find every log line for that request in seconds. See `observability`.

## War story

An indie SaaS shipped `POST /api/contact` with no rate limit. A scraper found it, sent 80k requests in two hours through their Resend integration. $400 in transactional email costs, IP reputation tanked, deliverability dropped for two weeks across all customers. A 5-line Upstash limiter would have stopped it at request 21.

## Quick checklist

- [ ] Rate limit per-IP and per-user, scoped to the route
- [ ] Body size cap before parsing
- [ ] Auth + authz before any work
- [ ] Zod-parsed input (see `input-validation`)
- [ ] Idempotency key for charges, emails, and other irreversible side effects
- [ ] Stable JSON error contract with codes
- [ ] CORS allowlist, not `*`
- [ ] Cursor pagination with a max limit
- [ ] Response DTOs, not raw DB rows
- [ ] `x-request-id` echoed on every response and in every log line
