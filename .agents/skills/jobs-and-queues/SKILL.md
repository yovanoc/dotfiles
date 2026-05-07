---
name: jobs-and-queues
description: Use when the user schedules a cron, ships a worker, sends an email/SMS asynchronously, processes uploads, builds a "do this in the background" flow, or any task that takes more than a second. Covers idempotent handlers, retries with backoff, dead-letter queues, the "exactly once" myth, and visibility timeouts.
---

# Background Jobs & Queues

> A queue is a network. The network is unreliable. Your job will run twice. Sometimes zero times. Plan for that.

## When to use
- Sending email / SMS / push notifications asynchronously
- Image / video / file processing
- Scheduled jobs (daily reports, billing runs, cleanup)
- Webhook receivers that fan out work (see `webhooks`)
- Any HTTP request handler that takes >1s and doesn't *need* to be sync
- Data backfills, large imports/exports, search index updates

## When to skip
- Operations that genuinely complete in <100ms with no I/O
- One-off scripts run by humans

## The two truths

1. **"Exactly once" doesn't exist.** Every queue is "at least once" — sometimes "at most once" if you accept losing messages. Build handlers that survive being run twice.
2. **A job that crashed mid-run will be retried.** It must be safe to retry from any point.

These two truths reduce to one rule: **make every handler idempotent.**

## The rules

### 1. Idempotent handlers, always.

```ts
// BAD — retried = duplicate email sent
async function handleSignupEmail(userId: string) {
  const user = await db.user.findUnique({ where: { id: userId } })
  await resend.emails.send({ to: user.email, subject: 'Welcome', ... })
}

// GOOD — second run is a no-op
async function handleSignupEmail(userId: string) {
  const user = await db.user.findUnique({ where: { id: userId } })
  const already = await db.emailLog.findUnique({
    where: { userId_kind: { userId, kind: 'signup_welcome' } },
  })
  if (already) return
  const sent = await resend.emails.send({
    to: user.email,
    subject: 'Welcome',
    headers: { 'Idempotency-Key': `welcome:${userId}` },
  })
  await db.emailLog.create({ data: { userId, kind: 'signup_welcome', providerId: sent.id } })
}
```

The `emailLog` table is the truth source. The Resend idempotency key is belt-and-braces (their side dedupes too).

### 2. Idempotency by **business key**, not by message ID.

Message IDs are unique per delivery — a re-enqueued retry has a *new* message ID but the same business intent. Dedupe on `(user_id, action, day)` or whatever uniquely identifies the *intent*, not the *message*.

### 3. Retries with exponential backoff and jitter.

```ts
const delays = [
  1_000,           // 1s
  5_000,           // 5s
  30_000,          // 30s
  5 * 60_000,      // 5m
  30 * 60_000,     // 30m
  2 * 60 * 60_000, // 2h
]
// Add jitter: delay = base * (0.5 + Math.random())
```

Why jitter: a thundering herd of synchronized retries (20 jobs all retry at exactly 5s) DDoSes whatever broke. Jitter spreads them.

Most queue systems (BullMQ, Inngest, Trigger.dev, AWS SQS, GCP Tasks) configure backoff per-job — use them, don't reinvent.

### 4. Distinguish *retryable* from *terminal* errors.

```ts
class TerminalError extends Error {} // never retry
class TransientError extends Error {} // retry per policy

// Inside handler:
catch (err) {
  if (err.status === 404) throw new TerminalError(err.message) // resource gone, don't retry
  if (err.status >= 500) throw new TransientError(err.message) // their bad, retry
  if (err.code === 'ECONNRESET') throw new TransientError(err.message)
  throw err
}
```

A 404 from Stripe will be 404 forever. Retrying 50 times wastes resources and delays the dead-letter queue.

### 5. Set a max attempt count. Then dead-letter.

After N retries, the job goes to a **dead-letter queue (DLQ)**. The DLQ is monitored, alerts fire, and a human looks at it. **A growing DLQ is the signal something is broken.** A queue with no DLQ silently drops failed work.

### 6. Visibility timeouts > job duration. With a margin.

If your job takes 4 minutes, the visibility timeout must be longer (say 6). Otherwise the queue thinks the worker died and re-delivers the message — now two workers run the same job. Most queue systems support **heartbeat** / extending the lease for long jobs; use it.

### 7. Schedule from the database, not from "remember to enqueue."

For "send a follow-up in 3 days" or "expire this in 24h":
- Persist the intent (`scheduled_at`, `kind`, `payload`) when the originating action happens
- A scheduler (or your queue's delayed delivery) picks it up at the right time

If you `await sleep(3 * 24h); send(...)` you've coupled durability to whichever process is running. A redeploy kills it. A crash kills it. Persistence is non-negotiable.

### 8. Cron jobs are the same problem.

```ts
// A daily 3am job that runs on two app pods because both think they're "the cron node"?
// That's two emails to every user.
```

Use a queue with a single-leader cron (Inngest, Trigger.dev, Vercel Cron, GCP Cloud Scheduler), not a `setInterval` baked into your web server. And: idempotency by date — the job's first action is `if alreadyRanForDate(today) return`.

### 9. Outbox pattern for "DB write + enqueue."

```ts
// BAD — DB commits, enqueue fails. The job is lost.
await db.order.create({ data })
await queue.send({ type: 'order.created', orderId: order.id })

// GOOD — write the event in the same transaction, deliver via outbox worker
await db.$transaction(async (tx) => {
  await tx.order.create({ data })
  await tx.outboxEvent.create({ data: { type: 'order.created', payload: { ... } } })
})
// Separate worker drains outboxEvent → queue, marks each delivered.
```

Either both happen or neither does. See `transactions-and-consistency`.

### 10. Observability: every job has a log line + a duration metric + a status.

```ts
logger.info({ jobId, kind, attempt, payload }, 'job.started')
try {
  await handler(payload)
  logger.info({ jobId, kind, attempt, durationMs }, 'job.completed')
} catch (err) {
  logger.error({ jobId, kind, attempt, durationMs, err }, 'job.failed')
  throw err
}
```

When a customer asks "did our 3pm export run?", you can answer in seconds. See `observability`.

## Picking a queue (2026)

- **Inngest** / **Trigger.dev** — durable workflows, great DX for serverless. Default for most TS apps.
- **BullMQ** (Redis) — solid, you run the worker. Right when you have a long-lived server.
- **AWS SQS** / **GCP Cloud Tasks** — boring, durable, cheap, no fancy DX. Right at scale.
- **Cloudflare Queues** — paired with Workers. Right when you're already on CF.

Don't roll your own queue with `setTimeout` and a database table unless you've read the existing options and have a specific reason.

## War story

A "send weekly digest" cron lived as a `setInterval` inside the Next.js server. Three deploy instances ran simultaneously. Every user got 3 weekly digests. Marked as spam by 2% of recipients. Domain reputation tanked, deliverability dropped 40% across all transactional email for the next month. The fix was moving the cron to Vercel Cron (single leader) + idempotency by `(userId, week)`.

## Quick checklist

- [ ] Handler is idempotent (dedupe by business key, not message ID)
- [ ] Exponential backoff with jitter; max attempts set
- [ ] Retryable vs terminal errors distinguished
- [ ] Dead-letter queue exists and is monitored
- [ ] Visibility timeout > expected job duration; heartbeat for long jobs
- [ ] Scheduled work persisted in DB or durable queue, not in-process timers
- [ ] Crons run on a single leader; idempotent per period
- [ ] DB write + enqueue uses outbox pattern
- [ ] Job lifecycle logged with `jobId`, `kind`, `attempt`, `durationMs`
