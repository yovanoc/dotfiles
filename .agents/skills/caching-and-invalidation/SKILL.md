---
name: caching-and-invalidation
description: Use when the user adds a cache layer, memoizes a fetch, sets a Redis/KV key, configures Next.js fetch caching, or sees stale-data complaints. Covers cache keys, TTL choice, stampede prevention, invalidation strategies, and the per-user vs global trap.
---

# Caching & Invalidation

> "There are only two hard things in computer science: cache invalidation and naming things." — Phil Karlton.
> The corollary: **don't add a cache until you've measured a problem the cache solves.**

## When to use
- Read traffic to an expensive computation or query is high and the data changes rarely
- Third-party API rate limits or cost are forcing your hand
- You've measured a slow path and a cache *for that specific path* makes it fast enough
- Adding `cache()`, `unstable_cache`, `'use cache'`, `revalidatePath`, `revalidateTag`
- Wiring Redis / KV / in-memory cache for a hot read

## When to skip
- "Cache it just in case" — premature
- Per-user data with high cardinality and low repeat reads (cache miss rate is ~100%)
- Data where staleness causes correctness bugs (balances, permissions, current price)

## The rules

### 1. Cache key includes everything that varies the result.

```ts
// BAD — same key for every user. First user's data leaks to every user.
const cache = new Map<string, User>()
async function getUser() {
  if (cache.has('user')) return cache.get('user')
  const u = await fetchCurrentUser()
  cache.set('user', u)
  return u
}

// GOOD — keyed by what varies
async function getUser(userId: string) {
  const k = `user:${userId}`
  const hit = await redis.get<User>(k)
  if (hit) return hit
  const u = await db.user.findUnique({ where: { id: userId } })
  await redis.set(k, u, { ex: 60 })
  return u
}
```

If the result depends on `userId`, `tenantId`, locale, A/B variant — every one of those goes in the key.

### 2. Don't cache per-user data globally. Don't cache global data per-user.

This is the same bug, two directions. A cache keyed without the user leaks one user's data to all. A cache keyed by user when the data is global wastes memory at near-100% miss rate.

In Next.js: `cache()` and `'use cache'` are **request-scoped or content-keyed**. If you cache a function whose result depends on `cookies()`/`headers()`, include those in the key explicitly or you'll cross-contaminate users.

### 3. Pick the TTL based on tolerable staleness.

| Data | TTL | Why |
|---|---|---|
| User profile | 30s–5min | rare changes, OK to be slightly stale |
| Marketing page | hours | content rarely changes; revalidate on publish |
| Pricing page | minutes + tag-based revalidation | needs invalidation on price change |
| Auth permissions | seconds, or **don't cache** | wrong = security incident |
| Account balance | **don't cache** | wrong = correctness incident |

"Forever" is a TTL only if you have invalidation. Always pair long TTLs with a deliberate invalidation plan.

### 4. Tag-based invalidation > path-based > time-based.

Next.js 15+:
```ts
// Read
const data = await fetch(url, { next: { tags: ['post:42'] } })

// Or with use cache (Next 15+)
async function getPost(id: string) {
  'use cache'
  cacheTag(`post:${id}`)
  cacheLife({ revalidate: 3600, expire: 86400 })
  return db.post.findUnique({ where: { id } })
}

// Invalidate when the post changes
await revalidateTag(`post:${id}`)
```

Tags let you invalidate a single logical entity across every cache that touched it. Path revalidation is a blunt instrument; time-based is a fallback for "we forgot to invalidate."

### 5. Prevent stampedes.

When a hot key expires, every concurrent request misses → all hammer the origin → the origin falls over.

Options:
- **Stale-while-revalidate**: serve stale, refresh in the background. (Next.js does this by default for `revalidate`.)
- **Single-flight / lock**: first miss takes a Redis `SETNX` lock; concurrent misses wait or return stale.
- **Probabilistic early refresh**: refresh with probability rising as TTL approaches, so the herd disperses.

### 6. Cache the *negative* result too.

```ts
// BAD — every "not found" hits the DB. A scraper looking for valid IDs DDoSes you.
const post = await db.post.findUnique({ where: { id } })
if (!post) return notFound()

// GOOD — short-TTL "not found"
const cached = await redis.get(`post:${id}`)
if (cached === '__null__') return notFound()
const post = await db.post.findUnique({ where: { id } })
if (!post) {
  await redis.set(`post:${id}`, '__null__', { ex: 30 })
  return notFound()
}
```

### 7. Don't cache mutations or anything that should be POST.

`GET` is cacheable; `POST/PUT/PATCH/DELETE` are not. If something feels cacheable but mutates, it's modeled wrong.

### 8. Versioned keys for breaking changes.

Shipped a code change that changes the shape of cached data? Old cached entries are now poisoned. Two safe patterns:
- **Bump a version prefix** in the key: `v2:user:42` — old `v1:` keys age out, new ones populate.
- **Flush on deploy** if the cache is small and warming is fast.

Never deploy a "I'll just keep using the same key with the new shape" change. Old data + new code = type error in production.

### 9. Watch for cache penetration and cardinality blowup.

A cache keyed by `?search=<random>` lets attackers fill it with garbage that no one will hit again. Defenses:
- Cap the cache size with eviction (Redis maxmemory + LRU)
- Don't cache low-cardinality misses (search with no results)
- Allowlist or hash-bucket the cache key space

### 10. Observe hits, misses, and origin RPS.

Without metrics you don't know the cache works. Track:
- Hit rate per cache (`name`, `region`)
- Origin RPS (the thing the cache is supposed to reduce)
- TTL effectiveness — are most reads served fresh or stale-but-served?

If hit rate is < ~70% on a hot path, the cache is probably a net loss after key/TTL/serialization overhead. Re-evaluate.

## Next.js specifics (2026)

- **`'use cache'`** + `cacheTag` + `cacheLife` is the modern primitive. Prefer it over `unstable_cache`.
- **PPR (Partial Prerendering)** lets you cache the static shell while streaming the dynamic part — often eliminates the need for a separate read cache.
- **`fetch(url, { next: { revalidate, tags } })`** for data-fetching caches.
- **`revalidateTag`** in a Server Action after a mutation is the canonical "data changed, invalidate."

See `next-cache-components` for deeper Next.js 15+ details.

## War story

A "trending posts" page used `unstable_cache` keyed by route path. It rendered a personalized "for you" panel. After the cache populated for the first user, every subsequent visitor saw that user's recommendations — including their private "saved drafts" preview. Discovered when one user reported seeing another user's name. Fix: include `userId` in the cache key, plus a `'use server'` audit pass for any cache that touched session state.

## Quick checklist

- [ ] Cache key includes every input that varies the result (user, tenant, locale, etc.)
- [ ] No per-user data in a globally-keyed cache, ever
- [ ] TTL chosen based on tolerable staleness, written down somewhere
- [ ] Tag-based invalidation for entities; tags propagate from mutation paths
- [ ] Stampede protection (SWR, single-flight, or jitter) on hot keys
- [ ] Negative results cached with short TTL to prevent DB hammering
- [ ] Versioned cache keys for shape changes
- [ ] Observability: hit rate, origin RPS, TTL effectiveness
- [ ] No caching of permission/auth state beyond a few seconds (or not at all)
