#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtemp, cp, mkdir, rm, writeFile, readFile, access, symlink, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import { observe, sanitize, PROVIDERS } from "../home/private_dot_pi/private_agent/private_extensions/quota-status/quota.ts";
import { normalizeAnthropicUsagePayload, observeAnthropic } from "../home/private_dot_pi/private_agent/private_extensions/quota-status/anthropic.ts";

import { observeAnthropicApi, parseCodexbarUsage } from "../home/private_dot_pi/private_agent/private_extensions/quota-status/api.ts";
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
assert.deepEqual(PROVIDERS, ["openai", "anthropic", "anthropic-api", "github-copilot", "opencode-go", "opencode"]);
// anthropic-api uses the CodexBar Console collector, never the shared subscription helper.
const observed = PROVIDERS.filter((provider) => provider !== "anthropic-api");
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
const mixed = await Promise.all(observed.map((provider) => observe(provider, helpers({ queryProviderUsage: async (adapter) => {
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
const prepaid = (bucket) => sanitize("anthropic-api", { ...report, buckets: [{ id: "prepaid", label: "Pi-local cumulative estimate (USD)", ...bucket }] }).windows[0];
assert.deepEqual(
  [prepaid({ unit: "count", used: 57.56 }), prepaid({ unit: "percent", used: 100 }), prepaid({ unit: "count", used: 5, limit: 0 })].map(({ unit, used, limit, usedPercent, usedFraction }) => [unit, used, limit, usedPercent, usedFraction]),
  [["count", 57.56, null, null, null], [null, null, null, null, null], ["count", 5, 0, null, null]],
  "anthropic-api spend is a count with unknown limit; percent exhaustion is rejected",
);
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
const mixedGoFailure = await Promise.all(observed.map((provider) => observe(provider, helpers({ queryProviderUsage: async (adapter) => {
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
    assert.equal(failed.reason, status === 401 ? "auth-expired" : "query-failed");
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

// CodexBar Console fixtures: all command output is mocked; no CLI, network, or credential access.
const apiNow = Date.parse("2026-10-20T08:23:05Z");
const apiLedger = async () => ({ spentUsd: 57.56, exhausted: true });
const observedSectionPayload = [{
  usage: {
    tertiary: null,
    secondary: null,
    providerCost: { used: 851.79, period: "<REDACTED>", balance: 851.79 },
    details: [
      { rows: [{ label: "API credit", secondaryValue: "Expires Apr 8, 2027 (UTC)", progress: { used: 0.14822 }, value: "$851.78 of $1,000.00 left" }], title: "Other credit grants" },
      { rows: [{ label: "This month (UTC)", value: "$868.21" }], title: "Billing" },
    ],
    primary: null,
  },
  provider: "claudeplatform",
}];
const observedSection = parseCodexbarUsage(JSON.stringify(observedSectionPayload), apiNow);
assert.equal(observedSection.status, "fresh");
assert.deepEqual(observedSection.console, {
  totalBalanceUsd: 851.79,
  grants: [{ label: "Prepaid grant", grantUsd: 1000, remainingUsd: 851.78, expiresAt: "2027-04-08" }],
  monthSpendUsd: 868.21,
});
const apiEntry = (balance, rows, lanes = {}) => [{
  provider: "claudeplatform", account: secret,
  usage: {
    providerCost: { balance, organizationId: secret },
    details: [
      { title: "Other credit grants", rows: rows.filter((row) => row.label !== "This month (UTC)" && row.label !== "Spend") },
      { title: "Billing", rows: rows.filter((row) => row.label === "This month (UTC)" || row.label === "Spend") },
    ],
    primary: lanes.primary ?? null,
    secondary: lanes.secondary ?? null,
  },
  organization: secret,
}];
const laneObserved = parseCodexbarUsage(JSON.stringify(apiEntry(851.79, [
  { label: "API credit", value: "$30.00 of $50.00 left", secondaryValue: "Expires Apr 8, 2027 (UTC)" },
  { label: "This month (UTC)", value: "$868.21" },
], {
  primary: { resetDescription: "$30.00 of $50.00 left · Expires Apr 8, 2027 (UTC)" },
  secondary: { resetDescription: "$5.00 of $20.00 left · Expires Oct 21 (UTC)" },
})), apiNow);
assert.deepEqual(laneObserved.console, {
  totalBalanceUsd: 851.79,
  grants: [
    { label: "Prepaid grant", grantUsd: 50, remainingUsd: 30, expiresAt: "2027-04-08" },
    { label: "Prepaid grant", grantUsd: 20, remainingUsd: 5, expiresAt: "2026-10-21" },
    { label: "Prepaid grant", grantUsd: 50, remainingUsd: 30, expiresAt: "2027-04-08" },
  ],
  monthSpendUsd: 868.21,
}, "primary/secondary lanes and the disjoint Other grants section are all retained without summing or speculative deduplication");
const unavailableSpend = parseCodexbarUsage(JSON.stringify(apiEntry(44.25, [{ label: "Spend", value: "Unavailable" }])), apiNow);
assert.equal(unavailableSpend.status, "fresh", "known balance remains available when Billing spend is unavailable");
assert.equal(unavailableSpend.console.totalBalanceUsd, 44.25);
assert.equal(unavailableSpend.console.monthSpendUsd, null);
const apiPayload = apiEntry(857.32, [
  { label: "Purchased credit", value: "$857.31 of $1,000.00 left", secondaryValue: "Expires Apr 8, 2027 (UTC)", organizationId: secret },
  { label: "Purchased credit", value: "$0.00 of $360.00 left", secondaryValue: "Expires Unknown", account: secret },
  { label: "This month (UTC)", value: "$751.47", secondaryValue: secret },
  { label: secret, value: secret, secondaryValue: secret },
]);
const apiRunner = (payload = apiPayload) => async (file, args, options) => {
  assert.equal(file, "codexbar");
  assert.deepEqual(args, ["usage", "--provider", "claudeplatform", "--source", "web", "--json"]);
  assert.equal(options.encoding, "utf8");
  assert.equal(options.maxBuffer, 64 * 1024);
  assert(options.signal instanceof AbortSignal);
  return { stdout: typeof payload === "string" ? payload : JSON.stringify(payload), stderr: secret };
};
const liveApi = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, apiRunner());
assert.equal(liveApi.source, "codexbar-console-web");
assert.equal(liveApi.status, "fresh");
assert.equal(liveApi.capturedAt, apiNow);
assert.deepEqual(liveApi.windows, [], "Console balances are typed telemetry, not percent quota windows");
assert.deepEqual(liveApi.console, {
  totalBalanceUsd: 857.32,
  grants: [
    { label: "Prepaid grant", grantUsd: 1000, remainingUsd: 857.31, expiresAt: "2027-04-08" },
    { label: "Prepaid grant", grantUsd: 360, remainingUsd: 0, expiresAt: null },
  ],
  monthSpendUsd: 751.47,
});
assert.deepEqual(liveApi.piLocalRefusal, { source: "pi-local-exhausted-refusal", status: "observed" }, "Pi refusal evidence is separate from the live Console balance");
safe(liveApi);
assert(!JSON.stringify(liveApi).includes("857.32 of"), "total balance is not reconstructed from grants");

const zeroPayload = apiEntry(0, [{ label: "This month (UTC)", value: "$0.00" }]);
const zeroApi = await observeAnthropicApi(async () => ({ spentUsd: 0, exhausted: false }), undefined, 100, () => apiNow, apiRunner(zeroPayload));
assert.equal(zeroApi.status, "fresh");
assert.equal(zeroApi.console.totalBalanceUsd, 0, "an explicit numeric zero is valid");
assert.deepEqual(zeroApi.console.grants, []);
assert.equal(zeroApi.console.monthSpendUsd, 0, "an explicit formatted USD zero is valid");
assert.equal(zeroApi.piLocalRefusal, undefined, "absence of refusal evidence is not reported as a balance or an exhaustion marker");

const noGrants = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, apiRunner(apiEntry(12.34, [{ label: "This month (UTC)", value: "$1.00" }])));
assert.equal(noGrants.console.totalBalanceUsd, 12.34);
assert.deepEqual(noGrants.console.grants, [], "missing grant rows are not inferred from the balance");
const absentExpiry = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, apiRunner(apiEntry(1, [
  { label: "Purchased credit", value: "$1.00 of $2.00 left" },
  { label: "This month (UTC)", value: "$0.00" },
])));
assert.equal(absentExpiry.console.grants[0].expiresAt, null, "an omitted expiry stays unknown");

const malformedPayloads = [
  "not JSON",
  JSON.stringify({ unexpected: secret }),
  JSON.stringify({ providers: [] }),
  JSON.stringify([]),
  JSON.stringify([...apiPayload, ...apiPayload]),
  JSON.stringify(apiEntry("857.32", [])),
  JSON.stringify(apiEntry(1.234, [])),
  JSON.stringify(apiEntry(1, [{ label: "Spend", value: "Unavailable" }, { label: "This month (UTC)", value: "$1.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "This month (UTC)", value: "EUR 1.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "This month (UTC)", value: "$1,00.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "This month (UTC)", value: "$1.001" }])),
  JSON.stringify(apiEntry(1, [{ label: "This month (UTC)", value: "$1.00" }, { label: "This month (UTC)", value: "$1.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "Purchased credit", value: "$2.00 of $1.00 left", secondaryValue: "Expires Apr 8, 2027 (UTC)" }, { label: "This month (UTC)", value: "$1.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "Purchased credit", value: "$1.00 of $1.00 left", secondaryValue: "Expires Feb 30, 2027 (UTC)" }, { label: "This month (UTC)", value: "$1.00" }])),
  JSON.stringify(apiEntry(1, [{ label: "Purchased credit", value: "$1.00 of $1.00 left", secondaryValue: "next month" }, { label: "This month (UTC)", value: "$1.00" }])),
];
for (const payload of malformedPayloads) {
  const failed = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, apiRunner(payload));
  assert.equal(failed.status, "unavailable");
  assert.equal(failed.reason, "query-failed");
  assert.equal(failed.source, null);
  assert.equal(failed.console, undefined, "malformed or unknown data never becomes zero or stale balance");
  safe(failed);
}

const missingExecutable = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, async () => { throw Object.assign(new Error(secret), { code: "ENOENT", stderr: secret }); });
assert.equal(missingExecutable.reason, "dependency-unavailable");
assert.deepEqual(missingExecutable.piLocalRefusal, { source: "pi-local-exhausted-refusal", status: "observed" });
safe(missingExecutable);
for (const error of [Object.assign(new Error(secret), { code: 1, stderr: secret }), Object.assign(new Error(secret), { code: "EACCES", stderr: secret })]) {
  const failed = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, async () => { throw error; });
  assert.equal(failed.reason, "query-failed");
  safe(failed);
}
const oversized = await observeAnthropicApi(apiLedger, undefined, 100, () => apiNow, async () => ({ stdout: "x".repeat(64 * 1024 + 1), stderr: secret }));
assert.equal(oversized.reason, "query-failed");
safe(oversized);

const apiCancelController = new AbortController();
let commandCancelled = false;
const pendingRunner = (_file, _args, options) => new Promise((_resolve, reject) => {
  options.signal.addEventListener("abort", () => { commandCancelled = true; reject(new Error(secret)); }, { once: true });
});
const cancelledApi = observeAnthropicApi(apiLedger, apiCancelController.signal, 100, () => apiNow, pendingRunner);
await new Promise((done) => setTimeout(done, 1));
apiCancelController.abort();
assert.equal((await cancelledApi).reason, "cancelled");
assert(commandCancelled, "external cancellation reaches the child-process signal");
const keepAlive = setTimeout(() => {}, 100);
try {
  const timedOut = await observeAnthropicApi(apiLedger, undefined, 10, () => apiNow, pendingRunner);
  assert.equal(timedOut.reason, "timeout");
  safe(timedOut);
} finally { clearTimeout(keepAlive); }
const apiCostFixture = liveApi;
const apiUnknownSpendFixture = unavailableSpend;
console.log("PASS: CodexBar Console fixtures (sections, lanes, UTC expiry, nullable spend, fixed argv, privacy, missing executable, timeout, cancellation)");

console.log("PASS: credential-free quota fixtures and local Claude auth/query/normalization (origin, identity, body cap, redirect, deadline, cancellation)");

// Opt-in host integration uses an isolated agent directory, a symlink to the installed helper, fake auth, and mocked HTTP only.
if (process.argv[2] === "--runtime") {
  const host = resolve(process.argv[3]);
  const hostVersion = JSON.parse(await readFile(join(host, "package.json"), "utf8")).version;
  const hostConfig = await import(pathToFileURL(join(host, "dist/config.js")));
  const installedAgentDir = hostConfig.getAgentDir();
  const addonRoot = join(installedAgentDir, "npm", "node_modules", "@narumitw", "pi-usage");
  const addonManifest = JSON.parse(await readFile(join(addonRoot, "package.json"), "utf8"));
  assert.deepEqual({ name: addonManifest.name, version: addonManifest.version }, { name: "@narumitw/pi-usage", version: "0.66.0" });
  const workspace = await mkdtemp(join(tmpdir(), "pi-quota-status-test-"));
  const originalFetch = globalThis.fetch;
  const originalAgentDir = process.env.PI_CODING_AGENT_DIR;
  const originalPath = process.env.PATH;
  const agentDir = join(workspace, "agent");
  const helperPath = join(agentDir, "npm", "node_modules", "@narumitw", "pi-usage");
  console.log(`TEMP owner=quota-test path=${workspace}`);
  process.env.PI_CODING_AGENT_DIR = agentDir;
  process.env.PATH = join(workspace, "empty-bin");
  try {
    assert.equal(hostConfig.getAgentDir(), agentDir, "all test auth paths must stay inside the disposable agent directory");
    await mkdir(process.env.PATH, { recursive: true });
    const { discoverAndLoadExtensions, loadExtensions } = await import(pathToFileURL(join(host, "dist/core/extensions/loader.js")));
    const folder = join(agentDir, "extensions", "quota-status");
    await mkdir(join(workspace, "project"), { recursive: true });
    await cp(source, folder, { recursive: true });
    // index.ts imports the sibling ledger reader, so deploy it as chezmoi does (it is a separate extension too).
    await cp(join(source, "..", "anthropic-api.ts"), join(agentDir, "extensions", "anthropic-api.ts"));
    const load = () => discoverAndLoadExtensions([], join(workspace, "project"), agentDir);
    const loaded = await load();
    assert.deepEqual(loaded.errors, []);
    assert.equal(loaded.extensions.length, 2);
    const quotaExtension = loaded.extensions.find((extension) => extension.tools.has("quota_status"));
    assert.equal(quotaExtension.tools.size, 1);
    assert.equal(quotaExtension.commands.size, 0, "the usage addon's default factory must not be invoked");
    const tool = quotaExtension.tools.get("quota_status").definition;
    const emptyContext = { modelRegistry: {
      getAvailable: () => [], getAll: () => [], getProvider: () => undefined,
      getProviderAuth: async () => undefined, getApiKeyAndHeaders: async () => ({ ok: false, error: secret }), isUsingOAuth: () => false,
    } };
    const checkUnavailable = (result, expectedExternal) => {
      assert.deepEqual(result.structuredContent.providers.map((provider) => provider.reason), [expectedExternal, "auth-unavailable", "dependency-unavailable", expectedExternal, expectedExternal, "unsupported"]);
      assert.deepEqual(JSON.parse(result.content[0].text), result.details);
      safe(result.details);
    };

    globalThis.fetch = () => { throw new Error("Unmocked provider network forbidden"); };
    const missing = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    checkUnavailable(missing, "dependency-unavailable");

    const fakeCliBin = join(workspace, "fake-codexbar-bin");
    const fakeCli = join(fakeCliBin, "codexbar");
    await mkdir(fakeCliBin);
    await writeFile(fakeCli, `#!/bin/sh
if [ "$#" -ne 6 ] || [ "$1" != "usage" ] || [ "$2" != "--provider" ] || [ "$3" != "claudeplatform" ] || [ "$4" != "--source" ] || [ "$5" != "web" ] || [ "$6" != "--json" ]; then exit 23; fi
printf '%s\\n' '${JSON.stringify(observedSectionPayload)}'
`);
    await chmod(fakeCli, 0o755);
    console.log(`TEMP owner=quota-test path=${fakeCli}`);
    const emptyPath = process.env.PATH;
    try {
      process.env.PATH = fakeCliBin;
      const fakeCliResult = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
      const consoleProvider = fakeCliResult.structuredContent.providers[2];
      assert.equal(consoleProvider.status, "fresh");
      assert.equal(consoleProvider.reason, "ok");
      assert.equal(consoleProvider.console.totalBalanceUsd, 851.79);
      assert.deepEqual(consoleProvider.console.grants, [{ label: "Prepaid grant", grantUsd: 1000, remainingUsd: 851.78, expiresAt: "2027-04-08" }]);
      assert.equal(consoleProvider.console.monthSpendUsd, 868.21);
      safe(fakeCliResult.structuredContent);
    } finally {
      process.env.PATH = emptyPath;
      await rm(fakeCliBin, { recursive: true, force: true });
      await assert.rejects(access(fakeCliBin), { code: "ENOENT" });
      console.log(`CLEANED owner=quota-test path=${fakeCli}`);
    }

    const claudeMock = async (url, options) => {
      assert.equal(url, "https://api.anthropic.com/api/oauth/usage");
      assert.equal(options.method, "GET");
      assert.equal(options.redirect, "error");
      assert.equal(options.headers.Authorization, "Bearer fixture-token");
      return new Response(JSON.stringify({ limits: [{ kind: "session", percent: 0, resets_at: "2027-01-15T08:05:00Z" }] }), { status: 200 });
    };
    globalThis.fetch = claudeMock;
    const missingClaude = await tool.execute("fixture", {}, undefined, undefined, anthropicContext());
    assert.deepEqual(missingClaude.structuredContent.providers.map((provider) => provider.reason), ["dependency-unavailable", "ok", "dependency-unavailable", "dependency-unavailable", "dependency-unavailable", "unsupported"]);
    assert.equal(missingClaude.structuredContent.providers[1].windows[0].usedPercent, 0);
    safe(missingClaude.details);

    // Qualification matrix with fake packages: only the exact 0.66.0 manifest may reach the package's code.
    // Each fake dist records an import on globalThis, so a rejected manifest must leave the counter untouched.
    const fakeDist = (exportNames) => `globalThis.quotaHelperImports = (globalThis.quotaHelperImports ?? 0) + 1;\n${exportNames.map((name) => `export const ${name} = ${name === "adapterForProvider" ? "(id) => ({ id })" : "async () => undefined"};`).join("\n")}\n`;
    const threeExports = ["adapterForProvider", "resolveUsageAuth", "queryProviderUsage"];
    // The module loader caches by path, so every fake package gets its own disposable agent directory.
    let fakeAgents = 0;
    const installFake = async (manifest, exportNames = threeExports) => {
      const fakeRoot = join(workspace, `fake-agent-${++fakeAgents}`, "npm", "node_modules", "@narumitw", "pi-usage");
      process.env.PI_CODING_AGENT_DIR = join(workspace, `fake-agent-${fakeAgents}`);
      await mkdir(join(fakeRoot, "dist"), { recursive: true });
      await writeFile(join(fakeRoot, "package.json"), typeof manifest === "string" ? manifest : JSON.stringify(manifest));
      await writeFile(join(fakeRoot, "dist", "index.ts"), fakeDist(exportNames));
    };
    const helperReasons = (result) => [0, 3, 4].map((index) => result.structuredContent.providers[index].reason);
    for (const manifest of [
      { name: "@narumitw/pi-usage", version: "0.64.3" },
      { name: "@narumitw/pi-usage", version: "0.64.1" },
      { name: "@narumitw/pi-usage", version: "0.65.0" },
      { name: "@narumitw/pi-usage", version: "0.66.1" },
      { name: "@narumitw/pi-usage", version: "0.66.0-beta.1" },
      { name: "@narumitw/pi-usage", version: "0.67.0" },
      { name: "@narumitw/pi-usage", version: "1.0.0" },
      { name: "@narumitw/pi-usage", version: 66 },
      { name: "@narumitw/pi-usage" },
      { name: "@narumitw/pi-usage-fork", version: "0.66.0" },
      { name: "pi-usage", version: "0.66.0" },
      { version: "0.66.0" },
      "not json",
      "[]",
      "null",
    ]) {
      await installFake(manifest);
      globalThis.quotaHelperImports = 0;
      globalThis.fetch = () => { throw new Error("Only local Claude mock is allowed"); };
      const rejected = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
      assert.deepEqual(helperReasons(rejected), ["dependency-unavailable", "dependency-unavailable", "dependency-unavailable"], `unqualified manifest ${JSON.stringify(manifest)}`);
      assert.equal(globalThis.quotaHelperImports, 0, `unqualified manifest ${JSON.stringify(manifest)} must not execute package code`);
      checkUnavailable(rejected, "dependency-unavailable");
    }
    globalThis.fetch = claudeMock;
    const wrongVersionClaude = await tool.execute("fixture", {}, undefined, undefined, anthropicContext());
    assert.equal(wrongVersionClaude.structuredContent.providers[1].reason, "ok", "Claude stays independent of the optional helper version");
    // Exact 0.66.0 manifest but a missing contract function: loaded, then rejected as dependency-unavailable.
    for (const exportNames of [["adapterForProvider", "resolveUsageAuth"], ["adapterForProvider", "queryProviderUsage"], ["resolveUsageAuth", "queryProviderUsage"]]) {
      await installFake({ name: "@narumitw/pi-usage", version: "0.66.0" }, exportNames);
      globalThis.quotaHelperImports = 0;
      globalThis.fetch = () => { throw new Error("Only local Claude mock is allowed"); };
      const incomplete = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
      checkUnavailable(incomplete, "dependency-unavailable");
      assert.equal(globalThis.quotaHelperImports, 1);
    }
    await installFake({ name: "@narumitw/pi-usage", version: "0.66.0" });
    globalThis.quotaHelperImports = 0;
    globalThis.fetch = () => { throw new Error("Only local Claude mock is allowed"); };
    const qualifiedStub = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    assert.deepEqual(helperReasons(qualifiedStub), ["auth-unavailable", "auth-unavailable", "auth-unavailable"], "exact 0.66.0 with all three functions is accepted (stub auth resolves to nothing, so no query is made)");
    assert.equal(globalThis.quotaHelperImports, 1);
    safe(qualifiedStub.details);
    process.env.PI_CODING_AGENT_DIR = agentDir;

    await rm(helperPath, { recursive: true, force: true });
    await mkdir(join(agentDir, "npm", "node_modules", "@narumitw"), { recursive: true });
    await symlink(addonRoot, helperPath, "dir");
    globalThis.fetch = () => { throw new Error("Empty auth fixture must not make a request"); };
    const installed = await tool.execute("fixture", {}, undefined, undefined, emptyContext);
    assert.deepEqual(installed.structuredContent.providers.map((provider) => provider.reason), ["auth-unavailable", "auth-unavailable", "dependency-unavailable", "auth-unavailable", "auth-unavailable", "unsupported"], "the installed 0.66.0 helper loaded successfully; no real CodexBar binary is on the fixture PATH");
    assert.deepEqual(installed.details, installed.structuredContent);

    const runtimeCancelled = new AbortController();
    runtimeCancelled.abort();
    const cancelled = await tool.execute("fixture", {}, undefined, undefined, { ...emptyContext, signal: runtimeCancelled.signal });
    assert.deepEqual(cancelled.structuredContent.providers.map((provider) => provider.reason), ["cancelled", "cancelled", "cancelled", "cancelled", "cancelled", "unsupported"], "all supported collectors respect cancellation");

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
    assert.deepEqual(nativeResult.structuredContent.providers.map((provider) => provider.reason), ["ok", "auth-unavailable", "dependency-unavailable", "auth-unavailable", "auth-unavailable", "unsupported"]);
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

    // Copilot and Go through the real 0.66.0 helper: report shapes, helper error messages that map to no-quota-data, and real fingerprint identity guards.
    const copilotModel = { provider: "github-copilot", id: "fixture-copilot", baseUrl: "https://api.individual.githubcopilot.com" };
    const goModel = { provider: "opencode-go", id: "fixture-go", baseUrl: "https://opencode.ai/zen/go/v1" };
    await writeFile(join(agentDir, "auth.json"), JSON.stringify({ "github-copilot": { type: "oauth", access: "runtime-token", refresh: "original-github-token", expires: 1800000000000 } }));
    const copilotGoContext = ({ goToken = () => "go-token-1", copilotToken = () => "runtime-token", goBaseUrl } = {}) => ({ modelRegistry: {
      getAvailable: () => [copilotModel, goModel], getAll: () => [copilotModel, goModel],
      getProvider: (id) => id === "opencode-go" && goBaseUrl ? { id, baseUrl: goBaseUrl } : undefined,
      getProviderAuth: async (id) => id === "github-copilot" ? { auth: { apiKey: copilotToken() }, source: "OAuth" } : id === "opencode-go" ? { auth: { apiKey: goToken() } } : undefined,
      getApiKeyAndHeaders: async () => ({ ok: false, error: secret }), isUsingOAuth: () => true,
    } });
    const copilotPayload = { login: secret, copilot_plan: secret, quota_reset_date_utc: "2027-01-15T08:05:00Z", quota_snapshots: { premium_interactions: { token_based_billing: true, credits_used: 30, entitlement: 100, remaining: 70 } } };
    const goPayload = { usage: { rolling: { status: "ok", percent: 3, resetsAt: "2027-01-15T08:05:00Z" }, weekly: { status: "ok", percent: 4 } } };
    let providerRequests = [];
    const providerMock = (copilotBody, goBody) => async (url, options) => {
      providerRequests.push(url);
      assert.equal(options.redirect === undefined || options.redirect === "error", true);
      if (url === "https://api.github.com/copilot_internal/user") {
        assert.equal(options.headers.Authorization, "Bearer original-github-token", "Copilot quota uses the matching stored OAuth credential, never the runtime token");
        return new Response(JSON.stringify(copilotBody), { status: 200 });
      }
      assert.equal(url, "https://opencode.ai/zen/go/v1/usage");
      assert.match(options.headers.Authorization, /^Bearer go-token-[12]$/u);
      return new Response(JSON.stringify(goBody), { status: 200 });
    };
    const secretFree = (result) => { for (const value of ["runtime-token", "original-github-token", "go-token-1", "go-token-2"]) assert(!JSON.stringify(result).includes(value)); safe(result.details); };
    globalThis.fetch = providerMock(copilotPayload, goPayload);
    const copilotGo = await tool.execute("fixture", {}, undefined, undefined, copilotGoContext());
    const [, , , copilotObserved, goObserved] = copilotGo.structuredContent.providers;
    assert.deepEqual([copilotObserved.provider, copilotObserved.source, copilotObserved.reason, goObserved.provider, goObserved.source, goObserved.reason], ["github-copilot", "github-copilot-user", "ok", "opencode-go", "opencode-zen-usage", "ok"]);
    assert.deepEqual(copilotObserved.windows.map(({ label, unit, used, remaining, limit, usedPercent, usedFraction, resetsAt }) => ({ label, unit, used, remaining, limit, usedPercent, usedFraction, resetsAt })), [
      { label: "AI credits", unit: "count", used: 30, remaining: 70, limit: 100, usedPercent: 30, usedFraction: 0.3, resetsAt: Date.parse("2027-01-15T08:05:00Z") / 1000 },
    ]);
    assert.deepEqual(goObserved.windows.map(({ label, unit, usedPercent, windowMinutes }) => [label, unit, usedPercent, windowMinutes]), [["Rolling window", "percent", 3, null], ["Weekly window", "percent", 4, null]]);
    assert.equal(copilotGo.structuredContent.providers[0].reason, "auth-unavailable");
    assert.equal(providerRequests.length, 2);
    secretFree(copilotGo);

    providerRequests = [];
    globalThis.fetch = providerMock({}, { usage: {} });
    const noQuota = await tool.execute("fixture", {}, undefined, undefined, copilotGoContext());
    assert.deepEqual([3, 4].map((index) => [noQuota.structuredContent.providers[index].status, noQuota.structuredContent.providers[index].reason]), [["unknown", "no-quota-data"], ["unknown", "no-quota-data"]], "0.66.0 helper error messages still map to no-quota-data");
    secretFree(noQuota);

    globalThis.fetch = providerMock(copilotPayload, goPayload);
    let goResolutions = 0;
    let copilotResolutions = 0;
    const rotated = await tool.execute("fixture", {}, undefined, undefined, copilotGoContext({
      goToken: () => ++goResolutions === 1 ? "go-token-1" : "go-token-2",
      copilotToken: () => ++copilotResolutions === 1 ? "runtime-token" : "rotated-runtime-token",
    }));
    assert.deepEqual([3, 4].map((index) => rotated.structuredContent.providers[index].reason), ["auth-failed", "identity-changed"], "real 0.66.0 fingerprints/matching detect rotation after the query");
    assert.deepEqual([3, 4].map((index) => rotated.structuredContent.providers[index].windows), [[], []]);
    secretFree(rotated);

    providerRequests = [];
    const proxied = await tool.execute("fixture", {}, undefined, undefined, copilotGoContext({ goBaseUrl: "https://proxy.example" }));
    assert.equal(proxied.structuredContent.providers[4].reason, "auth-failed");
    assert(!providerRequests.includes("https://opencode.ai/zen/go/v1/usage"), "an overridden provider base URL never receives the credential");
    secretFree(proxied);

    const hostRequire = createRequire(join(host, "package.json"));
    const { Check } = await import(pathToFileURL(hostRequire.resolve("typebox/value")));
    assert(Check(tool.outputSchema, installed.structuredContent));
    assert(Check(tool.outputSchema, { providers: installed.structuredContent.providers.map((value, index) => index === 2 ? apiCostFixture : value) }), "live CodexBar balance/grants, UTC spend, capture time and separate refusal evidence match the output schema");
    assert(Check(tool.outputSchema, { providers: installed.structuredContent.providers.map((value, index) => index === 2 ? apiUnknownSpendFixture : value) }), "unknown CodexBar spend is nullable while its balance remains fresh");
    assert(Check(tool.outputSchema, missingClaude.structuredContent));
    assert(Check(tool.outputSchema, nativeResult.structuredContent));
    assert(Check(tool.outputSchema, missingCompanionRuntime.structuredContent));
    assert(Check(tool.outputSchema, mismatchedCompanionRuntime.structuredContent));
    for (const result of [copilotGo, noQuota, rotated, proxied]) assert(Check(tool.outputSchema, result.structuredContent));
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
      adapters: ["openai", "github-copilot", "opencode-go", "opencode"].map((id) => { const adapter = addon.adapterForProvider(id); return adapter ? [adapter.id, adapter.semantics?.kind, typeof adapter.query] : null; }),
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
    assert.deepEqual(actual.adapters, [["openai", "consumer-subscription", "function"], ["github-copilot", "consumer-subscription", "function"], ["opencode-go", "consumer-subscription", "function"], null], "the helper still exposes the three adapters and no opencode (Zen) adapter");
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
    const runtimeSnapshot = { providers: [nativeResult.structuredContent.providers[0], missingClaude.structuredContent.providers[1], nativeResult.structuredContent.providers[2], copilot, go, sanitize("opencode", report)] };
    assert(Check(tool.outputSchema, nativeResult.structuredContent));
    assert(Check(tool.outputSchema, runtimeSnapshot));
    safe(nativeResult.details);
    safe(runtimeSnapshot);
    safe(variants);
    console.log(`PASS: Pi ${hostVersion} discovery/Jiti, installed @narumitw/pi-usage@0.66.0 helper imports/auth/query with fake auth and mocked HTTP; missing/wrong helper leaves local Claude independent`);
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.quotaHelperLookups;
    if (originalAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = originalAgentDir;
    if (originalPath === undefined) delete process.env.PATH;
    else process.env.PATH = originalPath;
    await rm(workspace, { recursive: true, force: true });
    await assert.rejects(access(workspace), { code: "ENOENT" });
    console.log(`CLEANED owner=quota-test path=${workspace}`);
  }
}
