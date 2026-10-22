import assert from "node:assert/strict";
import { observeCodexbarCredits, parseCodexbarCredits } from "./credits.ts";

const secret = "private-account-token-cookie-error";
const now = 1800000000000;
const fixture = {
  provider: "codex", source: "openai-web", accountEmail: secret,
  credits: { remaining: 1234.567891, balanceReadSucceeded: true, balanceIsWorkspace: false, events: [secret] },
  openaiDashboard: { accountID: secret, creditsRemaining: 999 },
  usage: { providerCost: { balance: 999, currencyCode: "USD" } },
};
const json = (value = fixture) => JSON.stringify([value]);
const safe = (value) => assert(!JSON.stringify(value).includes(secret));
const fresh = parseCodexbarCredits(json(), now);
assert.deepEqual(fresh, {
  source: "codexbar-codex-web", capturedAt: now, status: "fresh", reason: "ok",
  remainingCredits: 1234.567891, balanceIsWorkspace: false,
});
safe(fresh);
for (const balanceIsWorkspace of [false, true]) {
  const zero = parseCodexbarCredits(json({ ...fixture, credits: { ...fixture.credits, remaining: 0, balanceIsWorkspace } }), now);
  assert.equal(zero.remainingCredits, 0);
  assert.equal(zero.balanceIsWorkspace, balanceIsWorkspace);
}
for (const remaining of [null, -1, "123", Number.MAX_VALUE]) {
  assert.throws(() => parseCodexbarCredits(json({ ...fixture, credits: { ...fixture.credits, remaining } }), now));
}
for (const credits of [undefined, {}, { ...fixture.credits, balanceReadSucceeded: false }, { ...fixture.credits, balanceIsWorkspace: undefined }]) {
  assert.throws(() => parseCodexbarCredits(json({ ...fixture, credits }), now));
}
for (const invalid of [secret, "null", "{}", "[]", JSON.stringify([fixture, fixture]), json({ ...fixture, provider: secret }), json({ ...fixture, source: "cli" })]) {
  assert.throws(() => parseCodexbarCredits(invalid, now));
}
for (const capturedAt of [NaN, Infinity, -1, Number.MAX_VALUE]) assert.throws(() => parseCodexbarCredits(json(), capturedAt));
let calls = 0;
const runner = async (file, args, options) => {
  calls++;
  assert.equal(file, "codexbar");
  assert.deepEqual(args, ["usage", "--provider", "codex", "--source", "web", "--web-timeout", "8", "--json"]);
  assert.equal(options.maxBuffer, 64 * 1024);
  assert.equal(options.encoding, "utf8");
  assert(options.signal instanceof AbortSignal);
  return { stdout: Buffer.from(json()), stderr: secret };
};
assert.deepEqual(await observeCodexbarCredits(undefined, 100, () => now, runner), fresh);
assert.equal(calls, 1);
for (const [runner, reason] of [
  [async () => { throw Object.assign(new Error(secret), { code: "ENOENT" }); }, "dependency-unavailable"],
  [async () => { throw Object.assign(new Error(secret), { code: "EACCES" }); }, "query-failed"],
  [async () => ({ stdout: secret }), "query-failed"],
  [async () => ({ stdout: "x".repeat(64 * 1024 + 1) }), "query-failed"],
]) {
  const result = await observeCodexbarCredits(undefined, 100, () => now, runner);
  assert.deepEqual(result, { source: null, capturedAt: null, status: "unavailable", reason, remainingCredits: null, balanceIsWorkspace: null });
  safe(result);
}
const cancelled = new AbortController();
cancelled.abort();
assert.equal((await observeCodexbarCredits(cancelled.signal, 100, () => now, runner)).reason, "cancelled");
assert.equal(calls, 1, "pre-cancellation never launches the CLI");
let aborted = false;
const pending = (_file, _args, options) => new Promise((_resolve, reject) => {
  options.signal.addEventListener("abort", () => { aborted = true; reject(new Error(secret)); }, { once: true });
});
const controller = new AbortController();
const waiting = observeCodexbarCredits(controller.signal, 100, () => now, pending);
controller.abort();
assert.equal((await waiting).reason, "cancelled");
assert(aborted, "cancellation reaches the child-process signal");
const keepAlive = setTimeout(() => {}, 100);
try {
  aborted = false;
  const result = await observeCodexbarCredits(undefined, 5, () => now, pending);
  assert.equal(result.reason, "timeout");
  assert(aborted, "deadline reaches the child-process signal");
  safe(result);
} finally { clearTimeout(keepAlive); }
console.log("PASS: CodexBar credit counts, scope, zero/invalid/missing balances, privacy, fixed web-only argv, failures, timeout and cancellation");

if (process.argv[2] === "--runtime") {
  const { createRequire } = await import("node:module");
  const { join, resolve } = await import("node:path");
  const { pathToFileURL, fileURLToPath } = await import("node:url");
  const { PROVIDERS, unavailable } = await import("./quota.ts");
  const host = resolve(process.argv[3]);
  const { loadExtensions } = await import(pathToFileURL(join(host, "dist/core/extensions/loader.js")));
  const loaded = await loadExtensions([fileURLToPath(new URL("./index.ts", import.meta.url))], process.cwd());
  assert.deepEqual(loaded.errors, []);
  const tool = loaded.extensions[0].tools.get("quota_status").definition;
  const hostRequire = createRequire(join(host, "package.json"));
  const { Check } = await import(pathToFileURL(hostRequire.resolve("typebox/value")));
  const providers = PROVIDERS.map((provider) => unavailable(provider, "query-failed"));
  assert(Check(tool.outputSchema, { providers, codexbarCredits: fresh }));
  const failed = await observeCodexbarCredits(cancelled.signal);
  assert(Check(tool.outputSchema, { providers, codexbarCredits: failed }));
  assert(!Check(tool.outputSchema, { providers, codexbarCredits: { ...fresh, accountID: secret } }));
  assert(!Check(tool.outputSchema, { providers, codexbarCredits: { ...fresh, remainingCredits: "123" } }));
  console.log("PASS: Pi extension loading and fresh/unavailable credit output schemas (no telemetry calls)");
}
