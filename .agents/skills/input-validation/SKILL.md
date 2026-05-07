---
name: input-validation
description: Use when an endpoint, Server Action, route handler, form handler, or webhook receiver accepts a request body, query param, search param, header, or form data. Catches unvalidated `req.body`, missing schema parsing, type-cast assumptions, dates as strings, and trust-boundary holes.
---

# Input Validation & Trust Boundaries

> A trust boundary is anywhere data crosses from outside your code into it. **Parse, don't validate** — turn unknown input into a fully-typed value at the boundary, or reject it. Once parsed, the rest of your code can trust the types.

## When to use
- Writing a route handler / Server Action that reads `request.json()`, `formData()`, or `searchParams`
- Receiving a webhook payload
- Parsing query strings, URL params, headers, cookies for anything beyond identity
- Reading data from `localStorage`, IndexedDB, URL hash on the client
- Consuming a third-party API response (yes, that's a trust boundary too)

## When to skip
- Internal function calls between fully-typed code with no external input
- Pure rendering of already-parsed, already-trusted data

## Parse, don't validate

The wrong shape:

```ts
// BAD — type assertion is a lie. The runtime value can be anything.
const body = (await req.json()) as { email: string; age: number }
await db.user.create({ data: body }) // 💥 if `age` is "twenty-one"
```

The right shape:

```ts
import { z } from 'zod'

const CreateUser = z.object({
  email: z.string().email().toLowerCase().trim(),
  age: z.number().int().min(13).max(120),
})

export async function POST(req: Request) {
  const parsed = CreateUser.safeParse(await req.json())
  if (!parsed.success) {
    return Response.json({ error: 'Invalid input', issues: parsed.error.flatten() }, { status: 400 })
  }
  // parsed.data is now fully typed AND validated
  await db.user.create({ data: parsed.data })
  return new Response(null, { status: 201 })
}
```

The schema is the type. The runtime check and the compile-time type are the same object — they cannot drift.

## The rules

### 1. Validate at every trust boundary. Not "deeper in the code."

If the validation lives three function calls down, you'll forget it once and ship a vulnerability. Validate at the **boundary** — the route handler, Server Action, webhook receiver — and pass typed data inward.

### 2. Use Zod or Valibot. Not handwritten checks. Not `Joi`-from-2018.

```ts
// BAD — handwritten, leaky, drifts from the type
if (typeof body.email !== 'string' || !body.email.includes('@')) { ... }

// GOOD
z.string().email()
```

Valibot is lighter (better for edge bundles); Zod is more ergonomic. Pick one per project.

### 3. Whitelist, not blacklist.

Define the shape you accept; reject everything else. **Strict mode**:

```ts
const Body = z.object({
  title: z.string().min(1).max(200),
}).strict() // reject unknown keys

// Without strict(): user sends { title, role: 'admin' } and your spread copies role into the DB
```

`.strict()` (or `.passthrough()` only with intent) prevents **mass assignment** — the bug where extra keys in the body get spread into your DB write.

### 4. Coerce, then validate. Don't trust string→number→string conversions.

Query params and form data are strings. Headers are strings. Coerce explicitly:

```ts
const Search = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
})
const { page, limit } = Search.parse(Object.fromEntries(searchParams))
```

### 5. Validate dates as ISO strings, then coerce to Date.

```ts
const Body = z.object({
  publishAt: z.string().datetime().transform((s) => new Date(s)),
})
```

Never trust `new Date(input)` — it accepts garbage and silently produces `Invalid Date`.

### 6. Headers and cookies are user input.

The `Authorization` header, `User-Agent`, `Origin`, `Referer`, custom `X-*` headers — all attacker-controllable. Validate before using.

### 7. Length limits on every string. Size limits on every array.

```ts
z.string().max(10_000)              // not unbounded
z.array(z.string()).max(100)        // not unbounded
z.string().regex(/^[a-z0-9-]+$/)    // slugs etc
```

Unbounded inputs are how you get OOM crashes and request smuggling. See `api-route-hardening` for body-size limits at the framework level.

### 8. Never `eval`, `Function`, or pass user input to a templating engine without escaping.

Self-explanatory. Same rule applies to building shell commands, `child_process.exec`, and SQL strings (use parameterization — see `database-query-safety`).

### 9. Don't use the parsed shape as the DB shape implicitly.

Validation schema and DB schema overlap but aren't the same. Don't `db.user.create({ data: parsed })` and assume — at minimum strip server-controlled fields (`id`, `createdAt`, `role`, `isAdmin`) from the validation schema, or use `pick`/`omit` deliberately.

```ts
const PublicUserUpdate = UserSchema.pick({ name: true, bio: true })
// User cannot ever set `role`, `email`, `isAdmin` via this endpoint
```

### 10. The same rules apply to webhook payloads.

A "Stripe webhook" is bytes from the internet until you've verified the signature *and* parsed the schema. See `webhooks`.

## Client-side validation is UX, not security

Forms can validate with the same Zod schema (share it between client and server) for nice UX. The **server still validates**, because anyone can `curl` past the form.

## War story

A vibe-coded note app accepted `PATCH /api/notes/:id` with `(await req.json()) as { content: string }`. A user sent `{ content: "x", userId: "<other-user-id>" }`, the server spread the body into a Prisma `update`, and the note transferred to another account. Took down the entire ownership model. The fix was `.strict()` and an explicit `pick`. Cost: hours of data reconciliation across 8k notes.

## Quick checklist

- [ ] Every endpoint parses input via Zod/Valibot at the boundary
- [ ] Schemas use `.strict()` (or explicit `pick`) — no mass assignment
- [ ] String/array fields have explicit max lengths
- [ ] Dates are validated as ISO strings, then coerced
- [ ] Query params are coerced explicitly (no `as number`)
- [ ] Server-controlled fields (`id`, `role`, `userId`) cannot come from request body
- [ ] Headers / cookies / webhook payloads validated, not trusted
