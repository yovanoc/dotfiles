---
name: llm-endpoint-safety
description: Use when the user calls an LLM API from a server route, builds a chat endpoint, wires generateText/streamText/streamObject, integrates OpenAI/Anthropic/Google/Mistral, or proxies any AI request from the client. Catches client-side keys, missing per-user quotas, prompt injection, runaway costs, and abuse loops.
---

# LLM Endpoint Safety

> An LLM endpoint is a credit card with a JSON interface. Treat it that way.

## When to use
- Wiring `streamText`, `generateText`, `streamObject`, `generateObject` (AI SDK)
- Calling OpenAI / Anthropic / Google / Mistral / Groq / xAI from a server route
- Building a chat, completion, embedding, image-gen, or speech endpoint
- Letting users supply prompts, system messages, or tool definitions
- Proxying any AI request that reaches your platform's bill

## When to skip
- Local-only LLM (Ollama, llama.cpp) with no per-user cost
- Pure read-only metadata about a model (no inference)

## The non-negotiables

1. **Key is server-side.** Never `NEXT_PUBLIC_OPENAI_API_KEY`. See `secrets-and-env`.
2. **Auth before inference.** No anonymous calls to your model proxy.
3. **Per-user rate limit and quota.** Per-IP is not enough. A logged-in attacker burns one key.
4. **Hard token cap on every call.** `max_tokens` / `maxOutputTokens` always set.
5. **Cost ceiling per user per period.** Hard stop, not a warning.
6. **Abort on disconnect.** Close the upstream stream when the client closes.
7. **Log usage server-side.** Every call → user, model, input tokens, output tokens, cost.

## The rules

### 1. Never expose the model API key to the client.

```ts
// BAD — your key in every visitor's bundle, instantly drained
'use client'
import OpenAI from 'openai'
const client = new OpenAI({ apiKey: process.env.NEXT_PUBLIC_OPENAI_API_KEY, dangerouslyAllowBrowser: true })

// GOOD — proxy through your server route
'use client'
const res = await fetch('/api/chat', { method: 'POST', body: JSON.stringify({ messages }) })
```

`dangerouslyAllowBrowser: true` is named that way for a reason. The only correct use is in trusted environments (extensions, internal tools with their own auth), never on a public web app.

### 2. Per-user quota, not just rate limit.

Rate limit prevents bursts. **Quota** prevents a logged-in attacker from spending $5k/day at a steady drip.

```ts
// Two layers:
// 1. Burst: e.g., 20 messages / minute
// 2. Daily cap: e.g., 200 messages / day (free tier), $5 / day (paid)

const dayKey = `llm:day:${userId}:${todayUTC()}`
const usage = await redis.get<number>(dayKey) ?? 0
if (usage >= dailyLimitForPlan(user.plan)) {
  return Response.json({ error: { code: 'quota_exceeded' } }, { status: 429 })
}
```

### 3. Hard `max_tokens` cap. Always.

```ts
// BAD — model decides how long to talk; one user asks for "an entire novel"
const result = await streamText({ model, messages })

// GOOD
const result = await streamText({
  model,
  messages,
  maxOutputTokens: 1024, // cap per response
})
```

The cap is a cost ceiling per call. Pick a value that serves your UX, not the model's appetite.

### 4. Pick the cheapest model that does the job.

Don't default to the flagship for every call. Route simple tasks (classification, extraction, short answers) to a smaller model. Reserve the expensive one for tasks that actually need it. A 10x cost difference on the bulk path adds up to your runway.

### 5. Stream and abort on disconnect.

```ts
export async function POST(req: Request) {
  const { messages } = await req.json()

  // AI SDK pattern: pass the request signal so abort propagates upstream
  const result = streamText({
    model,
    messages,
    abortSignal: req.signal,
    maxOutputTokens: 1024,
  })

  return result.toTextStreamResponse()
}
```

If the user closes the tab, you stop paying for tokens you'll never deliver. Without this, a malicious client opens 100 streams and immediately disconnects — you keep paying.

### 6. Treat user input as untrusted prompt material.

Every message body, every tool argument, every retrieved doc is **attacker-controllable text**. Prompt injection is real and unsolvable in the general case. Defenses:

- **Don't grant tools you can't afford to be called.** No `delete_user`, `transfer_funds`, `run_shell` exposed to a chat agent without out-of-band confirmation.
- **Constrain output** with structured generation (`generateObject` + Zod schema) when possible — schema-bound output is much harder to weaponize than free-form.
- **Strip or escape** user content before mixing into a system prompt. Sandwich content between explicit delimiters and tell the model to treat it as data.
- **Don't render model output as HTML** without sanitization (see `error-handling` for output safety in general).

### 7. RAG / retrieval: source-control the corpus.

Anything you retrieve and feed to the model gets the same trust as the prompt. If users can write to the corpus (notes, docs, comments), an attacker can poison retrieval to manipulate other users' answers. Scope retrieval to the requesting user/tenant; never cross-tenant retrieve.

### 8. Log every call. Cost included.

```ts
await db.llmCall.create({
  data: {
    userId,
    model: 'claude-sonnet-4-6',
    inputTokens: result.usage.inputTokens,
    outputTokens: result.usage.outputTokens,
    costUsd: estimateCost(model, result.usage),
    latencyMs,
    requestId,
    abortedByClient,
  },
})
```

When a $400 day shows up, you need to know which user, which model, which feature. Without this you can only stare at the OpenAI dashboard and guess.

### 9. Fail closed on quota check failure.

If your quota store (Redis) is unreachable, the safe default is **deny**, not allow. A "fail open" quota check is a vector — attacker DDoSes Redis, then drains your model budget through your unprotected proxy.

### 10. Set a billing alarm at the provider.

OpenAI, Anthropic, and Google all support hard usage limits. **Set them.** A misconfigured loop or a credential leak should hit a $X/day cap and stop, not run free until your card declines.

## War story

A "AI resume reviewer" launched on Hacker News. The chat endpoint had no auth — "we want low friction." A scraper ran a script that hammered the endpoint with 200k requests overnight, burning $9,400 of OpenAI credits. The founder's startup card declined the next morning. Auth + per-IP+per-account quota + a billing alarm would have capped exposure at low double digits.

## Quick checklist

- [ ] API key is server-only; client calls a proxy route
- [ ] Auth required to hit the endpoint
- [ ] Per-user quota (daily/monthly $ or token cap), not just rate limit
- [ ] `maxOutputTokens` set on every call
- [ ] Cheaper model for cheaper work; flagship reserved
- [ ] `abortSignal: req.signal` so client disconnect cancels upstream
- [ ] User input treated as untrusted; tool exposure minimized
- [ ] RAG retrieval scoped per-user/tenant
- [ ] Every call logged with usage + cost + userId
- [ ] Fail-closed quota check
- [ ] Provider-side billing cap configured
