#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

export PI_RUNTIME="${PI_RUNTIME:-$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent}"

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import { join } from "node:path"
const runtime = process.env.PI_RUNTIME!
const { createJiti } = await import(join(runtime, "node_modules/jiti/lib/jiti.mjs"))
const jiti = createJiti(join(process.cwd(), "scripts/test-worker-router.sh"), {
  moduleCache: false, fsCache: false,
  alias: { "@earendil-works/pi-coding-agent": join(runtime, "dist/index.js") },
})
const R = await jiti.import(join(process.cwd(), "home/private_dot_pi/private_agent/private_extensions/worker-router.ts"))
const { createRoute, poolState, classifyFailure, settle, latestLease, ROUTES, CAPS, COOLDOWN_MS } = R

let t = 1_000_000_000_000
const physical = Object.values(ROUTES).flat().map((e: any) => ({ provider: e.provider, id: e.id, api: "x" }))
let missing = new Set<string>()
const registry = {
  find: (p: string, id: string) => physical.find((m) => m.provider === p && m.id === id),
  getAvailable: () => physical.filter((m) => !missing.has(`${m.provider}/${m.id}`)),
}
const fresh = (windows: any[]) => ({ provider: "x", source: null, capturedAt: t, status: "fresh", reason: "ok", windows })
const win = (label: string, usedFraction: number, windowMinutes = 300, resetsAt: number | null = null) => ({ label, group: null, status: "fresh", unit: "percent", used: usedFraction * 100, remaining: null, limit: null, usedPercent: usedFraction * 100, usedFraction, windowMinutes, resetsAt })
let quota: Record<string, any> = {}
const observed: string[] = []
const newStore = () => ({ leases: new Map(), cooldowns: new Map(), caches: new Map(), registry })
let n = 0
const make = (store: any) => createRoute(store, { observe: async (p: string) => { observed.push(p); return quota[p] }, now: () => t, uuid: () => `lease-${++n}` })
// A ctx that throws like a stale extension ctx: route() must never touch it.
const vm = (id: string) => ({ provider: "route", id, api: "pi-virtual" })
const req = (id: string, extra: any = {}) => ({ model: vm(id), thinkingLevel: "off", reason: "user", messages: [], ...extra })
const ref = (r: any) => `${r.model.provider}/${r.model.id}:${r.thinkingLevel}`

// Pool state from real quota shapes.
assert.equal(poolState("anthropic", "claude-sonnet-5-5", undefined, t), "unknown")
assert.equal(poolState("anthropic", "claude-sonnet-5-5", fresh([win("Five-hour", 0.5)]), t), "normal")
assert.equal(poolState("anthropic", "claude-sonnet-5-5", fresh([win("Five-hour", 0.85)]), t), "conserve")
assert.equal(poolState("anthropic", "claude-sonnet-5-5", fresh([win("Five-hour", 0.96)]), t), "reserve")
assert.equal(poolState("anthropic", "claude-sonnet-5-5", fresh([win("Five-hour", 0.2), win("Weekly Sonnet", 1, 10080)]), t), "full")
assert.equal(poolState("anthropic", "claude-haiku-5-5", fresh([win("Five-hour", 0.2), win("Weekly Sonnet", 1, 10080)]), t), "normal") // scoped window not applicable
assert.equal(poolState("anthropic", "claude-haiku-5-5", fresh([win("Quota window", 1, 10080)]), t), "unknown") // generic window never decides
assert.equal(poolState("anthropic", "claude-haiku-5-5", fresh([win("Five-hour", 1, 300, t / 1000 - 1)]), t), "unknown") // passed reset
// Weekly ahead of pace (60% used with half the week left) tapers from 70% of the short window.
const half = t / 1000 + 5040 * 60
assert.equal(poolState("anthropic", "claude-haiku-5-5", fresh([win("Five-hour", 0.72), win("Weekly", 0.6, 10080, half)]), t), "conserve")
assert.equal(poolState("anthropic", "claude-haiku-5-5", fresh([win("Five-hour", 0.72), win("Weekly", 0.4, 10080, half)]), t), "normal")
assert.equal(poolState("opencode-go", "claude-haiku-5-5", fresh([win("Five-hour", 1)]), t), "full") // other collectors count
assert.equal(poolState("openai", "gpt-6-luna", fresh([win("Weekly", 1, 10080)]), t), "normal") // credit rollover
assert.deepEqual(CAPS, { normal: 8, unknown: 8, conserve: 3, reserve: 0, full: 0 })
assert.equal(classifyFailure("429 Too Many Requests"), "rate-limit")
assert.equal(classifyFailure("insufficient_quota"), "hard")
assert.equal(classifyFailure("503 overloaded"), "other")
assert.equal(classifyFailure(undefined), "other")

// Fresh worker takes the first eligible route and a lease; quota is read for the chain's pools.
let store: any = newStore()
let route = make(store)
let r = await route(req("narrow"))
assert.equal(ref(r), "opencode-go/claude-haiku-5-5:medium")
assert.deepEqual(r.state, { class: "narrow", provider: "opencode-go", id: "claude-haiku-5-5", thinking: "medium", lease: "lease-1" })
assert.deepEqual([...store.leases], [["lease-1", { pool: "opencode-go" }]])
assert.deepEqual(observed.sort(), ["anthropic", "github-copilot", "openai", "opencode-go"])

// Continuations are sticky, never re-check caps or quota, and keep the same lease.
observed.length = 0
quota["opencode-go"] = fresh([win("Five-hour", 1)])
const cont = await route(req("narrow", { reason: "continuation", state: r.state }))
assert.equal(ref(cont), "opencode-go/claude-haiku-5-5:medium")
assert.equal(cont.state, r.state)
assert.deepEqual(observed, [])
assert.equal(store.leases.size, 1)

// An observed full pool is skipped for fresh workers.
r = await route(req("explore"))
assert.equal(ref(r), "github-copilot/gpt-6-luna:high")
quota = {}

// Cap: 8 per pool normally, 3 at Conserve; the next worker spills to the next pool.
store = newStore(); route = make(store)
for (let i = 0; i < 8; i++) assert.equal((await route(req("substantive"))).model.provider, "anthropic")
assert.equal(ref(await route(req("substantive"))), "openai/gpt-6.2-sol:medium")
store = newStore(); route = make(store)
quota.anthropic = fresh([win("Five-hour", 0.85)])
const leases: any[] = []
for (let i = 0; i < 3; i++) leases.push((await route(req("substantive"))).state)
assert.equal((await route(req("substantive"))).model.provider, "openai")
// Concurrent fresh dispatch cannot overshoot the cap.
store = newStore(); route = make(store)
const many = await Promise.all(Array.from({ length: 6 }, () => route(req("substantive"))))
assert.equal(many.filter((x: any) => x.model.provider === "anthropic").length, 3)
// Difficult at Anthropic Conserve prefers the other pool first.
assert.equal(ref(await route(req("difficult"))), "openai/gpt-6.2-sol:xhigh")
quota = {}

// Reserve/Full with no alternative: the request fails with the reasons; nothing is leased.
store = newStore(); route = make(store)
quota.openai = undefined
missing = new Set(["openai/gpt-6.2-sol"])
quota.anthropic = fresh([win("Five-hour", 0.97)])
await assert.rejects(route(req("substantive")), /no eligible route.*reserve, 0\/0.*not registered/)
assert.equal(store.leases.size, 0)
missing = new Set(); quota = {}

// Lifecycle: settling releases exactly that worker's slot; inactivity alone never does.
store = newStore(); route = make(store)
const a = (await route(req("substantive"))).state, b = (await route(req("substantive"))).state
t += 24 * 3600_000
assert.equal(store.leases.size, 2)
const branch = (state: any, extra: any[] = []) => [{ type: "custom", customType: "pi.virtual-model-state", data: { provider: "route", modelId: state.class, state } }, ...extra]
assert.equal(latestLease(branch(a)), a.lease)
settle(store, branch(a), t)
assert.deepEqual([...store.leases.keys()], [b.lease])
// Resume of a settled worker re-takes its slot without a cap check, on the same route.
const resumed = await route(req("substantive", { state: a }))
assert.equal(resumed.state, a)
assert.equal(store.leases.size, 2)

// Retry: rate limits cool the pool and move the same lease on; other errors stay on the failed model.
const failed = (model: any, errorMessage: string) => ({ model, thinkingLevel: "medium", message: { stopReason: "error", errorMessage } })
const sonnet = registry.find("anthropic", "claude-sonnet-5-5")
const transient = await route(req("substantive", { reason: "retry", state: a, failed: failed(sonnet, "503 overloaded") }))
assert.equal(transient.model, sonnet)
const moved = await route(req("substantive", { reason: "retry", state: a, failed: failed(sonnet, "429 rate limit") }))
assert.equal(ref(moved), "openai/gpt-6.2-sol:medium")
assert.equal(moved.state.lease, a.lease)
assert.equal(store.leases.get(a.lease).pool, "openai")
assert.equal(store.cooldowns.get("anthropic"), t + COOLDOWN_MS)
// While cooling, fresh work skips the pool; a stored user turn on it moves too.
assert.equal((await route(req("substantive"))).model.provider, "openai")
assert.equal((await route(req("substantive", { state: b }))).model.provider, "openai")
t += COOLDOWN_MS + 1
assert.equal((await route(req("substantive"))).model.provider, "anthropic")

// A non-retryable refusal seen at settle cools the pool for later fresh workers.
store = newStore(); route = make(store)
const c = (await route(req("narrow"))).state
settle(store, branch(c, [{ type: "message", message: { role: "assistant", provider: "opencode-go", stopReason: "error", errorMessage: "GoUsageLimitError" } }]), t)
assert.equal(store.leases.size, 0)
assert.equal(ref(await route(req("narrow"))), "github-copilot/gpt-6-luna:high")

// Direct requests reuse the last physical model and never lease.
const direct = await route(req("narrow", { reason: "direct", previous: { model: sonnet, thinkingLevel: "high" } }))
assert.equal(direct.model, sonnet); assert.equal(direct.state, undefined)

// Extension wiring: six routes, registration in every session, route() ignores its (stale) ctx.
const g = globalThis as any
delete g[Symbol.for("dotfiles.worker-router.store")]
const registered = new Map<string, any>(); const handlers = new Map<string, any[]>()
const fakePi = () => ({ registerVirtualModel: (d: any) => registered.set(`${d.provider}/${d.id}`, d), on: (name: string, h: any) => handlers.set(name, [...(handlers.get(name) ?? []), h]) })
R.default(fakePi()); R.default(fakePi()) // root + one worker load
assert.deepEqual([...registered.keys()].sort(), ["route/difficult", "route/explore", "route/narrow", "route/review-deep", "route/substantive", "route/writing"])
assert.equal(registered.get("route/narrow").thinkingLevels, undefined)
const sessionCtx = (branchEntries: any[], prompt = "") => ({ modelRegistry: registry, sessionManager: { getBranch: () => branchEntries }, getSystemPrompt: () => prompt, ui: { notify: (m: string) => notes.push(m) } })
const notes: string[] = []
handlers.get("session_start")![0]({}, sessionCtx([]))
const stale = new Proxy({}, { get: () => { throw new Error("This extension ctx is stale") } })
quota = {}
// Wired route with the real collectors: route/writing only touches openai, which is never queried (credit rollover).
const shared = g[Symbol.for("dotfiles.worker-router.store")]
shared.caches = new Map()
shared.helpers = Promise.resolve(undefined) // no pi-usage helpers: other pools stay unknown
assert.equal(shared.registry, registry)
const wired = await registered.get("route/writing").route(req("writing"), stale)
assert.equal(ref(wired), "openai/gpt-6.1-terra:medium")
assert.equal(shared.leases.size, 1)
for (const h of handlers.get("agent_settled")!) h({}, sessionCtx(branch(wired.state)))
assert.equal(shared.leases.size, 0)
handlers.get("model_select")![0]({ model: vm("narrow") }, sessionCtx([]))
handlers.get("model_select")![0]({ model: vm("narrow") }, sessionCtx([], '<active_agent name="implementer"/>'))
assert.equal(notes.length, 1)
console.log("worker-router tests passed")
TS
