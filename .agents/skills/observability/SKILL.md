---
name: observability
description: Use when the user is shipping anything to production, adding console.log for debugging, asking "why is this slow/broken?", wiring logging/tracing/metrics, or setting up alerts. Catches console.log in prod, missing trace IDs, alerting on symptoms instead of SLOs, and "we have no idea what happened" incidents.
---

# Observability

> If a user reports a bug at 3am, can you tell — within 5 minutes — exactly what request they made, what code path it took, and why it failed? If not, you don't have observability, you have logs.

## When to use
- About to ship anything to production
- Setting up logging, tracing, or metrics
- Adding `console.log` (replace with structured log immediately)
- Wiring an alert
- Diagnosing a slow or flaky path
- Reviewing what happens when an incident hits

## When to skip
- Throwaway scripts and one-off tooling

## The three pillars (and which to reach for first)

| | What | When to reach for it |
|---|---|---|
| **Logs** | structured records of events | "what happened on this request?" |
| **Metrics** | numbers over time | "how often, how slow, how many errors?" |
| **Traces** | request → spans across services | "where did the time go in this slow request?" |

Default: **structured logs first**, **traces for any request that crosses services**, **metrics for SLOs**. Don't skip straight to a fancy dashboard before you can answer "what happened in this request" from logs.

## The rules

### 1. No `console.log` in production code paths.

```ts
// BAD — unstructured, ungreppable, no level, no context
console.log('user signed up', user)

// GOOD — structured, queryable, leveled
import { logger } from '@/lib/logger'
logger.info({ userId: user.id, plan: user.plan, requestId }, 'user.signed_up')
```

Picks: **Pino** (Node), **Logtape** (cross-runtime, edge-friendly), **@vercel/otel** for built-in. Whatever you pick, **structured JSON** is non-negotiable.

### 2. Every log line gets a request ID.

```ts
// In a middleware or at the top of every handler
const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
const log = logger.child({ requestId })
// pass `log` down, or attach to async-local-storage
```

The `requestId` is also returned in the response (`x-request-id` header). When a user pastes it in a bug report, you `grep` that ID and see every log line for the request — across web, API, jobs, and downstream services.

### 3. Use levels with intent.

| Level | Use for |
|---|---|
| `trace` / `debug` | Local development; stripped in prod by config |
| `info` | Normal events: request received, job completed, user action |
| `warn` | Recoverable issues: retry, fallback engaged, deprecated path used |
| `error` | Unexpected failure that affected this request |
| `fatal` | Process going down |

Don't `error`-level things that are normal (a 404 from a missing-user lookup is `info`). Alert thresholds depend on level being meaningful.

### 4. Log the entire `Error` object, not its message.

```ts
// BAD — loses stack trace, loses cause chain
logger.error('failed: ' + err.message)

// GOOD — modern loggers serialize Error properly via `err.cause`
logger.error({ err, requestId, userId }, 'job.failed')
```

### 5. Distributed traces with OpenTelemetry. Not provider-locked SDKs.

```ts
// instrumentation.ts
import { registerOTel } from '@vercel/otel'
registerOTel({ serviceName: 'web' })
```

OTel emits a vendor-neutral format. Honeycomb, Datadog, Grafana Tempo, AWS X-Ray, Jaeger — all consume it. Don't hand-write spans for everything; instrument the framework + your DB + outbound HTTP, and let auto-instrumentation cover the rest.

### 6. Trace propagation across boundaries.

When you call another service, propagate the trace context:

```ts
// fetch automatically forwards `traceparent` if OTel is wired correctly
const res = await fetch('https://internal.api/x', { headers: { ... } })
```

For background jobs, include the trace context in the job payload; resume it in the worker. Otherwise the trace is broken at every async boundary and you can't see the whole request.

### 7. Metrics: **RED** for services, **USE** for resources.

**RED** (per service/endpoint):
- **R**ate (requests per second)
- **E**rrors (errors per second)
- **D**uration (latency, p50/p95/p99)

**USE** (per resource: CPU, DB connections, queue):
- **U**tilization
- **S**aturation
- **E**rrors

Build a dashboard with these for every service before you build anything fancier.

### 8. Alert on SLOs, not symptoms.

```
BAD:  alert if error_rate > 0% for 1 minute    →   pages you for every blip
BAD:  alert if cpu > 80%                       →   not a user-facing problem yet
GOOD: alert if (success_rate over 5 min) < 99.9% AND lasts > 5 min
GOOD: alert if p95_latency over 10 min > 500ms AND lasts > 10 min
```

An SLO-based alert pages you when **users are affected at a meaningful level**, not when a metric twitches. Consider error-budget burn rate (Google SRE handbook) for the right shape.

### 9. Cardinality discipline.

```ts
// BAD — every requestId becomes a metric label, blows up cardinality and your bill
metrics.increment('http.requests', { requestId, userId, url })

// GOOD — bounded label sets
metrics.increment('http.requests', {
  route: '/api/posts',     // bounded
  status: '200',           // bounded
  region: 'iad1',          // bounded
})
```

Put high-cardinality fields in **logs and traces** (where they belong), not in metric labels. A cardinality blowup can $$$ you instantly.

### 10. The dashboard you'd want at 3am, before 3am.

For each service: requests/sec, errors/sec, p95 latency, queue depth, DB connection pool, recent deploys overlaid. **Recent deploys overlaid** is the cheap superpower — most prod incidents are "what just changed."

### 11. Don't log sensitive data. Or log a redacted version.

```ts
// BAD
logger.info({ user, password: req.body.password }, 'login')

// GOOD — explicit allowlist of fields, or use a redactor
logger.info({ userId, email: redactEmail(email), ip }, 'login')
```

Most loggers (Pino) support `redact` paths. Configure once at the logger level so a junior dev's new log line can't leak. See `data-privacy`.

## What "good" looks like (minimum bar)

For every service before launch:

- Structured logs with `requestId`, `userId`, `route`, level, msg
- One trace per request (auto-instrumented for HTTP + DB + outbound)
- RED metrics dashboard + recent-deploy overlay
- One SLO-based alert ("availability < 99.5% for 5min" or similar)
- Logs and traces correlated via `requestId` and `traceparent`

## War story

A "background sync" job started failing silently after a deploy. Errors went to `console.log`. The platform's stdout retention was 24 hours and ungreppable. Three days later, customer reports come in: "data hasn't synced since Friday." The team spent six hours reconstructing the failure window from raw logs and DB state. Adding Pino + a `job.failed` alert took 30 minutes the next day and would have caught it within the hour.

## Quick checklist

- [ ] No `console.log` in prod code; use a structured logger
- [ ] `requestId` in every log line and echoed in the response header
- [ ] Log levels used with intent; expected events not at `error`
- [ ] Errors logged with `{ err }` (full Error object), not `err.message`
- [ ] OpenTelemetry instrumentation enabled; traces flow across services and jobs
- [ ] RED dashboard per service with deploy markers
- [ ] SLO-based alerts (sustained, multi-window), not symptom-twitch alerts
- [ ] Metric labels are low-cardinality
- [ ] Sensitive fields redacted at the logger level
