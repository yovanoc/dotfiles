---
name: authorization
description: Use when the user writes any endpoint, server action, route handler, or query that reads or mutates user-owned data — anything taking a resource ID from the request. Catches IDOR, missing row-level checks, "logged in" mistaken for "allowed to," and role/permission gaps.
---

# Authorization

> Authentication answers "who are you." Authorization answers "are you allowed to touch this." They are not the same. Most "data leak" incidents are missing authorization, not missing authentication.

## When to use
- Writing a route handler, Server Action, RPC, or RSC that takes an ID from the URL/body/params
- Building admin / team / multi-tenant features
- Adding a "share" or "transfer" feature
- Returning a list that should be scoped to the current user/tenant
- Touching `WHERE id = ?` or `findById` with input-derived IDs

## When to skip
- Public, unauthenticated, read-only endpoints with no user-scoped data
- Health checks, public marketing content

## The rule, stated plainly

> **Every query that touches user-owned data must scope by the current user/tenant. Every. Single. One.**

Logged-in does not mean allowed. Knowing the URL does not mean allowed. Being on the right page does not mean allowed.

## The IDOR pattern (Insecure Direct Object Reference)

```ts
// BAD — any logged-in user can read any invoice by guessing IDs
export async function GET(req: Request, { params }: { params: { id: string } }) {
  const session = await getSession()
  if (!session) return new Response('Unauthorized', { status: 401 })
  const invoice = await db.invoice.findUnique({ where: { id: params.id } })
  return Response.json(invoice)
}

// GOOD — scoped by ownership
export async function GET(req: Request, { params }: { params: { id: string } }) {
  const session = await getSession()
  if (!session) return new Response('Unauthorized', { status: 401 })
  const invoice = await db.invoice.findFirst({
    where: { id: params.id, userId: session.userId }, // ← the load-bearing line
  })
  if (!invoice) return new Response('Not found', { status: 404 })
  return Response.json(invoice)
}
```

The vulnerable version "feels fine" because it has `getSession()`. That's authentication. It does not check whether **this** user owns **that** invoice. That's authorization.

## The rules

### 1. Scope at the query, not after.

```ts
// BAD — fetch then check (race-prone, leaks existence, easy to forget)
const order = await db.order.findUnique({ where: { id } })
if (order.userId !== session.userId) throw new Error('forbidden')

// GOOD — scope in the WHERE clause
const order = await db.order.findFirst({
  where: { id, userId: session.userId },
})
```

### 2. Multi-tenant: scope by tenant, not just user.

If a user belongs to one or more orgs:

```ts
// GOOD
const project = await db.project.findFirst({
  where: { id: projectId, orgId: { in: session.orgIds } },
})
```

Better still: enforce at the database with **Row-Level Security** (Postgres RLS, Supabase) or a query interceptor in your ORM (Prisma extensions, Drizzle middleware). Defense in depth — a forgotten scope at the call site is still blocked at the DB.

### 3. 404, not 403, for "not yours."

Returning `403 Forbidden` confirms the resource exists. That's an information leak. Return `404 Not Found` for both "doesn't exist" and "exists but not yours" — the user should not be able to enumerate IDs.

### 4. Authorization checks happen on the server. Always.

Hiding a button on the client is UX, not security. Anyone can `curl` the endpoint. Every check happens server-side, in the route handler / Server Action / RPC.

```ts
// Client-side check is fine for UX
{ session.role === 'admin' && <DeleteButton /> }

// But the endpoint must check too
export async function DELETE(req, { params }) {
  const session = await getSession()
  if (session?.role !== 'admin') return new Response('Not found', { status: 404 })
  // ...
}
```

### 5. Permissions, not just roles, once you have more than two of them.

Roles (`admin`, `member`, `viewer`) work for simple apps. Once you have edge cases (a member who can manage billing but not invite users), switch to **permissions**:

```ts
// permission strings: "billing.manage", "members.invite", "projects.delete"
if (!session.permissions.includes('billing.manage')) {
  return new Response('Not found', { status: 404 })
}
```

A role becomes a named bundle of permissions. The check stays the same regardless of how the bundle is composed.

### 6. Server Actions and RSCs need authz too.

Server Actions are HTTP endpoints. RSCs run on the server but render with whatever data you fetch — if you fetch unscoped, you render someone else's data. Same rule: scope at the query.

### 7. Bulk operations: scope every item, not just the IDs you're given.

```ts
// BAD — trusts the IDs in the request
await db.task.deleteMany({ where: { id: { in: req.body.ids } } })

// GOOD
await db.task.deleteMany({
  where: { id: { in: req.body.ids }, userId: session.userId },
})
```

### 8. "Public share" links are not exemptions.

They're a separate authorization rule: "this resource has an active share token and the request presents it." Still scoped, still checked, still expirable, still revocable.

## War story

A YC-batch SaaS launched a "team workspaces" feature. Every endpoint had `getSession()` at the top. Six months later a customer noticed they could change a number in the URL of `/api/projects/123/export` and download any other tenant's project. Every authenticated user on the platform could read every other tenant's data. The fix was adding `orgId: session.orgId` to nine `findUnique` calls. The cost was a public disclosure post and three churned enterprise contracts.

## Quick checklist

- [ ] Every DB query with a user-supplied ID has a `userId` / `orgId` / `tenantId` clause
- [ ] Authentication and authorization are both checked — never assume one implies the other
- [ ] `404` (not `403`) for "exists but not yours"
- [ ] Bulk endpoints scope **every** target row, not just the requested IDs
- [ ] Authorization runs server-side; client checks are UX only
- [ ] Postgres RLS (or ORM middleware) layered as defense in depth
- [ ] Share/invite tokens are scoped, expirable, revocable
