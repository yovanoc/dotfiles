---
name: error-handling
description: Use when the user writes try/catch, throws errors, builds error boundaries, returns errors from an API, sets up global error handling, or designs how failures surface to users. Catches swallowed errors, leaked internals in error responses, missing graceful degradation, and "the spinner spins forever" UX.
---

# Error Handling & User-Facing Failures

> Two failure modes are unforgivable: silently swallowing errors so debugging is impossible, and leaking internals so attackers learn your stack. The middle path is narrow and worth getting right.

## When to use
- Writing `try`/`catch`, `Promise.catch`, error boundaries, `error.tsx`
- Returning errors from an API or Server Action
- Designing fallback UI when something fails
- Wrapping third-party calls that might throw
- Reviewing how the app behaves when the network / DB / dependency goes down

## When to skip
- Pure deterministic functions with no I/O and no exceptional conditions

## The mental model

Two kinds of errors. Treat them differently:

| Kind | Examples | What to do |
|---|---|---|
| **Expected** | "email already taken", "out of stock", "not found" | Return a typed result; show user-facing UI; log at `info` |
| **Unexpected** | DB unreachable, OOM, bug, third-party 500 | Catch at the boundary, log full detail, show a generic message, alert |

Conflating them produces both bad UX (cryptic errors for normal cases) and bad ops (alert fatigue from "expected" errors).

## The rules

### 1. Never swallow.

```ts
// BAD — error vanishes; you'll wonder why nothing works at 3am
try { await doThing() } catch {}

// BAD — log + ignore is also swallowing
try { await doThing() } catch (e) { console.log(e) }

// GOOD — handle deliberately, or rethrow
try {
  await doThing()
} catch (e) {
  if (isExpectedNotFound(e)) return null
  throw e
}
```

If you don't know what to do with an error, let it propagate to the boundary that does.

### 2. Catch at the boundary. Not in the middle.

```ts
// BAD — every layer wraps in try/catch and re-throws or returns null. Stack trace is lost.

// GOOD — boundaries catch (route handler, job handler, top-level UI). Inner code throws freely.
export async function POST(req: Request) {
  try {
    return await handler(req)
  } catch (err) {
    return errorResponse(err) // single place that maps errors → response
  }
}
```

### 3. User-facing message ≠ error.message.

```ts
// BAD — leaks internals
return Response.json({ error: err.message }, { status: 500 })
// "PrismaClientKnownRequestError: relation 'user' does not exist" → tells attackers your DB

// GOOD — generic to user, full detail to logs
logger.error({ err, requestId }, 'request_failed')
return Response.json(
  { error: { code: 'internal_error', message: 'Something went wrong.', requestId } },
  { status: 500 },
)
```

The `requestId` lets you correlate the user's complaint to the log entry without revealing internals.

### 4. Result types for expected errors. Throws for unexpected.

```ts
// Expected outcome → typed result
type Result<T, E = string> = { ok: true; value: T } | { ok: false; error: E }

async function createUser(email: string): Promise<Result<User, 'email_taken' | 'invalid_email'>> {
  if (!isEmail(email)) return { ok: false, error: 'invalid_email' }
  const existing = await db.user.findUnique({ where: { email } })
  if (existing) return { ok: false, error: 'email_taken' }
  const user = await db.user.create({ data: { email } })
  return { ok: true, value: user }
}

// Unexpected → throw, let the boundary catch
```

The caller pattern-matches; the type system makes you handle every error case.

### 5. Tagged error classes. Don't string-match `err.message`.

```ts
// BAD — fragile
catch (e) { if (e.message.includes('not found')) ... }

// GOOD — branded
class NotFoundError extends Error { _tag = 'NotFoundError' as const }
class RateLimitError extends Error { _tag = 'RateLimitError' as const }

catch (e) {
  if (e instanceof NotFoundError) return new Response(null, { status: 404 })
  if (e instanceof RateLimitError) return new Response('Slow down', { status: 429 })
  throw e
}
```

### 6. Always log with structure and correlation.

```ts
logger.error({
  err,                     // logger serializes Error properly (stack, cause)
  requestId,
  userId,
  route: '/api/x',
  durationMs,
}, 'request.failed')
```

`{ err }` not `String(err)`. Modern loggers (Pino, Logtape) serialize the chain via `err.cause`. See `observability`.

### 7. UI: never strand the user on a spinner.

Every async UI surface needs three states: **loading**, **error**, **empty**. Plus a way out (retry, back, contact support).

```tsx
// Next.js: app/products/error.tsx + loading.tsx
'use client'
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  useEffect(() => { logToService(error) }, [error])
  return (
    <div>
      <h2>We hit a problem.</h2>
      <button onClick={reset}>Try again</button>
      <p className="text-xs text-muted-foreground">Error ID: {error.digest}</p>
    </div>
  )
}
```

In React 19+: error boundaries log the `digest` (server-generated ID); pair with your server-side log via that digest.

### 8. Fail closed for security. Fail open for non-critical features.

- Permission check failed because Redis is down? **Fail closed** (deny access).
- Search index unreachable? **Fail open** (show "search temporarily unavailable", let the rest of the app work).

The default for new features should be fail-closed; relax deliberately for feature-by-feature non-criticality.

### 9. Graceful degradation: design fallbacks before you need them.

Third-party API down → cached last-known-good value, or a "service degraded" badge, not a 500.
Image CDN down → original image URL or placeholder, not broken images.
Analytics down → swallow the error (analytics isn't core), don't break the user flow.

Identify what's load-bearing for the user task and what's auxiliary. Auxiliary failures must not break load-bearing flows.

### 10. Top-level `unhandledrejection` and `uncaughtException` handlers.

```ts
process.on('unhandledRejection', (reason) => logger.error({ reason }, 'unhandled.rejection'))
process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'uncaught.exception')
  process.exit(1) // crash & restart; don't keep running in unknown state
})
```

A process that's seen an uncaught exception is in undefined state. Log, exit, let the orchestrator restart it. Don't try to "keep going."

### 11. Preserve the cause when wrapping.

```ts
// BAD — lose the original
throw new Error('failed to load user')

// GOOD — chain via cause (ES2022+)
throw new Error('failed to load user', { cause: err })
```

Modern loggers serialize the cause chain. You see "user load failed → DB query failed → connection timeout" in one log line.

## React error boundaries — what they catch and don't

- **Catch**: render-time errors in children
- **Don't catch**: errors in event handlers, async code (`.then()`/`useEffect`), errors thrown after suspension
- For async errors in components, surface them through state and re-throw during render to enter the boundary, OR use a library like `react-error-boundary`'s `useErrorBoundary().showBoundary(err)`

## War story

A vibe-coded SaaS wrapped every Server Action body in `try { ... } catch (e) { console.log(e); return null }`. Worked great until one day every checkout silently failed because Stripe rotated a webhook secret and the error was eaten. Three days of $0 revenue before someone noticed. The fix wasn't fancy: remove the swallow, let the route handler's outer `try/catch` log it, and an alert fired the next time it happened — within minutes.

## Quick checklist

- [ ] No empty `catch {}` and no `catch (e) { console.log(e) }` (that's swallowing)
- [ ] Errors caught at boundaries (route handler, job handler, error boundary), not in the middle
- [ ] User-facing messages are generic; full detail goes to structured logs
- [ ] `requestId` in every error response and matching log line
- [ ] Expected errors use typed results; unexpected errors throw
- [ ] Tagged error classes, not message string-matching
- [ ] UI has loading + error + empty states for every async surface
- [ ] Auth/permission failures fail **closed**; auxiliary feature failures fail open
- [ ] Top-level handlers for `unhandledRejection` / `uncaughtException`
- [ ] Errors wrap with `{ cause }` to preserve the chain
