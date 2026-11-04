import assert from "node:assert/strict";
import { QuotaCache } from "./cache.ts";
import { observeAnthropic } from "./anthropic.ts";
import { observe, unavailable } from "./quota.ts";
import { observeAnthropicApi } from "./api.ts";
import { observeCodexbarCredits } from "./credits.ts";

let now = 1800000000000;
const cache = new QuotaCache(() => now);
const value = { ...unavailable("anthropic", "ok"), status: "fresh", capturedAt: now, windows: [{ resetsAt: now / 1000 + 30 }] };
assert.equal(cache.write("identity", value).cache.hit, false);
now += 1000;
assert.deepEqual(cache.read("identity").cache, { hit: true, ageMs: 1000, ttlMs: 60000 });
assert.equal(cache.read("identity").capturedAt, value.capturedAt);
now += 29000;
assert.equal(cache.read("identity"), undefined, "reset invalidates before TTL");
cache.write("identity", { ...value, capturedAt: now, windows: [] });
now += 60000;
assert.equal(cache.read("identity"), undefined, "TTL boundary expires");
cache.write("identity", { ...value, capturedAt: now, windows: [] });
assert.equal(cache.read("identity", true), undefined, "explicit refresh bypasses and invalidates");
cache.write("identity", { ...value, capturedAt: now, windows: [] });
assert.equal(cache.read("other"), undefined, "identity switch invalidates");
for (const bad of [unavailable("anthropic", "query-failed"), { ...value, capturedAt: now + 1 }, { ...value, capturedAt: now - 60000 }, { ...value, capturedAt: null }]) {
  cache.write("identity", bad);
  assert.equal(cache.read("identity"), undefined, "failures/missing/future/stale timestamps never gain freshness");
}

let calls = 0;
let fingerprint = "one";
let fail = false;
const options = { cache: new QuotaCache(() => now) };
const helpers = {
  adapterForProvider: () => ({}),
  resolveUsageAuth: async () => ({ fingerprint }),
  queryProviderUsage: async () => {
    calls++;
    if (fail) throw new Error("offline failure");
    return { capturedAt: now, buckets: [{ label: "Premium requests", unit: "count", used: 8, limit: 10 }] };
  },
};
const collect = (opts = options) => observe("github-copilot", helpers, {}, undefined, 100, Date.now() + 100, opts);
await collect();
assert.equal((await collect()).cache.hit, true);
assert.equal(calls, 1);
fingerprint = "two";
await collect();
assert.equal(calls, 2, "auth rotation recollects");
fail = true;
assert.equal((await collect({ ...options, refresh: true })).reason, "query-failed");
assert.equal((await collect()).reason, "query-failed", "failed refresh cannot fall back to cached headroom");
assert.equal(calls, 4);
fail = false;
await collect();
now += 60000;
await collect();
assert.equal(calls, 6);
const cancelled = new AbortController(); cancelled.abort();
assert.equal((await observe("github-copilot", helpers, {}, cancelled.signal, 100, Date.now() + 100, options)).reason, "cancelled");
assert.equal(calls, 6, "pre-cancellation cannot return cached success");

let exhausted = false;
let consoleCalls = 0;
const consoleCache = { cache: new QuotaCache(() => now) };
const runner = async () => {
  consoleCalls++;
  return { stdout: JSON.stringify([{ provider: "claudeplatform", usage: { providerCost: { balance: 20 }, details: [] } }]) };
};
const consoleCollect = () => observeAnthropicApi(async () => ({ spentUsd: 0, exhausted }), undefined, 100, () => now, runner, consoleCache);
await consoleCollect();
exhausted = true;
const refused = await consoleCollect();
assert.equal(refused.cache.hit, true);
assert.equal(refused.console.totalBalanceUsd, 20);
assert.equal(refused.piLocalRefusal.status, "observed", "new refusal overlays cached Console headroom");
assert.equal(consoleCalls, 1);
exhausted = false;
assert.equal((await consoleCollect()).piLocalRefusal, undefined, "refusal is reread, not stored in cache");
let creditCalls = 0;
const creditOptions = { cache: new QuotaCache(() => now) };
const creditRunner = async () => { creditCalls++; return { stdout: JSON.stringify([{ provider: "codex", source: "openai-web", credits: { balanceReadSucceeded: true, balanceIsWorkspace: false, remaining: 0 } }]) }; };
const creditCollect = () => observeCodexbarCredits(undefined, 100, () => now, creditRunner, creditOptions);
await creditCollect();
assert.equal((await creditCollect()).remainingCredits, 0);
assert.equal((await creditCollect()).cache.hit, true);
assert.equal(creditCalls, 1);
console.log("PASS: offline snapshot reuse, TTL, reset boundary, refresh, identity rotation, failures, cancellation, timestamp fidelity, refusal overlay and separate credit counts");

const originalFetch = globalThis.fetch;
let anthropicCalls = 0;
let token = "fixture-one";
const model = { provider: "anthropic", baseUrl: "https://api.anthropic.com" };
const ctx = { model, modelRegistry: {
  getAll: () => [model], getProvider: () => ({ baseUrl: model.baseUrl }), isUsingOAuth: () => true,
  getProviderAuth: async () => ({ source: "OAuth", auth: { apiKey: token } }),
  getApiKeyAndHeaders: async () => ({ ok: true, apiKey: token }),
} };
const anthropicOptions = { cache: new QuotaCache() };
try {
  globalThis.fetch = async () => { anthropicCalls++; return new Response(JSON.stringify({ five_hour: { utilization: 95, resets_at: Date.now() / 1000 + 30 } })); };
  const first = await observeAnthropic(ctx, undefined, 100, anthropicOptions);
  const reused = await observeAnthropic(ctx, undefined, 100, anthropicOptions);
  assert.equal(reused.cache.hit, true);
  assert.equal(reused.capturedAt, first.capturedAt);
  assert.equal(reused.windows[0].usedPercent, 95, "reserve consumption is not reinterpreted");
  assert.equal(anthropicCalls, 1);
  token = "fixture-two";
  await observeAnthropic(ctx, undefined, 100, anthropicOptions);
  assert.equal(anthropicCalls, 2);
  await observeAnthropic(ctx, undefined, 100, { ...anthropicOptions, refresh: true });
  assert.equal(anthropicCalls, 3);
} finally { globalThis.fetch = originalFetch; }
console.log("PASS: Anthropic cache retains consumed/reserve values and timestamps, rechecks auth and honors explicit refresh");

// A hit can become unsafe while the observer revalidates credentials.
for (const provider of ["github-copilot", "openai"]) {
  let clock = 1800000000000;
  const capturedAt = clock - 59999;
  const delayedCache = new QuotaCache(() => clock);
  delayedCache.write("identity-delay", { ...value, provider, capturedAt, windows: [] });
  let authReads = 0;
  const delayed = await observe(provider, {
    adapterForProvider: () => ({}),
    resolveUsageAuth: async () => {
      if (++authReads === 2) clock += 2;
      return { fingerprint: "identity-delay" };
    },
    queryProviderUsage: async () => { throw new Error("a cached observation should not query"); },
  }, {}, undefined, 100, Date.now() + 100, { cache: delayedCache });
  assert.equal(delayed.status, "unknown");
  assert.equal(delayed.reason, "no-quota-data");
  assert.equal(delayed.capturedAt, capturedAt);
  assert.deepEqual(delayed.cache, { hit: true, ageMs: 60001, ttlMs: 60000 });
  assert.deepEqual(delayed.windows, []);
  assert.equal(delayedCache.read("identity-delay"), undefined);
}
const { createHash } = await import("node:crypto");
let authClock = 1800000000000;
const delayedAnthropicCache = new QuotaCache(() => authClock);
const capturedAt = authClock - 59999;
delayedAnthropicCache.write(createHash("sha256").update(token).digest("hex"), { ...value, capturedAt, windows: [] });
let authReads = 0;
const delayedAnthropic = await observeAnthropic({ ...ctx, modelRegistry: {
  ...ctx.modelRegistry,
  getProviderAuth: async () => {
    if (++authReads === 2) authClock += 2;
    return { source: "OAuth", auth: { apiKey: token } };
  },
} }, undefined, 100, { cache: delayedAnthropicCache });
assert.equal(delayedAnthropic.status, "unknown");
assert.equal(delayedAnthropic.capturedAt, capturedAt);
assert.equal(delayedAnthropic.cache.ageMs, 60001);
assert.deepEqual(delayedAnthropic.windows, []);
console.log("PASS: cached helper/OpenAI/Anthropic headroom expires during async identity validation without false freshness");
