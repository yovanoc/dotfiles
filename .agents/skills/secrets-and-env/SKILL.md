---
name: secrets-and-env
description: Use when the user is adding an API key, editing .env / .env.local / .env.production, naming a variable NEXT_PUBLIC_/VITE_/PUBLIC_/EXPO_PUBLIC_, wiring a third-party SDK that needs a credential, or logging/returning errors that may include credentials. Catches client-bundled secrets, committed env files, and secrets in logs.
---

# Secrets & Env Vars

## When to use
- Adding any API key, token, or credential to the codebase
- Creating or editing `.env`, `.env.local`, `.env.production`, `.dev.vars`
- Naming a var with a public-bundling prefix (`NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `EXPO_PUBLIC_`)
- Wiring a third-party SDK that needs a secret (Stripe, OpenAI, Anthropic, AWS, Resend, Twilio, etc.)
- Logging or returning errors from code that touches secrets

## When to skip
- Reading already-established config that isn't changing
- Pure UI work with zero credential involvement

## The rules

### 1. Public-prefixed = client bundle. No exceptions.

Any var prefixed `NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `EXPO_PUBLIC_`, `REACT_APP_` is shipped in the JS bundle. It is **public on first page load**. Build-time inlining does not make it private.

```ts
// BAD — secret key shipped to every visitor's browser
NEXT_PUBLIC_STRIPE_SECRET_KEY=sk_live_...
NEXT_PUBLIC_OPENAI_API_KEY=sk-proj-...

// GOOD — server-only, no public prefix
STRIPE_SECRET_KEY=sk_live_...
OPENAI_API_KEY=sk-proj-...
```

Why: viewable via DevTools → Sources, and bot-scrapers index public bundles within hours of deploy.

### 2. Server-only secrets must be unreachable from client code.

Use the `server-only` package (or your framework's equivalent). It throws at build time the moment a client component imports it — you learn now, not in prod.

```ts
// lib/stripe.ts
import 'server-only'
import Stripe from 'stripe'
export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)
```

```ts
// app/checkout/page.tsx — Client Component
'use client'
import { stripe } from '@/lib/stripe' // ❌ build error: "server-only cannot be imported from a Client Component"
```

The error is the feature.

### 3. Never log a secret. Never include one in an error response.

Logs ship to third parties (Datadog, Vercel, BetterStack, Sentry). Stack traces returned to clients have leaked AWS keys, GitHub PATs, and OAuth tokens to public bug reports. Strip before logging, and never echo `process.env` or full request headers.

```ts
// BAD
logger.error({ err, headers: req.headers }) // Authorization header now in your log provider

// GOOD
logger.error({ err, path: req.url, userId: ctx.userId })
```

### 4. `.env*` is gitignored. Always.

Verify `.gitignore` contains `.env*` (with an exception for `.env.example`) **before** running `git add .` for the first time. Once a secret hits Git history, treat it as compromised — see rule 6.

```gitignore
# .gitignore
.env*
!.env.example
```

### 5. Production secrets live in the platform secret manager.

Never in committed files. Use Vercel env vars, Cloudflare Workers secrets, Doppler, 1Password Secrets Automation, AWS Secrets Manager, or Infisical. `.env.local` is for local dev only.

### 6. Exposed = rotate immediately.

If a secret hit Git, npm, a Slack channel, a screenshot, or `console.log` in prod: **rotate the key first, audit second.** Do not "delete the commit" and move on — Git history, GitHub's reflog, third-party caches, and bot-scrapers have already seen it. After rotation, audit usage logs for the old key (Stripe, OpenAI, AWS all expose this) to scope the blast radius.

### 7. Validate env at boot, not at use-site.

Parse `process.env` once with Zod/T3 Env at startup. Missing or malformed config should fail loud immediately, not at 3am when a user hits the rare endpoint that needs it.

```ts
// lib/env.ts
import { z } from 'zod'
const envSchema = z.object({
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
  DATABASE_URL: z.string().url(),
  OPENAI_API_KEY: z.string().startsWith('sk-'),
})
export const env = envSchema.parse(process.env)
```

## War story

A vibe-coded SaaS prefixed every var with `NEXT_PUBLIC_` because "otherwise it doesn't work." The live Stripe secret key shipped to every visitor for three weeks. $14k of fraudulent charges before Stripe's fraud team caught it. The fix was a one-line rename + key rotation. The cost was the chargebacks. Bots scrape new Vercel/Netlify deploys for `NEXT_PUBLIC_*_SECRET` literally within minutes.

## Quick checklist

- [ ] No `NEXT_PUBLIC_*_SECRET` / `_KEY` / `_TOKEN` / `_PRIVATE` anywhere
- [ ] `.env*` in `.gitignore` (with `!.env.example` exception)
- [ ] Server secrets imported from a `server-only` module
- [ ] No secrets in `console.log`, error responses, or full-header dumps
- [ ] Prod secrets in platform secret manager, not committed
- [ ] Env parsed and validated at boot via Zod/T3 Env
- [ ] If a secret leaked: rotated, then audited — in that order
