---
name: rsc-boundaries
description: Use when the user mixes "use client" and server code, writes Server Actions, imports server-only or client-only modules, or hits hydration errors / "X is not exported from server" / "Functions cannot be passed to Client Components". Catches secrets leaking to the client, accidental client bundles, hydration drift, and the data-fetching-in-client-components anti-pattern.
---

# Client / Server Boundary (RSC era)

> The boundary is invisible until you cross it wrong. Then your secret is in the bundle, your DB call runs in the browser, or hydration errors flood the console at midnight.

## When to use
- Adding `"use client"` / `"use server"` directives
- Writing a Server Action
- Importing across the boundary (server module → client component, or vice versa)
- Hitting "Functions cannot be passed to Client Components" or "X is not exported from server"
- Diagnosing hydration mismatch errors
- Choosing where to fetch data (RSC vs client component)

## When to skip
- Pages that are entirely server or entirely client with no boundary crossings
- Apps not using RSC (plain SPA, classic Pages Router)

## The mental model

| Where | What runs | Has access to | Gets shipped to client |
|---|---|---|---|
| **Server Component** (default) | once on server | DB, secrets, fs, headers/cookies, server-only modules | only its rendered HTML + serialized props for child Client Components |
| **Client Component** (`"use client"`) | on server (SSR) and on client (hydration + interactions) | browser APIs, hooks, event handlers | yes, its source is in the JS bundle |
| **Server Action** (`"use server"`) | only on server, called via RPC from client | same as Server Component | only a typed proxy is in the client bundle |

Default to Server Components. Add `"use client"` *only* when you need state, effects, event handlers, or browser APIs.

## The rules

### 1. `"use client"` is a boundary, not a contagion.

A Client Component can render Server Components passed as `children` or as props. You don't have to make the whole tree client-side just because a leaf needs interactivity.

```tsx
// app/page.tsx — Server Component
import { ClientPanel } from './client-panel'
import { ServerData } from './server-data'

export default function Page() {
  return (
    <ClientPanel>
      <ServerData /> {/* still runs on the server */}
    </ClientPanel>
  )
}
```

Push `"use client"` as far down the tree as possible. Big interactive surfaces stay small in the bundle when most of their content is server-rendered.

### 2. Mark server-only modules with `import 'server-only'`.

The single best protection against accidentally bundling secrets:

```ts
// lib/db.ts
import 'server-only'
import { drizzle } from 'drizzle-orm/postgres-js'
export const db = drizzle(...)
```

Any client component importing this file fails the build with a clear message — at compile time, not runtime, and not in production after the fact.

Mirror with `import 'client-only'` for modules that only make sense in the browser (e.g., wrappers around `window`).

### 3. Never put secrets behind a `"use client"` import.

```ts
// BAD — Stripe secret key in the client bundle
'use client'
import Stripe from 'stripe'
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

// GOOD — call a Server Action or route handler from the client
'use client'
import { createCheckoutSession } from './actions'
```

`process.env.STRIPE_SECRET_KEY` is `undefined` in the client at runtime, but the module imports + bundling can still drag in code paths that expose intent. Combine with rule 2.

### 4. Server Action arguments and return values must be serializable.

```ts
// BAD
'use server'
export async function trackEvent(emit: () => void) { emit() }
// Error: Functions cannot be passed to Server Actions / Client Components

// GOOD — pass plain data
'use server'
export async function trackEvent(payload: { name: string; userId: string }) { ... }
```

Same for what Server Components pass to Client Components: dates, plain objects, arrays, primitives are fine; class instances, functions, Maps, Sets, Symbols, `Date` objects (serialized but no methods on the client) — be deliberate.

### 5. Fetch data on the server. Don't `useEffect` to fetch.

```tsx
// BAD — client-side fetch, waterfalls, no SSR data, exposes endpoint shape
'use client'
function Posts() {
  const [posts, setPosts] = useState([])
  useEffect(() => { fetch('/api/posts').then(r => r.json()).then(setPosts) }, [])
  return ...
}

// GOOD — server-rendered, single round trip, secrets stay server-side
async function Posts() {
  const posts = await db.post.findMany()
  return ...
}
```

Reach for client fetching only for: real-time updates, infinite scroll past the first page, post-interaction refreshes (and even then, prefer Server Action + `revalidatePath`/`revalidateTag`).

### 6. Authorize at the boundary in Server Actions, not before.

A Server Action is an HTTP endpoint. The fact that it's only called from your UI means nothing — anyone can replay it.

```ts
'use server'
export async function deleteProject(id: string) {
  const session = await getSession()
  if (!session) throw new UnauthorizedError()
  const project = await db.project.findFirst({ where: { id, ownerId: session.userId } })
  if (!project) throw new NotFoundError()
  await db.project.delete({ where: { id } })
}
```

See `authorization` and `api-route-hardening`.

### 7. Hydration errors mean server HTML ≠ client first render.

Common causes:
- `Date.now()` / `Math.random()` / `new Date().toLocaleString()` rendered without locale fix
- Reading `window` / `localStorage` during render (top-level, not in `useEffect`)
- `if (typeof window !== 'undefined')` branches that produce different markup
- Browser extensions injecting attributes (`Grammarly`, `ColorZilla`)

Fixes:
- Compute non-deterministic values in `useEffect` after first render
- Wrap in `<ClientOnly>` (Suspense-friendly) for genuinely client-only UI
- For browser-extension noise, `suppressHydrationWarning` on the affected element (sparingly)

### 8. Don't `import` a Client Component into a server-only file expecting it to run.

`"use client"` modules export a *reference* the renderer uses to bootstrap on the client. You can't call their functions from a Server Action and expect them to execute browser code.

### 9. Server Actions return values, mutations invalidate cache.

```ts
'use server'
import { revalidateTag } from 'next/cache'
export async function publishPost(id: string) {
  await db.post.update({ where: { id }, data: { publishedAt: new Date() } })
  revalidateTag(`post:${id}`)
  revalidateTag('posts:list')
}
```

After a mutation, invalidate the cache tags that touch the affected data so the next read is fresh. See `caching-and-invalidation`.

### 10. Streaming and Suspense: where you put the boundary determines what users see.

```tsx
<Suspense fallback={<Skeleton />}>
  <SlowList /> {/* async server component */}
</Suspense>
```

Suspense boundaries let the rest of the page paint immediately while the slow part streams in. Place them around real data dependencies, not around the whole page.

## War story

A "use client" was added at the top of a layout to fix a one-off interaction. The layout's children were Server Components fetching from the DB. The whole subtree got pulled into the client bundle: the bundle grew 600KB, every visitor downloaded the ORM client (which then no-op'd in the browser), and one of the imports — through a transitive chain — bundled the database connection string. Caught in a security review, not in CI. Fix: move `"use client"` to the leaf, add `import 'server-only'` to the DB module.

## Quick checklist

- [ ] `"use client"` placed at the leaf, not bubbled up
- [ ] Server-only modules guarded with `import 'server-only'`
- [ ] No secrets reachable from `"use client"` modules (transitively)
- [ ] Server Action args/returns are serializable
- [ ] Data fetched in Server Components, not `useEffect`
- [ ] Server Actions check auth and authz at entry
- [ ] No non-deterministic values in render (move to effect or `<ClientOnly>`)
- [ ] Mutations invalidate the cache tags they affect
- [ ] Suspense boundaries placed at real data dependencies
