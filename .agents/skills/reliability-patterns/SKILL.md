---
name: reliability-patterns
description: Use when the user makes outbound HTTP calls, integrates a third-party API, calls an LLM/Stripe/email/SMS provider, or anywhere "the network might be slow or down." Covers timeouts, retries with jitter, circuit breakers, fallbacks, and the "what if their API is down at peak" question.
---

# Reliability Patterns

> Every outbound call is a tiny lottery ticket: usually fine, occasionally slow, sometimes broken. If your app falls over when a third-party hiccups, your reliability is *their* reliability — and you can't pick that.

## When to use
- Calling a third-party API (Stripe, OpenAI, Anthropic, Resend, Twilio, S3, etc.)
- Internal service-to-service HTTP calls
- Webhook *senders* (you calling someone else's URL)
- Anywhere a `fetch()` could block your handler
- Code that runs on a request path and depends on external availability

## When to skip
- Pure in-process logic
- Local-only operations

## The default for any outbound call

```ts
async function callPaymentApi(req: Request) {
  return fetch('https://api.payments.example/charge', {
    method: 'POST',
    body: JSON.stringify(req),
    headers: { 'Idempotency-Key': req.idempotencyKey },
    signal: AbortSignal.timeout(5_000), // ALWAYS a timeout
  })
}
```

The bare `fetch(url)` with no timeout is a bug. Set one. Always.

## The rules

### 1. Set a timeout. Tighter than you think.

```ts
// BAD — hangs forever if their server stalls. Holds your connection slot until the platform kills you.
await fetch(url)

// GOOD
await fetch(url, { signal: AbortSignal.timeout(3_000) })
```

Pick timeouts based on **what's reasonable for the user**, not what the upstream's worst case is. A 30-second timeout means a degraded upstream takes your whole app down with it.

Default: 3-5s for transactional calls, 10-15s for known-slow operations (LLM completions, file processing).

### 2. Retry transient failures. With jitter.

```ts
async function withRetry<T>(fn: () => Promise<T>, opts = { max: 3, base: 200 }): Promise<T> {
  for (let i = 0; i < opts.max; i++) {
    try { return await fn() }
    catch (err) {
      if (!isTransient(err) || i === opts.max - 1) throw err
      const delay = opts.base * 2 ** i * (0.5 + Math.random()) // jitter
      await new Promise((r) => setTimeout(r, delay))
    }
  }
  throw new Error('unreachable')
}

function isTransient(err: unknown) {
  if (err instanceof Error && err.name === 'AbortError') return true   // timeout
  if (err instanceof Error && err.name === 'TypeError') return true    // network
  const status = (err as any)?.status
  return status === 429 || status === 502 || status === 503 || status === 504
}
```

**Don't retry**: 4xx (other than 429), validation errors, "not found." They'll fail forever; retrying wastes resources and delays the real fix.

**Jitter is essential**: synchronized retries (every client retries at exactly 1s) DDoS the upstream when it comes back up. Add randomness.

### 3. Retries demand idempotency. No idempotency, no retry.

A retry of a non-idempotent call charges twice, sends two emails, creates two rows. Either:
- Make the call idempotent with an idempotency key (Stripe, Resend, your own — see `api-route-hardening`)
- Don't retry — return the error and let the caller decide

There is no third option that doesn't lose to either correctness or reliability.

### 4. Circuit breaker for chronic failures.

When an upstream is failing for many requests in a row, **stop calling it** for a window — let it recover instead of piling on.

```ts
// State: closed (normal) | open (fail-fast) | half-open (probe)
class CircuitBreaker {
  private failures = 0
  private state: 'closed' | 'open' | 'half-open' = 'closed'
  private openedAt = 0

  async exec<T>(fn: () => Promise<T>, opts = { threshold: 5, resetMs: 30_000 }): Promise<T> {
    if (this.state === 'open' && Date.now() - this.openedAt < opts.resetMs) {
      throw new Error('circuit_open')
    }
    if (this.state === 'open') this.state = 'half-open'

    try {
      const out = await fn()
      this.failures = 0
      this.state = 'closed'
      return out
    } catch (err) {
      this.failures++
      if (this.failures >= opts.threshold) {
        this.state = 'open'
        this.openedAt = Date.now()
      }
      throw err
    }
  }
}
```

In practice, use a battle-tested library (`opossum`, your service mesh, your platform) rather than handwriting. The pattern is the point.

### 5. Fallback. Or fail explicitly.

When the upstream is down or the breaker is open:

| Service | Fallback |
|---|---|
| Search | "Search temporarily unavailable" + cached results if any |
| Image CDN | Original URL or low-res placeholder |
| Analytics | Drop the event silently (analytics isn't core) |
| **Auth / payments / data write** | **No fallback. Fail loudly.** |

Pick fallback or fail-loud per dependency, deliberately. The wrong default is "swallow and keep going" everywhere — see `error-handling`.

### 6. Bulkhead: isolate resources per dependency.

If your `getUser` calls share a thread pool / connection pool with `searchPosts`, then a slow search backs up `getUser`. Use **separate pools** (or queues, or workers) per critical dependency.

In Node.js this is more about HTTP connection pools and async concurrency limits than threads. `p-limit` per upstream is a cheap form.

### 7. Concurrency limits on outbound.

Without one, a sudden burst of requests fan out unbounded outbound calls — overwhelms upstream, gets you rate-limited, takes your app down with it.

```ts
import pLimit from 'p-limit'
const limit = pLimit(20) // max 20 concurrent calls to upstream X

await Promise.all(items.map((i) => limit(() => callUpstream(i))))
```

### 8. Honor `Retry-After`.

When an upstream returns 429 or 503 with `Retry-After`, respect it. Don't immediately retry; wait the suggested duration (with some jitter).

### 9. Health checks check actual dependencies, not "200 OK."

```ts
// BAD — passes even if your DB is down
export async function GET() { return new Response('ok') }

// GOOD — checks load-bearing deps
export async function GET() {
  const [db, redis] = await Promise.allSettled([
    sql`SELECT 1`,
    redis.ping(),
  ])
  const ok = db.status === 'fulfilled' && redis.status === 'fulfilled'
  return Response.json({ ok, db: db.status, redis: redis.status }, { status: ok ? 200 : 503 })
}
```

Distinguish **liveness** (am I running?) from **readiness** (can I serve traffic?). Orchestrators use them differently.

### 10. Degrade gracefully, advertise the degradation.

If you've fallen back to cached data, surface it: "Showing data from 5 min ago — refresh failed." Hidden degradation builds false confidence; explicit degradation lets users (and you) make decisions.

## Where each pattern fits

| Pattern | Solves |
|---|---|
| Timeout | Slow upstream blocking your latency |
| Retry + backoff + jitter | Transient errors, rare blips |
| Idempotency | Making retry safe |
| Circuit breaker | Chronic upstream failure piling on |
| Fallback | User-visible degradation |
| Bulkhead / concurrency limit | One upstream's failure not eating your other capacity |
| Health checks | Orchestrator routing decisions |

## War story

A SaaS dashboard called four upstream APIs in parallel on every page load: payments, support, analytics, email-stats. One day the analytics provider had a 14-minute latency spike to 30s response times. The dashboard had no per-call timeout — every page load held a connection for 30s, the connection pool exhausted, and the *entire site* went down. The fix that day was a 3s timeout on each call (analytics gracefully shows "—" on timeout). Took 5 minutes to ship, took 14 minutes of outage to motivate.

## Quick checklist

- [ ] Every outbound `fetch` has a timeout (`AbortSignal.timeout`)
- [ ] Retries with exponential backoff + jitter, only for transient errors
- [ ] Retried calls are idempotent (idempotency key or natural idempotency)
- [ ] Circuit breaker on upstreams known to chronically misbehave
- [ ] Deliberate fallback (or deliberate fail-loud) per dependency
- [ ] Concurrency limit on parallel outbound calls
- [ ] `Retry-After` honored
- [ ] Health checks verify real dependencies (DB, cache)
- [ ] Degraded mode is visible to the user, not hidden
