// Opt-in worker routing: `route/<class>` virtual models pick a physical route per request.
// Physical `provider/model` pins never pass through here. Never routes to `anthropic-api/` (paid credits).
import { randomUUID } from "node:crypto"
import { readFile } from "node:fs/promises"
import { join } from "node:path"
import { pathToFileURL } from "node:url"
import { getAgentDir, type ExtensionAPI, type ExtensionContext, type ModelRoute, type ModelRouteRequest } from "@earendil-works/pi-coding-agent"
import { observeAnthropic } from "./quota-status/anthropic.ts"
import { QuotaCache } from "./quota-status/cache.ts"
import { observe, type Helpers, type Observation } from "./quota-status/quota.ts"

export const PROVIDER = "route"
export type RouteClass = "explore" | "narrow" | "writing" | "substantive" | "difficult" | "review-deep"
export type Entry = { provider: string, id: string, thinking: "low" | "medium" | "high" | "xhigh" }
const e = (ref: string, thinking: Entry["thinking"]): Entry => ({ provider: ref.slice(0, ref.indexOf("/")), id: ref.slice(ref.indexOf("/") + 1), thinking })
const opusChain = [e("anthropic/claude-opus-5-5", "medium"), e("openai/gpt-6.2-sol", "xhigh"), e("anthropic/claude-sonnet-5-5", "high")]
// Mirrors the ordered rows of private_docs/coordinator-routing.md.
export const ROUTES: Record<RouteClass, Entry[]> = {
  explore: [e("opencode-go/claude-haiku-5-5", "medium"), e("github-copilot/gpt-6-luna", "high"), e("anthropic/claude-haiku-5-5", "medium"), e("openai/gpt-6-luna", "high")],
  narrow: [e("opencode-go/claude-haiku-5-5", "medium"), e("github-copilot/gpt-6-luna", "high"), e("anthropic/claude-haiku-5-5", "medium"), e("openai/gpt-6-luna", "high"), e("anthropic/claude-sonnet-5-5", "medium")],
  writing: [e("openai/gpt-6.1-terra", "medium"), e("openai/gpt-6.2-sol", "medium")],
  substantive: [e("anthropic/claude-sonnet-5-5", "medium"), e("openai/gpt-6.2-sol", "medium")],
  difficult: opusChain,
  "review-deep": opusChain,
}
const CONSERVE_PREFERS_OTHER_POOL = new Set<RouteClass>(["difficult", "review-deep"])
export const COOLDOWN_MS = 15 * 60_000
const QUOTA_TIMEOUT_MS = 5000

export type PoolState = "normal" | "conserve" | "reserve" | "full" | "unknown"
export const CAPS: Record<PoolState, number> = { normal: 8, unknown: 8, conserve: 3, reserve: 0, full: 0 }
export type RouterState = { class: RouteClass, provider: string, id: string, thinking: Entry["thinking"], lease: string }
type Registry = Pick<ExtensionContext["modelRegistry"], "find" | "getAvailable">
export type Store = {
  leases: Map<string, { pool: string }>
  cooldowns: Map<string, number>
  caches: Map<string, QuotaCache<Observation>>
  // Abort signals of agent runs in sessions that loaded this extension, so their agent_settled/session_shutdown hooks release leases.
  live: WeakSet<AbortSignal>
  registry?: Registry
  helpers?: Promise<Helpers | undefined>
}

// One store per process: root and worker sessions share the model runtime, so they share slots and cooldowns.
const KEY = Symbol.for("dotfiles.worker-router.store")
export function sharedStore(): Store {
  const g = globalThis as Record<symbol, Store | undefined>
  return (g[KEY] ??= { leases: new Map(), cooldowns: new Map(), caches: new Map(), live: new WeakSet() })
}

// Pool = provider subscription: Sol→Luna on one provider is not relief.
export function poolState(provider: string, modelId: string, obs: Observation | undefined, now: number): PoolState {
  // User-confirmed ChatGPT credit rollover: OpenAI allowance percentages are not holds.
  if (provider === "openai") return "normal"
  if (!obs || obs.status !== "fresh") return "unknown"
  const windows = obs.windows.filter((w) => w.usedFraction !== null && !(w.resetsAt !== null && w.resetsAt * 1000 <= now) && (provider !== "anthropic"
    || w.label === "Five-hour" || w.label === "Weekly" || (w.label === "Weekly Sonnet" && modelId.includes("sonnet")) || (w.label === "Weekly Opus" && modelId.includes("opus"))))
  if (!windows.length) return "unknown"
  const max = Math.max(...windows.map((w) => w.usedFraction!))
  if (max >= 1) return "full"
  if (max >= 0.95) return "reserve"
  if (max >= 0.8) return "conserve"
  // Weekly guard: a long window ahead of linear pace tapers the short window from 70%.
  const aheadOfPace = windows.some((w) => w.windowMinutes !== null && w.windowMinutes >= 10080 && w.resetsAt !== null
    && w.usedFraction! > 1 - (w.resetsAt * 1000 - now) / (w.windowMinutes * 60_000))
  const short = windows.filter((w) => w.windowMinutes !== null && w.windowMinutes < 10080)
  return aheadOfPace && short.some((w) => w.usedFraction! >= 0.7) ? "conserve" : "normal"
}

export type Choice = { entry: Entry } | { reasons: string[] }
export function chooseRoute(cls: RouteClass, input: { available: (e: Entry) => boolean, state: (e: Entry) => PoolState, active: (pool: string) => number, cooledUntil: (pool: string) => number | undefined, now: number }): Choice {
  let chain = ROUTES[cls]
  if (CONSERVE_PREFERS_OTHER_POOL.has(cls) && input.state(chain[0]) === "conserve") chain = [...chain.filter((x) => x.provider !== chain[0].provider), ...chain.filter((x) => x.provider === chain[0].provider)]
  const reasons: string[] = []
  for (const entry of chain) {
    const ref = `${entry.provider}/${entry.id}`
    if (!input.available(entry)) { reasons.push(`${ref}: not registered with auth`); continue }
    const until = input.cooledUntil(entry.provider)
    if (until !== undefined && until > input.now) { reasons.push(`${ref}: ${entry.provider} cooling down after a rate limit`); continue }
    const state = input.state(entry), active = input.active(entry.provider)
    if (active >= CAPS[state]) { reasons.push(`${ref}: ${entry.provider} ${state}, ${active}/${CAPS[state]} worker slots used`); continue }
    return { entry }
  }
  return { reasons }
}

// Only patterns Pi itself retries reach route() as `retry`; non-retryable limits end the run.
const RATE_LIMIT = /rate.?limit|too many requests|(?<![a-z0-9])429(?![a-z0-9])|ResourceExhausted|usage_unavailable|user_unavailable/i
const HARD_LIMIT = /GoUsageLimitError|FreeUsageLimitError|usage limit|available balance|insufficient_quota|out of budget|quota exceeded|billing|(?<![a-z0-9])(?:401|402)(?![a-z0-9])|unauthorized|authentication/i
export function classifyFailure(errorMessage: string | undefined): "rate-limit" | "hard" | "other" {
  if (!errorMessage) return "other"
  return HARD_LIMIT.test(errorMessage) ? "hard" : RATE_LIMIT.test(errorMessage) ? "rate-limit" : "other"
}

export type Deps = { observe: (provider: string, registry: Registry) => Promise<Observation | undefined>, now?: () => number, uuid?: () => string }

export function createRoute(store: Store, deps: Deps) {
  const now = deps.now ?? Date.now, uuid = deps.uuid ?? randomUUID
  return async (request: ModelRouteRequest<RouterState>): Promise<ModelRoute<RouterState>> => {
    const cls = request.model.id as RouteClass
    if (!ROUTES[cls]) throw new Error(`Unknown worker route ${PROVIDER}/${request.model.id}.`)
    // The ctx Pi passes to route() belongs to whichever session registered last and may be stale; never use it.
    const registry = store.registry
    if (!registry) throw new Error(`${PROVIDER}/${cls}: no live session has bound the model registry yet.`)
    const find = (entry: { provider: string, id: string }) => registry.find(entry.provider, entry.id)
    const available = (entry: { provider: string, id: string }) => !!find(entry) && registry.getAvailable().some((m) => m.provider === entry.provider && m.id === entry.id)
    const cooled = (pool: string) => (store.cooldowns.get(pool) ?? 0) > now()
    const sticky = (state: RouterState): ModelRoute<RouterState> => {
      // A running worker keeps its slot; resumes and continuations finish normally without a cap check.
      store.leases.set(state.lease, { pool: state.provider })
      return { model: find(state)!, thinkingLevel: state.thinking, state }
    }
    const fresh = async (lease: string): Promise<ModelRoute<RouterState>> => {
      const pools = [...new Set(ROUTES[cls].map((x) => x.provider))]
      const observed = new Map(await Promise.all(pools.map(async (pool) => [pool, await deps.observe(pool, registry).catch(() => undefined)] as const)))
      // Synchronous from here: the cap check and the lease write cannot interleave with another route().
      const t = now()
      const choice = chooseRoute(cls, {
        available, now: t,
        state: (x) => poolState(x.provider, x.id, observed.get(x.provider), t),
        active: (pool) => [...store.leases.entries()].filter(([id, l]) => l.pool === pool && id !== lease).length,
        cooledUntil: (pool) => store.cooldowns.get(pool),
      })
      if (!("entry" in choice)) throw new Error(`${PROVIDER}/${cls}: no eligible route; work stays pending (${choice.reasons.join("; ")}).`)
      const state: RouterState = { class: cls, provider: choice.entry.provider, id: choice.entry.id, thinking: choice.entry.thinking, lease }
      store.leases.set(lease, { pool: state.provider })
      return { model: find(state)!, thinkingLevel: state.thinking, state }
    }
    const state = request.state
    // Fail closed: route() is runtime-wide, but only a session running this extension releases its lease. A worker without it
    // (extensions: false, isolated: true, an allowlist or exclude_extensions omitting it, an unknown role policy) would leak a slot.
    if (request.reason !== "direct" && !(request.signal && store.live.has(request.signal))) {
      throw new Error(`${PROVIDER}/${cls}: this session does not run the worker-router extension, so its slot could never be released; use an exact provider/model route or a role that loads worker-router.`)
    }
    if (request.reason === "direct") {
      // Compaction summaries etc. have no state: reuse the model that answered last, else the first available route.
      if (request.previous) return { model: request.previous.model, thinkingLevel: request.previous.thinkingLevel ?? "medium" }
      const entry = ROUTES[cls].find((x) => available(x) && !cooled(x.provider))
      if (!entry) throw new Error(`${PROVIDER}/${cls}: no available route for a direct request.`)
      return { model: find(entry)!, thinkingLevel: entry.thinking }
    }
    if (request.reason === "retry" && state && request.failed) {
      const failure = classifyFailure(request.failed.message.errorMessage)
      if (failure === "other") return { model: request.failed.model, thinkingLevel: request.failed.thinkingLevel ?? state.thinking }
      store.cooldowns.set(request.failed.model.provider, now() + COOLDOWN_MS)
      return fresh(state.lease)
    }
    if (state && available(state) && (request.reason === "continuation" || !cooled(state.provider))) return sticky(state)
    return fresh(state?.lease ?? uuid())
  }
}

// Exact pin shared with quota-status/index.ts; bump both together.
async function loadHelpers(): Promise<Helpers | undefined> {
  const root = join(getAgentDir(), "npm", "node_modules", "@narumitw", "pi-usage")
  try {
    const manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8")) as { name?: unknown, version?: unknown }
    if (manifest.name !== "@narumitw/pi-usage" || manifest.version !== "0.66.0") return undefined
    const addon = await import(pathToFileURL(join(root, "dist", "index.ts")).href)
    return [addon.adapterForProvider, addon.resolveUsageAuth, addon.queryProviderUsage].every((v) => typeof v === "function") ? addon as Helpers : undefined
  } catch {
    return undefined
  }
}

// Reuses quota-status collectors with process-wide 60 s caches; failures stay unknown, never headroom.
export function observePool(store: Store) {
  return async (provider: string, registry: Registry): Promise<Observation | undefined> => {
    if (provider === "openai") return undefined
    let cache = store.caches.get(provider)
    if (!cache) store.caches.set(provider, cache = new QuotaCache<Observation>())
    // SAFETY: the collectors only read modelRegistry and an optional selected model.
    const ctx = { modelRegistry: registry, model: undefined } as unknown as ExtensionContext
    if (provider === "anthropic") return observeAnthropic(ctx, undefined, QUOTA_TIMEOUT_MS, { cache })
    if (provider !== "github-copilot" && provider !== "opencode-go") return undefined
    const helpers = await (store.helpers ??= loadHelpers())
    return helpers ? observe(provider, helpers, ctx, undefined, QUOTA_TIMEOUT_MS, undefined, { cache }) : undefined
  }
}

type BranchEntry = { type: string, customType?: string, data?: unknown, message?: { role?: string, provider?: string, stopReason?: string, errorMessage?: string } }
export function latestLease(branch: readonly BranchEntry[]): string | undefined {
  for (let i = branch.length - 1; i >= 0; i--) {
    const entry = branch[i]
    const data = entry.data as { provider?: unknown, state?: { lease?: unknown } } | undefined
    if (entry.type === "custom" && entry.customType === "pi.virtual-model-state" && data?.provider === PROVIDER) return typeof data.state?.lease === "string" ? data.state.lease : undefined
  }
}

// Called with the settling session's own ctx: release its slot and cool a pool that refused it outright.
export function settle(store: Store, branch: readonly BranchEntry[], now = Date.now()): void {
  const lease = latestLease(branch)
  if (!lease) return
  store.leases.delete(lease)
  const last = [...branch].reverse().find((entry) => entry.type === "message" && entry.message?.role === "assistant")?.message
  if (last?.stopReason === "error" && last.provider && classifyFailure(last.errorMessage) !== "other") store.cooldowns.set(last.provider, now + COOLDOWN_MS)
}

const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())

export default function (pi: ExtensionAPI) {
  const store = sharedStore()
  const route = createRoute(store, { observe: observePool(store) })
  // Every session registers; Pi replaces the definition and route() reads only the shared store.
  for (const cls of Object.keys(ROUTES) as RouteClass[]) {
    pi.registerVirtualModel<RouterState>({ provider: PROVIDER, id: cls, name: `Worker route: ${cls}`, route: (request) => route(request) })
  }
  pi.on("session_start", (_event, ctx) => { store.registry = ctx.modelRegistry })
  pi.on("agent_start", (_event, ctx) => { if (ctx.signal) store.live.add(ctx.signal) })
  pi.on("agent_settled", (_event, ctx) => settle(store, ctx.sessionManager.getBranch() as readonly BranchEntry[]))
  pi.on("session_shutdown", (_event, ctx) => { const lease = latestLease(ctx.sessionManager.getBranch() as readonly BranchEntry[]); if (lease) store.leases.delete(lease) })
  pi.on("model_select", (event, ctx) => {
    if (event.model.provider === PROVIDER && !isWorker(ctx)) ctx.ui.notify(`${PROVIDER}/* models are for workers; the coordinator should stay on its routine model.`, "warning")
  })
}
