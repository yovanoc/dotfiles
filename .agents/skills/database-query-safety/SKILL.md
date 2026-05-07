---
name: database-query-safety
description: Use when the user writes raw SQL, Drizzle/Prisma/Kysely queries, ORM `findMany` / `findUnique` calls with user input, or anything constructing a query from request data. Covers parameterization, N+1 detection, missing indexes, SELECT *, query plans, and unbounded result sets.
---

# Database Query Safety

> Two questions before any new query ships: **"Can a user smuggle SQL into this?"** and **"What does this look like at 100x the current row count?"**

## When to use
- Writing raw SQL, `db.$queryRaw`, `sql\`\`` template literals
- Writing ORM queries (Drizzle / Prisma / Kysely / TypeORM) that include user input
- Adding a list/feed/search endpoint
- Touching a query inside a hot loop
- Reviewing a query before launch or under a perf incident

## When to skip
- Reading a static fixture or seed
- One-off scripts run by you against a dev DB

## The rules

### 1. Parameterize. Never concatenate user input into SQL.

```ts
// BAD — classic SQLi
db.$queryRawUnsafe(`SELECT * FROM users WHERE email = '${email}'`)

// GOOD — Prisma tagged template parameterizes safely
db.$queryRaw`SELECT * FROM users WHERE email = ${email}`

// GOOD — Drizzle
db.select().from(users).where(eq(users.email, email))

// GOOD — Kysely
db.selectFrom('users').where('email', '=', email).selectAll().execute()
```

ORMs parameterize by default. The unsafe escape hatches (`$queryRawUnsafe`, `sql.raw`, string concat) are where injection lives. If you need dynamic identifiers (table/column names from input), allowlist them — never interpolate.

### 2. Solve N+1 before it ships, not after.

```ts
// BAD — 1 query for posts, then N queries for authors
const posts = await db.post.findMany()
for (const post of posts) {
  post.author = await db.user.findUnique({ where: { id: post.authorId } })
}

// GOOD — eager-load
const posts = await db.post.findMany({ include: { author: true } })
```

In Drizzle:
```ts
db.query.posts.findMany({ with: { author: true } })
```

How to spot: any DB call inside a `for` / `map` / `forEach` over rows you just fetched. Catch it locally with a query log (`PRISMA_LOG_LEVEL=query`, Drizzle's `logger: true`); catch it in CI by snapshotting query counts in tests for hot paths.

### 3. Always cap `LIMIT`. Always.

```ts
// BAD — returns all 4M rows, OOMs the server
db.message.findMany({ where: { channelId } })

// GOOD
db.message.findMany({ where: { channelId }, take: 100, orderBy: { createdAt: 'desc' } })
```

Every list endpoint has a max page size (e.g. 100). Even "internal" queries should have a `LIMIT` — internal data grows. See `api-route-hardening` for cursor pagination.

### 4. Index every column you filter or sort on.

The query is fine when there are 1k rows. It's unusable at 1M. Indexes fix this; they're cheap to add, painful to add late under load.

```sql
-- For: WHERE userId = ? ORDER BY createdAt DESC
CREATE INDEX idx_message_user_created ON message (userId, createdAt DESC);
```

Read the **query plan** for any non-trivial query: `EXPLAIN ANALYZE`. If you see `Seq Scan` on a table over a few thousand rows, you need an index.

Composite index order matters: put the equality filter first, the sort/range filter second.

### 5. Don't `SELECT *` over wide rows in hot paths.

If your `users` table has a 50KB `metadata` JSON column and you `findMany` for a user list, every row drags 50KB across the wire. Project only the columns you need.

```ts
// Prisma
db.user.findMany({ select: { id: true, name: true, avatarUrl: true } })

// Drizzle
db.select({ id: users.id, name: users.name }).from(users)
```

### 6. Soft-deletes need partial indexes.

If you "soft-delete" with `deletedAt IS NOT NULL`, every index needs to either include `deletedAt` or be partial:

```sql
CREATE INDEX idx_user_email_active ON users(email) WHERE deletedAt IS NULL;
```

Otherwise lookups slow down forever as deleted rows accumulate.

### 7. Beware the silent full-table scan.

These all cause it:
- Filtering on a function: `WHERE LOWER(email) = ?` (without a functional index)
- Leading wildcard `LIKE '%foo'`
- Implicit type coercion: `WHERE id = '123'` when `id` is bigint
- `OR` across columns without each branch being indexed

For text search at scale, use full-text search (Postgres `tsvector` + GIN) or a search index (Meilisearch, Typesense, OpenSearch). Don't `LIKE '%foo%'` on a 10M-row table.

### 8. Connection pool: small and serverful.

Serverless functions can each open a connection. 100 concurrent invocations × 5 connections each = 500 — your Postgres dies at 100. Use a pooler (PgBouncer, Supabase pooler, Prisma Accelerate, Neon's serverless driver) and keep the per-instance pool tiny (`connection_limit=1` for serverless).

### 9. Long queries hold locks. Watch what blocks what.

Updates and deletes take row locks; `ALTER TABLE` takes table locks (see `migrations-and-schema`). A "harmless" report query at peak traffic can pile up behind a lock. Set a `statement_timeout` per role:

```sql
ALTER ROLE app SET statement_timeout = '5s';
ALTER ROLE analytics SET statement_timeout = '60s';
```

Slow query gets killed instead of holding the system hostage.

### 10. Aggregate with the database, not in the app.

```ts
// BAD — fetch 50k rows, sum in JS
const orders = await db.order.findMany({ where: { userId } })
const total = orders.reduce((s, o) => s + o.amountCents, 0)

// GOOD — DB does the math
const { _sum } = await db.order.aggregate({
  where: { userId },
  _sum: { amountCents: true },
})
```

## War story

A "vibe-coded" project-tracker shipped a `/api/dashboard` endpoint that listed all of a user's tasks, their assignees, their projects, and each project's owner — four `findMany` calls in nested loops. Worked great with seed data. First customer with 800 tasks across 30 projects: dashboard took 14 seconds, hit the platform timeout, and 502'd. Fix was three lines of `include`. A query log on day one would have caught it before launch.

## Quick checklist

- [ ] No string-concatenated SQL with user input
- [ ] No DB calls inside loops over fetched rows (N+1)
- [ ] Every list query has a capped `LIMIT`
- [ ] Indexes on every filter + sort column; composite order matches query
- [ ] Projecting needed columns, not `SELECT *` on wide rows
- [ ] Partial indexes for soft-delete columns
- [ ] No leading-wildcard `LIKE` on large tables
- [ ] Connection pool sized for serverless (use a pooler)
- [ ] `statement_timeout` set per role
- [ ] Aggregation in the DB, not in JS
