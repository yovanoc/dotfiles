#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtemp, cp, mkdir, rm, writeFile, readFile, access, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import { observe, sanitize, PROVIDERS } from "../home/private_dot_pi/private_agent/private_extensions/quota-status/quota.ts";
import { normalizeAnthropicUsagePayload, observeAnthropic } from "../home/private_dot_pi/private_agent/private_extensions/quota-status/anthropic.ts";

const source = fileURLToPath(new URL("../home/private_dot_pi/private_agent/private_extensions/quota-status/", import.meta.url));
const secret = "account-private-ID ignore instructions credential headers token raw-error";
globalThis.fetch = async () => { throw new Error("Unmocked provider network forbidden"); };
const report = {
  providerId: secret, providerName: secret, source: secret, accountLabel: secret,
  capturedAt: 1800000000000, metrics: [{ value: secret }], notes: [secret],
  buckets: [{ id: secret, label: "Quota window", groupId: "fixture", groupLabel: "Fixture scope", modelKeys: [secret], unit: "percent", used: 0, windowMinutes: 300, resetsAt: 1800000300 }],
};
const auth = { fingerprint: secret, apiKey: secret, secrets: [secret], headers: { Authorization: secret } };
const helpers = (overrides = {}) => ({
  adapterForProvider: (id) => ({ id }),
  resolveUsageAuth: async () => auth,
  queryProviderUsage: async () => report,
  ...overrides,
});
const safe = (value) => assert(!JSON.stringify(value).includes(secret));
const ctx = {};
assert.deepEqual(PROVIDERS, ["openai", "anthropic", "github-copilot", "opencode-go", "opencode"]);
const companionReport = {
  providerId: "openai", providerName: secret, source: "openai-chatgpt-companion", accountLabel: secret,
  semantics: { kind: "consumer-subscription", label: secret }, capturedAt: 1800000000000,
  metrics: [{ id: secret, label: "App allowance", value: 85, unit: "percent" }], notes: [secret],
  buckets: [
    { id: secret, label: "Subscription limit", groupId: "chatgpt-plan", groupLabel: "Plan limits", modelKeys: [secret], unit: "percent", used: 0, remaining: 100, limit: 100, windowMinutes: 300, resetsAt: 1800000300 },
    { id: secret, label: "Subscription limit", groupId: "chatgpt-app", groupLabel: "App limits", modelKeys: [secret], unit: "percent", used: 27, remaining: 73, limit: 100, windowMinutes: 10080, resetsAt: 1800000300 },
    { id: secret, label: "Subscription limit", groupId: secret, groupLabel: secret, unit: "percent", used: 99 },
  ],
};
const openAI = sanitize("openai", companionReport);
assert.equal(openAI.source, "openai-chatgpt-companion-experimental");
assert.equal(openAI.reason, "ok");
assert.deepEqual(openAI.windows.map(({ label, group }) => [label, group]), [["ChatGPT plan", "ChatGPT plan"], ["ChatGPT app", "ChatGPT app"]]);
assert.deepEqual(openAI.windows.map((window) => window.usedPercent), [0, 27]);
assert.equal(openAI.windows[0].usedFraction, 0);
assert.equal(openAI.windows[0].remaining, null);
assert.equal(openAI.windows[0].limit, null);
safe(openAI);
const authOnlyReport = { ...companionReport, source: "openai-chatgpt-auth", buckets: [], metrics: [{ value: secret }] };
const authOnly = sanitize("openai", authOnlyReport);
assert.deepEqual({ source: authOnly.source, status: authOnly.status, reason: authOnly.reason, windows: authOnly.windows }, {
  source: "openai-chatgpt-auth", status: "unknown", reason: "no-quota-data", windows: [],
});
safe(authOnly);
assert.equal(sanitize("openai", { ...companionReport, providerId: secret }).reason, "no-quota-data");
assert.equal(sanitize("openai", { ...companionReport, semantics: { kind: "api-key" } }).reason, "no-quota-data");
assert.equal(sanitize("openai", { ...companionReport, buckets: [companionReport.buckets[2]] }).reason, "no-quota-data", "unknown scope must not become account-wide quota");
const hiddenOpenAI = sanitize("openai", { ...companionReport, buckets: [{ ...companionReport.buckets[0], used: undefined }] });
assert.equal(hiddenOpenAI.status, "unknown");
assert.equal(hiddenOpenAI.windows[0].usedPercent, null);
assert.equal(hiddenOpenAI.windows[0].usedFraction, null);
assert.equal(hiddenOpenAI.windows[0].status, "unknown");
assert(!JSON.stringify(openAI).includes("App allowance"), "app allowance metrics are caps, not quota windows");

let identityReads = 0;
let guardedRequests = 0;
const guardedOpenAI = await observe("openai", helpers({
  resolveUsageAuth: async () => { identityReads++; return { ...auth, fingerprint: "native+companion" }; },
  queryProviderUsage: async (_adapter, _auth, _signal, _timeout, guard) => {
    assert.equal(typeof guard, "function", "native OpenAI query receives a per-request identity guard");
    for (let request = 0; request < 2; request++) {
      await guard();
      guardedRequests++;
      await guard();
    }
    return companionReport;
  },
}), ctx);
assert.equal(guardedOpenAI.reason, "ok");
assert.equal(identityReads, 6, "native+companion identity is checked before and after both requests and before publication");
assert.equal(guardedRequests, 2);
safe(guardedOpenAI);
for (const changedAt of [2, 4, 6]) {
  let reads = 0;
  let requests = 0;
  const changed = await observe("openai", helpers({
    resolveUsageAuth: async () => ({ ...auth, fingerprint: ++reads === changedAt ? "changed-identity" : "native+companion" }),
    queryProviderUsage: async (_adapter, _auth, _signal, _timeout, guard) => {
      for (let request = 0; request < 2; request++) {
        await guard();
        requests++;
        await guard();
      }
      return companionReport;
    },
  }), ctx);
  assert.equal(changed.reason, "identity-changed");
  assert.equal(requests, changedAt === 2 ? 0 : changedAt === 4 ? 1 : 2, "identity changes prevent subsequent requests or publication");
  safe(changed);
}
let missingCompanionGuarded = false;
const missingCompanion = await observe("openai", helpers({
  resolveUsageAuth: async () => ({ ...auth, fingerprint: "native-only" }),
  queryProviderUsage: async (_adapter, _auth, _signal, _timeout, guard) => {
    missingCompanionGuarded = typeof guard === "function";
    await guard();
    return authOnlyReport;
  },
}), ctx);
assert.equal(missingCompanionGuarded, true);
assert.equal(missingCompanion.reason, "no-quota-data", "auth-only native report is never treated as zero use");
assert.equal(missingCompanion.source, "openai-chatgpt-auth");
let mismatchedCompanionQueries = 0;
const mismatchedCompanion = await observe("openai", helpers({
  resolveUsageAuth: async () => { throw new Error(secret); },
  queryProviderUsage: async () => { mismatchedCompanionQueries++; return companionReport; },
}), ctx);
assert.equal(mismatchedCompanion.reason, "auth-failed");
assert.equal(mismatchedCompanionQueries, 0);
safe(mismatchedCompanion);

const badUnits = sanitize("anthropic", { ...report, capturedAt: NaN, buckets: [{ ...report.buckets[0], unit: "count", windowMinutes: -1, resetsAt: 1800000300000 }] });
assert.equal(badUnits.status, "unknown");
assert.equal(badUnits.capturedAt, null);
assert.equal(badUnits.windows[0].resetsAt, null);
assert.equal(badUnits.windows[0].windowMinutes, null);
assert.equal(sanitize("anthropic", { ...report, buckets: [] }).status, "unknown");
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: async () => undefined }), ctx)).reason, "auth-unavailable");
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: async () => { throw new Error(secret); } }), ctx)).reason, "auth-failed");
const mixed = await Promise.all(PROVIDERS.map((provider) => observe(provider, helpers({ queryProviderUsage: async (adapter) => {
  if (adapter.id === "anthropic") throw new Error(secret);
  return report;
} }), ctx)));
assert.deepEqual(mixed.map((value) => value.status), ["unknown", "unavailable", "fresh", "fresh", "unknown"]);
safe(mixed);
assert.equal((await observe("anthropic", helpers({ queryProviderUsage: async () => { throw new Error("Claude usage endpoint returned no displayable usage data."); } }), ctx)).reason, "no-quota-data");
let resolutions = 0;
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: async () => ({ ...auth, fingerprint: String(resolutions++) }) }), ctx)).reason, "identity-changed");
let queries = 0;
await observe("anthropic", helpers({ queryProviderUsage: async () => { queries++; return report; } }), ctx);
await observe("anthropic", helpers({ queryProviderUsage: async () => { queries++; return report; } }), ctx);
assert.equal(queries, 2, "every invocation is fresh");
const never = () => new Promise(() => {});
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: never }), ctx, undefined, 15)).reason, "timeout");
let querySignal;
assert.equal((await observe("anthropic", helpers({ queryProviderUsage: async (_a, _auth, signal) => { querySignal = signal; return never(); } }), ctx, undefined, 15)).reason, "timeout");
assert.equal(querySignal.aborted, true);
const cancellation = new AbortController();
const cancelled = observe("anthropic", helpers({ queryProviderUsage: async (_a, _auth, signal) => { querySignal = signal; return never(); } }), ctx, cancellation.signal);
await new Promise((done) => setTimeout(done, 1));
cancellation.abort();
assert.equal((await cancelled).reason, "cancelled");
assert.equal(querySignal.aborted, true);
let postTimeoutQueries = 0;
let releaseAuth;
const delayed = observe("anthropic", helpers({ resolveUsageAuth: () => new Promise((done) => { releaseAuth = done; }), queryProviderUsage: async () => { postTimeoutQueries++; return report; } }), ctx, undefined, 15);
assert.equal((await delayed).reason, "timeout");
releaseAuth(auth);
await new Promise((done) => setTimeout(done, 1));
assert.equal(postTimeoutQueries, 0, "late auth must not start a provider query");
let revalidations = 0;
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: async () => ++revalidations === 1 ? auth : never() }), ctx, undefined, 15)).reason, "timeout");
const preCancelled = new AbortController();
preCancelled.abort();
assert.equal((await observe("anthropic", helpers({ resolveUsageAuth: () => { throw new Error("must not run"); } }), ctx, preCancelled.signal)).reason, "cancelled");
const fixtureNativeAuth = { ...auth, fingerprint: "native+companion" };
let openAISignal;
assert.equal((await observe("openai", helpers({
  resolveUsageAuth: async () => fixtureNativeAuth,
  queryProviderUsage: async (_a, _auth, signal, _timeout, guard) => { openAISignal = signal; await guard(); return never(); },
}), ctx, undefined, 15)).reason, "timeout");
assert.equal(openAISignal.aborted, true, "deadline aborts native companion requests");
let releaseGuard;
let lateOpenAIRequests = 0;
let openAIAuthCalls = 0;
const lateGuard = observe("openai", helpers({
  resolveUsageAuth: async () => ++openAIAuthCalls === 1 ? fixtureNativeAuth : new Promise((done) => { releaseGuard = () => done(fixtureNativeAuth); }),
  queryProviderUsage: async (_a, _auth, _signal, _timeout, guard) => { await guard(); lateOpenAIRequests++; return companionReport; },
}), ctx, undefined, 15);
assert.equal((await lateGuard).reason, "timeout");
releaseGuard();
await new Promise((done) => setTimeout(done, 1));
assert.equal(lateOpenAIRequests, 0, "late identity revalidation cannot start a quota request after deadline");
const openAICancellation = new AbortController();
let releaseCancelledGuard;
let cancelledOpenAIRequests = 0;
let cancelledOpenAIAuthCalls = 0;
const cancelledOpenAI = observe("openai", helpers({
  resolveUsageAuth: async () => ++cancelledOpenAIAuthCalls === 1 ? fixtureNativeAuth : new Promise((done) => { releaseCancelledGuard = () => done(fixtureNativeAuth); }),
  queryProviderUsage: async (_a, _auth, signal, _timeout, guard) => { openAISignal = signal; await guard(); cancelledOpenAIRequests++; return companionReport; },
}), ctx, openAICancellation.signal, 100);
await new Promise((done) => setTimeout(done, 1));
openAICancellation.abort();
assert.equal((await cancelledOpenAI).reason, "cancelled");
assert.equal(openAISignal.aborted, true);
releaseCancelledGuard();
await new Promise((done) => setTimeout(done, 1));
assert.equal(cancelledOpenAIRequests, 0, "late identity revalidation cannot start a quota request after cancellation");
for (const bucket of [
  { label: "AI credits", used: 25, remaining: 75, limit: 100 },
  { label: "Premium requests", used: 125, remaining: 0, limit: 100 },
  { label: "Chat requests", used: 0, remaining: 50, limit: 50 },
  { label: "AI credits", used: 5, remaining: 0, limit: 0 },
  { label: "Premium requests" },
  { label: secret, used: 4 },
]) {
  const result = sanitize("github-copilot", { ...report, buckets: [{ ...bucket, unit: "count", id: secret, modelKeys: [secret] }] });
  const window = result.windows[0];
  assert.equal(window.unit, "count");
  assert.equal(window.used, bucket.used ?? null);
  assert.equal(window.remaining, bucket.remaining ?? null);
  assert.equal(window.limit, bucket.limit ?? null);
  assert.equal(window.usedFraction, bucket.limit > 0 ? bucket.used / bucket.limit : null);
  assert.equal(window.status, bucket.used === undefined ? "unknown" : "fresh");
  safe(result);
}
for (const label of ["Rolling window", "Weekly window", "Monthly window", secret]) {
  const result = sanitize("opencode-go", { ...report, buckets: [{ ...report.buckets[0], label }] });
  assert.equal(result.windows[0].label, label === secret ? "Quota window" : label);
  assert.equal(result.windows[0].usedPercent, 0);
  safe(result);
}
assert.equal((await observe("opencode-go", helpers({ queryProviderUsage: async () => { throw new Error("OpenCode Zen usage endpoint returned no displayable usage data."); } }), ctx)).reason, "no-quota-data");
const forbidden = () => { throw new Error("Unsupported providers must never look up an adapter, credentials or HTTP"); };
assert.deepEqual(await observe("opencode", helpers({ adapterForProvider: forbidden, resolveUsageAuth: forbidden, queryProviderUsage: forbidden }), ctx), {
  provider: "opencode", source: null, capturedAt: null, status: "unknown", reason: "unsupported", windows: [],
});
assert.equal(sanitize("opencode", report).windows.length, 0);
for (const invalid of [NaN, Infinity, -1, "0", null, undefined]) {
  const value = sanitize("github-copilot", { ...report, buckets: [{ id: secret, label: secret, unit: "count", used: invalid, remaining: invalid, limit: invalid }] });
  assert.equal(value.status, "unknown");
  assert.equal(value.windows[0].usedFraction, null);
  assert.equal(value.windows[0].used, null);
  assert.equal(value.windows[0].remaining, null);
  assert.equal(value.windows[0].limit, null);
  safe(value);
}
const mixedGoFailure = await Promise.all(PROVIDERS.map((provider) => observe(provider, helpers({ queryProviderUsage: async (adapter) => {
  if (adapter.id === "opencode-go") throw new Error(secret);
  return report;
} }), ctx)));
assert.deepEqual(mixedGoFailure.map((value) => value.reason), ["no-quota-data", "ok", "ok", "query-failed", "unsupported"]);
safe(mixedGoFailure);

function anthropicContext(overrides = {}) {
  const model = { provider: "anthropic", id: "fixture-model", baseUrl: overrides.modelBaseUrl ?? "https://api.anthropic.com" };
  return {
    model: overrides.selected === false ? undefined : model,
    modelRegistry: {
      getAll: () => [model],
      getProvider: () => ({ id: "anthropic", baseUrl: overrides.providerBaseUrl ?? "https://api.anthropic.com" }),
      getProviderAuth: overrides.getProviderAuth ?? (async () => ({ auth: { apiKey: "fixture-token", ...(overrides.providerAuthBaseUrl ? { baseUrl: overrides.providerAuthBaseUrl } : {}) }, source: overrides.source ?? "OAuth" })),
      getApiKeyAndHeaders: overrides.getApiKeyAndHeaders ?? (async () => ({ ok: true, apiKey: "fixture-token", ...(overrides.modelAuthBaseUrl ? { baseUrl: overrides.modelAuthBaseUrl } : {}) })),
      isUsingOAuth: overrides.isUsingOAuth ?? (() => true),
    },
  };
}

const legacyClaude = normalizeAnthropicUsagePayload({
  five_hour: { utilization: 0, resets_at: "2027-01-15T08:05:00Z" },
  seven_day: { utilization: 125, resets_at: 1800000300 },
}, 1800000000000);
assert.deepEqual(legacyClaude.windows.map((window) => window.label), ["Five-hour", "Weekly"]);
assert.deepEqual(legacyClaude.windows.map((window) => window.usedPercent), [0, 125]);
assert.deepEqual(legacyClaude.windows.map((window) => window.windowMinutes), [300, 10080]);
assert.deepEqual(legacyClaude.windows.map((window) => window.resetsAt), [Date.parse("2027-01-15T08:05:00Z") / 1000, 1800000300]);
const structuredClaude = normalizeAnthropicUsagePayload({ limits: [
  { kind: "session", percent: 0, resets_at: "2027-01-15T08:05:00Z" },
  { kind: "weekly_scoped", percent: 125, scope: { model: { display_name: "Sonnet" } }, resets_at: "2027-01-22T08:05:00Z" },
  { kind: "weekly_scoped", percent: 25, scope: { model: { display_name: secret } } },
  { kind: "weekly_scoped", percent: -1, scope: { model: { display_name: "Opus" } } },
] }, 1800000000000);
assert.deepEqual(structuredClaude.windows.map((window) => window.label), ["Five-hour", "Weekly Sonnet", "Quota window", "Weekly Opus"]);
assert.deepEqual(structuredClaude.windows.map((window) => window.usedPercent), [0, 125, 25, null]);
assert.equal(structuredClaude.windows[1].resetsAt, Date.parse("2027-01-22T08:05:00Z") / 1000);
assert.equal(normalizeAnthropicUsagePayload({ limits: [] }, 1800000000000).reason, "no-quota-data");
assert.equal(normalizeAnthropicUsagePayload({ five_hour: { utilization: "0", resets_at: 1800000300000 } }, 1800000000000).windows[0].status, "unknown");
safe(structuredClaude);
const allClaudeLimits = normalizeAnthropicUsagePayload({ limits: Array.from({ length: 8 }, (_, index) => ({
  kind: "weekly_scoped", percent: index, scope: { model: { display_name: "Sonnet impostor" } },
})) }, 1800000000000);
assert.equal(allClaudeLimits.windows.length, 8, "no silent limit truncation");
assert(allClaudeLimits.windows.every((window) => window.label === "Quota window"));
assert.equal(normalizeAnthropicUsagePayload({ limits: [], five_hour: { utilization: 0 } }, 1800000000000).status, "fresh");
assert.equal(normalizeAnthropicUsagePayload({ limits: [{ kind: "weekly_all", percent: 0 }] }, 1800000000000).windows[0].label, "Weekly");


const originalFetch = globalThis.fetch;
let anthropicRequests = 0;
try {
  globalThis.fetch = async (url, options) => {
    anthropicRequests++;
    assert.equal(url, "https://api.anthropic.com/api/oauth/usage");
    assert.equal(options.method, "GET");
    assert.equal(options.redirect, "error");
    assert.match(options.headers.Authorization, /^Bearer (?:fixture-token|first-token)$/u);
    return new Response(JSON.stringify({ five_hour: { utilization: 0, resets_at: "2027-01-15T08:05:00Z" } }), { status: 200 });
  };
  const localClaude = await observeAnthropic(anthropicContext(), undefined, 100);
  assert.equal(localClaude.status, "fresh");
  assert.equal(localClaude.reason, "ok");
  assert.equal(localClaude.windows[0].usedPercent, 0);
  assert.equal(anthropicRequests, 1);
  safe(localClaude);

  for (const context of [
    anthropicContext({ providerBaseUrl: "https://proxy.example" }),
    anthropicContext({ modelBaseUrl: "https://proxy.example" }),
    anthropicContext({ providerAuthBaseUrl: "https://proxy.example" }),
    anthropicContext({ modelAuthBaseUrl: "https://proxy.example" }),
    anthropicContext({ source: "ANTHROPIC_API_KEY" }),
    anthropicContext({ isUsingOAuth: () => false }),
    anthropicContext({ getProviderAuth: async () => undefined }),
    anthropicContext({ getApiKeyAndHeaders: async () => ({ ok: true, apiKey: "fixture-token", headers: { Authorization: null } }) }),
    anthropicContext({ getApiKeyAndHeaders: async () => ({ ok: true, apiKey: "fixture-token", headers: { Authorization: "" } }) }),
  ]) {
    const before = anthropicRequests;
    const rejected = await observeAnthropic(context, undefined, 100);
    assert.notEqual(rejected.reason, "ok");
    assert.equal(anthropicRequests, before, "auth/origin failures must not query Anthropic");
    safe(rejected);
  }
  const crossProviderClaude = await observeAnthropic(anthropicContext({ selected: false }), undefined, 100);
  assert.equal(crossProviderClaude.status, "fresh", "configured Claude auth works when another provider is selected");

  let identityReads = 0;
  let currentToken = "first-token";
  const rotatingIdentity = anthropicContext({
    getProviderAuth: async () => {
      currentToken = ++identityReads === 1 ? "first-token" : "rotated-token";
      return { auth: { apiKey: currentToken }, source: "OAuth" };
    },
    getApiKeyAndHeaders: async () => ({ ok: true, apiKey: currentToken }),
  });
  const beforeRotation = anthropicRequests;
  assert.equal((await observeAnthropic(rotatingIdentity, undefined, 100)).reason, "identity-changed");
  assert.equal(anthropicRequests, beforeRotation + 1);

  for (const status of [302, 401]) {
    globalThis.fetch = async (_url, options) => {
      assert.equal(options.redirect, "error");
      return new Response(secret, { status, headers: status === 302 ? { Location: "https://evil.example" } : {} });
    };
    const failed = await observeAnthropic(anthropicContext(), undefined, 100);
    assert.equal(failed.reason, "query-failed");
    safe(failed);
  }
  globalThis.fetch = async () => new Response(new Uint8Array(64 * 1024 + 1), { status: 200 });
  const oversized = await observeAnthropic(anthropicContext(), undefined, 100);
  assert.equal(oversized.reason, "query-failed");
  safe(oversized);

  globalThis.fetch = (_url, options) => new Promise(() => { globalThis.anthropicPendingSignal = options.signal; });
  const timedClaude = await observeAnthropic(anthropicContext(), undefined, 15);
  assert.equal(timedClaude.reason, "timeout");
  assert.equal(globalThis.anthropicPendingSignal.aborted, true);
  const cancelledClaudeController = new AbortController();
  const cancelledClaudePromise = observeAnthropic(anthropicContext(), cancelledClaudeController.signal, 100);
  await new Promise((done) => setTimeout(done, 1));
  cancelledClaudeController.abort();
  assert.equal((await cancelledClaudePromise).reason, "cancelled");
  assert.equal(globalThis.anthropicPendingSignal.aborted, true);

  let releaseAnthropicAuth;
  const delayedClaude = observeAnthropic(anthropicContext({ getProviderAuth: () => new Promise((resolve) => { releaseAnthropicAuth = () => resolve({ auth: { apiKey: "fixture-token" }, source: "OAuth" }); }) }), undefined, 15);
  assert.equal((await delayedClaude).reason, "timeout");
  releaseAnthropicAuth();
  await new Promise((done) => setTimeout(done, 1));
  assert.equal(anthropicRequests, beforeRotation + 1, "late auth must not start a query after timeout");
} finally {
  globalThis.fetch = originalFetch;
  delete globalThis.anthropicPendingSignal;
}

console.log("PASS: credential-free quota fixtures and local Claude auth/query/normalization (origin, identity, body cap, redirect, deadline, cancellation)");

// Opt-in host integration uses an isolated agent directory, a symlink to the installed helper, fake auth, and mocked HTTP only.
if (process.argv[2] === "--runtime") {
  const host = resolve(process.argv[3]);
  const hostVersion = JSON.parse(await readFile(join(host, "package.json"), "utf8")).version;
  const hostConfig = await import(pathToFileURL(join(host, "dist/config.js")));
  const installedAgentDir = hostConfig.getAgentDir();
  const addonRoot = join(installedAgentDir, "npm", "node_modules", "@narumitw", "pi-usage");
  const addonManifest = JSON.parse(await readFile(join(addonRoot, "package.json"), "utf8"));
  assert.deepEqual({ name: addonManifest.name, version: addonManifest.version }, { name: "@narumitw/pi-usage", version: "0.64.1" });
  const workspace = await mkdtemp(join(tmpdir(), "pi-quota-status-test-"));
  const originalFetch = globalThis.fetch;
  const originalAgentDir = process.env.PI_CODING_AGENT_DIR;
  const agentDir = join(workspace, "agent");
  const helperPath = join(agentDir, "npm", "node_modules", "@narumitw", "pi-usage");
  console.log(`TEMP owner=quota-test path=${workspace}`);
  process.env.PI_CODING_AGENT_DIR = agentDir;
  try {
    assert.equal(hostConfig.getAgentDir(), agentDir, "all test auth paths must stay inside the disposable agent directory");
    const { discoverAndLoadExtensions, loadExtensions } = await import(pathToFileURL(join(host, "dist/core/extensions/loader.js")));
    const folder = join(agentDir, "extensions", "quota-status");
    await mkdir(join(workspace, "project"), { recursive: true });
    await cp(source, folder, { recursive: true });
    const load = () => discoverAndLoadExtensions([], join(workspace, "project"), agentDir);
    const loaded = await load();
    assert.deepEqual(loaded.errors, []);
    assert.equal(loaded.extensions.length, 1);
    assert.equal(loaded.extensions[0].tools.size, 1);
    assert.equal(loaded.extensions[0].commands.size, 0, "the usage addon's default factory must not be invoked");
    const tool = loaded.extensions[0].tools.get("quota_status").definition;
    const emptyContext = { modelRegistry: {
      getAvailable: () => [], getAll: () => [], getProvider: () => undefined,
      getProviderAuth: async () => undefined, getApiKeyAndHeaders: async () => ({ ok: false, error: secret }), isUsingOAuth: () => false,
    } };
    const checkUnavailable = (result, expectedExternal) => {
      assert.deepEqual(result.structuredContent.providers.map((provider) => provider.reason), [expectedExternal, "auth-unavailable", expectedExternal, expectedExternal, "unsupported"]);
      assert.deepEqual(JSON.parse(result.content[0].text), result.details);
      safe(result.details);
    };

    globalThis.fetch = () => { throw new Error("Unmocked provider network forbidden"); };
    const missing = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    checkUnavailable(missing, "dependency-unavailable");

    const claudeMock = async (url, options) => {
      assert.equal(url, "https://api.anthropic.com/api/oauth/usage");
      assert.equal(options.method, "GET");
      assert.equal(options.redirect, "error");
      assert.equal(options.headers.Authorization, "Bearer fixture-token");
      return new Response(JSON.stringify({ limits: [{ kind: "session", percent: 0, resets_at: "2027-01-15T08:05:00Z" }] }), { status: 200 });
    };
    globalThis.fetch = claudeMock;
    const missingClaude = await tool.execute("fixture", {}, undefined, undefined, anthropicContext());
    assert.deepEqual(missingClaude.structuredContent.providers.map((provider) => provider.reason), ["dependency-unavailable", "ok", "dependency-unavailable", "dependency-unavailable", "unsupported"]);
    assert.equal(missingClaude.structuredContent.providers[1].windows[0].usedPercent, 0);
    safe(missingClaude.details);

    await mkdir(join(agentDir, "npm", "node_modules", "@narumitw", "pi-usage"), { recursive: true });
    await writeFile(join(helperPath, "package.json"), JSON.stringify({ name: "@narumitw/pi-usage", version: "0.64.0" }));
    globalThis.fetch = () => { throw new Error("Only local Claude mock is allowed"); };
    const wrongVersion = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    checkUnavailable(wrongVersion, "dependency-unavailable");
    globalThis.fetch = claudeMock;
    const wrongVersionClaude = await tool.execute("fixture", {}, undefined, undefined, anthropicContext());
    assert.equal(wrongVersionClaude.structuredContent.providers[1].reason, "ok", "Claude stays independent of the optional helper version");

    await rm(helperPath, { recursive: true, force: true });
    await mkdir(join(agentDir, "npm", "node_modules", "@narumitw"), { recursive: true });
    await symlink(addonRoot, helperPath, "dir");
    globalThis.fetch = () => { throw new Error("Empty auth fixture must not make a request"); };
    const installed = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    assert.deepEqual(installed.structuredContent.providers.map((provider) => provider.reason), ["auth-unavailable", "auth-unavailable", "auth-unavailable", "auth-unavailable", "unsupported"], "the installed 0.64.1 helper loaded successfully");
    assert.deepEqual(installed.details, installed.structuredContent);

    const runtimeCancelled = new AbortController();
    runtimeCancelled.abort();
    const cancelled = await tool.execute("fixture", {}, undefined, undefined, { ...emptyContext, signal: runtimeCancelled.signal });
    assert.deepEqual(cancelled.structuredContent.providers.map((provider) => provider.reason), ["cancelled", "cancelled", "cancelled", "cancelled", "unsupported"]);

    const nativeToken = `fixture.${Buffer.from(JSON.stringify({ sub: "fixture-native-user" })).toString("base64url")}.signature`;
    const companionAccountId = "fixture-companion-account";
    const companionToken = `fixture.${Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: companionAccountId } })).toString("base64url")}.signature`;
    const nativeModel = { provider: "openai", id: "fixture-model", baseUrl: "https://api.openai.com/v1" };
    const companionModel = { provider: "openai-codex", id: "fixture-companion-auth", baseUrl: "https://chatgpt.com/backend-api/codex" };
    const nativeCredential = { type: "oauth", access: nativeToken, refresh: "fixture-native-refresh", expires: 1800000000000, clientId: "fixture-native-client", scopes: ["chatgpt.tokens.use.direct"] };
    const companionCredential = (accountId = companionAccountId) => ({ type: "oauth", access: companionToken, refresh: "fixture-companion-refresh", expires: 1800000000000, accountId });
    const writeFixtureAuth = (withCompanion = true, companionId = companionAccountId) => writeFile(join(agentDir, "auth.json"), JSON.stringify({
      openai: nativeCredential,
      ...(withCompanion ? { "openai-codex": companionCredential(companionId) } : {}),
    }));
    let nativeAuthReads = 0;
    let companionAuthReads = 0;
    const nativeContext = (withCompanion = true) => {
      const models = withCompanion ? [nativeModel, companionModel] : [nativeModel];
      return { model: nativeModel, modelRegistry: {
        getAvailable: () => models, getAll: () => models,
        getProvider: (id) => id === "openai" ? { id, baseUrl: nativeModel.baseUrl } : id === "openai-codex" ? { id, baseUrl: "https://chatgpt.com" } : undefined,
        getProviderAuth: async (id) => {
          if (id === "openai") { nativeAuthReads++; return { auth: { apiKey: nativeToken }, source: "OAuth" }; }
          if (id === "openai-codex" && withCompanion) { companionAuthReads++; return { auth: { apiKey: companionToken }, source: "OAuth" }; }
          return undefined;
        },
        getApiKeyAndHeaders: async (model) => ({ ok: true, apiKey: model.provider === "openai" ? nativeToken : companionToken }),
        isUsingOAuth: () => true,
      } };
    };
    await writeFixtureAuth();
    let nativeHttpLookups = 0;
    globalThis.fetch = async (url, options) => {
      nativeHttpLookups++;
      assert.equal(options.method, "GET");
      assert.equal(options.redirect, "error");
      assert.equal(options.headers.Authorization, `Bearer ${companionToken}`, "only the telemetry companion may authorize usage requests");
      assert.notEqual(options.headers.Authorization, `Bearer ${nativeToken}`, "native OpenAI inference auth is never sent to companion telemetry");
      if (url === "https://chatgpt.com/backend-api/wham/usage/chatpass/apps") {
        return new Response(JSON.stringify({ items: [{ id: "fixture-native-client", allowed_usage_percent: 85, windows: [
          { used_percent: 40, remaining_percent: 60, limit_window_seconds: 604800, reset_at: 1800000300 },
        ] }] }), { status: 200 });
      }
      assert.equal(url, "https://chatgpt.com/backend-api/wham/usage");
      return new Response(JSON.stringify({ rate_limit: {
        primary_window: { used_percent: 0, remaining_percent: 100, limit_window_seconds: 18000, reset_at: 1800000300 },
        secondary_window: { used_percent: 27, remaining_percent: 73, limit_window_seconds: 604800, reset_at: 1800000300 },
      } }), { status: 200 });
    };
    const nativeResult = await tool.execute("fixture", {}, undefined, undefined, nativeContext());
    assert.deepEqual(nativeResult.structuredContent.providers.map((provider) => provider.reason), ["ok", "auth-unavailable", "auth-unavailable", "auth-unavailable", "unsupported"]);
    assert.equal(nativeHttpLookups, 2, "native numerical reporting uses the installed companion adapter's two guarded requests");
    assert(nativeAuthReads >= 6 && companionAuthReads >= 6, "combined native/companion identity is re-resolved before both requests and publication");
    assert.equal(nativeResult.structuredContent.providers[0].source, "openai-chatgpt-companion-experimental");
    assert.deepEqual(nativeResult.structuredContent.providers[0].windows.map(({ label, group }) => [label, group]), [
      ["ChatGPT plan", "ChatGPT plan"], ["ChatGPT plan", "ChatGPT plan"], ["ChatGPT app", "ChatGPT app"],
    ]);
    assert.equal(nativeResult.structuredContent.providers[0].windows[0].usedPercent, 0);
    assert.equal(nativeResult.structuredContent.providers[0].windows[2].usedPercent, 40);
    assert(!JSON.stringify(nativeResult).includes("App allowance"));
    assert(!JSON.stringify(nativeResult).includes(nativeToken));
    assert(!JSON.stringify(nativeResult).includes(companionToken));
    assert.deepEqual(JSON.parse(nativeResult.content[0].text), nativeResult.details);
    safe(nativeResult.details);
    console.log(`FIXTURE quota_status result (mocked, not live): ${JSON.stringify(nativeResult.structuredContent)}`);

    const requestsBeforeMissing = nativeHttpLookups;
    await writeFixtureAuth(false);
    const missingCompanionRuntime = await tool.execute("fixture", {}, undefined, undefined, nativeContext(false));
    const missingNative = missingCompanionRuntime.structuredContent.providers[0];
    assert.deepEqual({ source: missingNative.source, status: missingNative.status, reason: missingNative.reason, windows: missingNative.windows }, {
      source: "openai-chatgpt-auth", status: "unknown", reason: "no-quota-data", windows: [],
    });
    assert.equal(nativeHttpLookups, requestsBeforeMissing, "auth-only output must not trigger companion quota requests");
    safe(missingCompanionRuntime.details);

    await writeFixtureAuth(true, "fixture-mismatched-account");
    const mismatchedCompanionRuntime = await tool.execute("fixture", {}, undefined, undefined, nativeContext());
    assert.equal(mismatchedCompanionRuntime.structuredContent.providers[0].reason, "auth-failed");
    assert.equal(nativeHttpLookups, requestsBeforeMissing, "a mismatched companion is rejected before HTTP");
    safe(mismatchedCompanionRuntime.details);

    const hostRequire = createRequire(join(host, "package.json"));
    const { Check } = await import(pathToFileURL(hostRequire.resolve("typebox/value")));
    assert(Check(tool.outputSchema, installed.structuredContent));
    assert(Check(tool.outputSchema, missingClaude.structuredContent));
    assert(Check(tool.outputSchema, nativeResult.structuredContent));
    assert(Check(tool.outputSchema, missingCompanionRuntime.structuredContent));
    assert(Check(tool.outputSchema, mismatchedCompanionRuntime.structuredContent));
    assert(Check(tool.parameters, {}));
    assert(!Check(tool.parameters, { forceRefresh: true }));

    const probe = join(agentDir, "extensions", "quota-status", "probe.ts");
    await writeFile(probe, `
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
export default function(pi) {
  pi.registerTool({ name: "fixture_probe", label: "fixture", description: "fixture", parameters: { type: "object", properties: {} }, async execute() {
    const addon = await import(pathToFileURL(join(getAgentDir(), "npm", "node_modules", "@narumitw", "pi-usage", "dist", "index.ts")).href);
    const salt = new Uint8Array(32);
    const copilotModel = { provider: "github-copilot", id: "fixture", baseUrl: "https://api.individual.githubcopilot.com" };
    const copilotContext = { modelRegistry: { getAvailable: () => [copilotModel], getAll: () => [copilotModel], getProviderAuth: async () => ({ auth: { apiKey: "runtime-token" }, source: "OAuth" }) } };
    const stored = () => ({ type: "oauth", access: "runtime-token", refresh: "original-github-token", expires: 1800000000000 });
    const copilotAdapter = addon.adapterForProvider("github-copilot");
    const copilotAuth = await addon.resolveUsageAuth(copilotContext, copilotAdapter, salt, stored);
    const copilot = await addon.queryProviderUsage(copilotAdapter, copilotAuth, new AbortController().signal, 100);
    const rejected = [];
    for (const [context, reader] of [
      [copilotContext, () => ({ ...stored(), access: "other-account" })],
      [copilotContext, () => ({ ...stored(), enterpriseUrl: "private.example" })],
      [{ ...copilotContext, model: { ...copilotModel, baseUrl: "https://proxy.example" } }, stored],
      [{ ...copilotContext, modelRegistry: { ...copilotContext.modelRegistry, getProviderAuth: async () => ({ auth: { apiKey: "runtime-token", baseUrl: "https://proxy.example" }, source: "OAuth" }) } }, stored],
    ]) {
      try { await addon.resolveUsageAuth(context, copilotAdapter, salt, reader); rejected.push(false); }
      catch { rejected.push(true); }
    }
    const goModel = { provider: "opencode-go", id: "fixture", baseUrl: "https://opencode.ai/zen/go/v1" };
    const goContext = { modelRegistry: { getAvailable: () => [goModel], getAll: () => [goModel], getProviderAuth: async () => ({ auth: { apiKey: "go-fixture-token" } }) } };
    const goAdapter = addon.adapterForProvider("opencode-go");
    const goAuth = await addon.resolveUsageAuth(goContext, goAdapter, salt, () => { throw new Error("Go must not read stored auth"); });
    const go = await addon.queryProviderUsage(goAdapter, goAuth, new AbortController().signal, 100);
    try { await addon.resolveUsageAuth({ ...goContext, model: { ...goModel, baseUrl: "https://proxy.example" } }, goAdapter); rejected.push(false); }
    catch { rejected.push(true); }
    const payloads = [
      { quota_snapshots: { premium_interactions: { token_based_billing: true, credits_used: 30, entitlement: 100, remaining: 70 } } },
      { quota_snapshots: { premium_interactions: { entitlement: 300, quota_remaining: 250 } } },
      { limited_user_quotas: { chat: 40 }, monthly_quotas: { chat: 50 } },
      { quota_snapshots: { premium_interactions: { unlimited: true } } },
      { quota_snapshots: { premium_interactions: { entitlement: 0, remaining: 0 } } },
      { quota_snapshots: { premium_interactions: { entitlement: 100, remaining: -25, overage_count: 25 } } },
    ];
    const variants = payloads.map((payload) => addon.normalizeGitHubCopilotUsagePayload({ ...payload, login: "${secret}", copilot_plan: "${secret}", quota_reset_date_utc: "2027-01-15T08:05:00Z" }, 1800000000000));
    const noGoQuota = (() => { try { addon.normalizeOpenCodeZenPayload({ usage: {} }, 1800000000000); return false; } catch { return true; } })();
    return { content: [], details: {
      namedExports: [addon.adapterForProvider, addon.resolveUsageAuth, addon.queryProviderUsage].map((value) => typeof value),
      providers: ["github-copilot", "opencode-go"].map((id) => addon.adapterForProvider(id)?.id ?? null),
      copilot, go, variants, rejected, noGoQuota,
    } };
  } });
}
`);
    let helperHttpLookups = 0;
    globalThis.fetch = async (url, options) => {
      helperHttpLookups++;
      if (url === "https://api.github.com/copilot_internal/user") {
        assert.equal(options.headers.Authorization, "Bearer original-github-token", "original OAuth, never runtime token");
        return new Response(JSON.stringify({ quota_snapshots: { premium_interactions: { token_based_billing: true, entitlement: 100, remaining: 0, credits_used: 125 } }, login: secret }), { status: 200 });
      }
      assert.equal(url, "https://opencode.ai/zen/go/v1/usage", "Go usage only, never Zen balance");
      assert.equal(options.headers.Authorization, "Bearer go-fixture-token");
      return new Response(JSON.stringify({ usage: { rolling: { status: "ok", percent: 0, resetsAt: "2027-01-15T08:05:00Z" }, weekly: { status: "rate-limited", percent: 125 }, monthly: { status: "ok", percent: 50 }, unknown: { status: secret, percent: 10 } } }), { status: 200 });
    };
    const probeLoaded = await loadExtensions([probe], workspace);
    assert.deepEqual(probeLoaded.errors, []);
    const actual = (await probeLoaded.extensions[0].tools.get("fixture_probe").definition.execute()).details;
    assert.deepEqual(actual.namedExports, ["function", "function", "function"]);
    assert.deepEqual(actual.providers, ["github-copilot", "opencode-go"]);
    assert.equal(actual.copilot.buckets[0].used, 125);
    assert.equal(actual.go.buckets[0].used, 0);
    assert.deepEqual(actual.rejected, [true, true, true, true, true]);
    assert(actual.noGoQuota);
    assert.equal(helperHttpLookups, 2);
    const copilot = sanitize("github-copilot", actual.copilot);
    const go = sanitize("opencode-go", actual.go);
    assert.equal(copilot.windows[0].usedFraction, 1.25);
    assert.equal(copilot.windows[0].group, null);
    assert.deepEqual(go.windows.map((window) => window.label), ["Rolling window", "Weekly window", "Monthly window"]);
    assert.deepEqual(go.windows.map((window) => window.usedPercent), [0, 125, 50]);
    assert.equal(go.windows[0].resetsAt, Date.parse("2027-01-15T08:05:00Z") / 1000);
    const variants = actual.variants.map((value) => sanitize("github-copilot", value));
    assert.deepEqual(variants.map((value) => value.windows[0].used), [30, 50, 10, null, 0, 125]);
    assert.deepEqual(variants.map((value) => value.windows[0].limit), [100, 300, 50, null, 0, 100]);
    const runtimeSnapshot = { providers: [nativeResult.structuredContent.providers[0], missingClaude.structuredContent.providers[1], copilot, go, sanitize("opencode", report)] };
    assert(Check(tool.outputSchema, nativeResult.structuredContent));
    assert(Check(tool.outputSchema, runtimeSnapshot));
    safe(nativeResult.details);
    safe(runtimeSnapshot);
    safe(variants);
    console.log(`PASS: Pi ${hostVersion} discovery/Jiti, installed @narumitw/pi-usage@0.64.1 helper imports/auth/query with fake auth and mocked HTTP; missing/wrong helper leaves local Claude independent`);
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.quotaHelperLookups;
    if (originalAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = originalAgentDir;
    await rm(workspace, { recursive: true, force: true });
    await assert.rejects(access(workspace), { code: "ENOENT" });
    console.log(`CLEANED owner=quota-test path=${workspace}`);
  }
}
