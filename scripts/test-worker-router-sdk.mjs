#!/usr/bin/env node
// Offline lifecycle smoke test: worker-router.ts on the installed Pi SDK with the faux provider.
//   node scripts/test-worker-router-sdk.mjs [--runtime <pi package root>] [--allow-missing]
// Env: WORKER_ROUTER_PATH (override module path), PI_RUNTIME (Pi package root), WORKER_ROUTER_CANDIDATE=provider/id (physical model route/narrow may pick;
// default is the first narrow candidate in coordinator-routing.md). Assumes worker-router.ts is a Pi extension
// (default export) that registers virtual model route/narrow; all real credentials/network are blocked.
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const rootIndex = args.indexOf("--runtime");
const router = process.env.WORKER_ROUTER_PATH ?? fileURLToPath(new URL("../home/private_dot_pi/private_agent/private_extensions/worker-router.ts", import.meta.url));
if (!existsSync(router)) {
  const message = `worker-router.ts not present at ${router}`;
  if (flag("--allow-missing")) { console.log(`SKIP: ${message}`); process.exit(0); }
  console.error(`FAIL: ${message}. Re-run once the module exists (or pass --allow-missing).`);
  process.exit(1);
}

const host = resolve(
  (rootIndex >= 0 ? args[rootIndex + 1] : undefined) ?? process.env.PI_RUNTIME
    ?? join(execFileSync("brew", ["--prefix", "pi-coding-agent"], { encoding: "utf8", timeout: 30000 }).trim(), "libexec/lib/node_modules/@earendil-works/pi-coding-agent"),
);
const sdk = await import(pathToFileURL(join(host, "dist/index.js")).href);
const ai = await import(pathToFileURL(join(host, "node_modules/@earendil-works/pi-ai/dist/index.js")).href);
const { ModelRuntime, createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } = sdk;
const { fauxProvider, fauxAssistantMessage } = ai;

const [candidateProvider, ...candidateRest] = (process.env.WORKER_ROUTER_CANDIDATE ?? "opencode-go/claude-haiku-5-5").split("/");
const candidateId = candidateRest.join("/");

// Offline guards: no ambient credentials, no network, no telemetry, disposable agent dir.
for (const key of Object.keys(process.env)) if (/(API_KEY|TOKEN|SECRET|PASSWORD)/i.test(key)) delete process.env[key];
process.env.PI_OFFLINE = "1";
process.env.PI_TELEMETRY = "0";
let networkCalls = 0;
globalThis.fetch = async () => { networkCalls++; throw new Error("Network forbidden in worker-router smoke test"); };

const workspace = await mkdtemp(join(tmpdir(), "worker-router-sdk-"));
console.log(`TEMP owner=test-worker-router-sdk path=${workspace}`);
const agentDir = join(workspace, "agent");
const cwd = join(workspace, "cwd");
await mkdir(agentDir, { recursive: true });
await mkdir(cwd, { recursive: true });
process.env.PI_CODING_AGENT_DIR = agentDir;

const sessions = [];
try {
  const faux = fauxProvider({ provider: candidateProvider, models: [{ id: candidateId, reasoning: true }] });
  const modelRuntime = await ModelRuntime.create({
    authPath: join(agentDir, "auth.json"), modelsPath: null, modelsStorePath: join(agentDir, "models-store.json"),
    refreshOnCreate: false, allowModelNetwork: false,
  });
  modelRuntime.registerNativeProvider(faux.provider);
  await modelRuntime.setRuntimeApiKey(candidateProvider, "faux-offline-key"); // in-memory only; makes the mock candidate "eligible"
  assert((await modelRuntime.getAvailable()).some((m) => m.provider === candidateProvider && m.id === candidateId), "mock candidate must be available"); // also refreshes the sync snapshot the router reads
  const physical = faux.getModel();

  // Every call is recorded; the reply echoes the last user text so concurrent workers stay distinguishable.
  const calls = [];
  const text = (message) => typeof message.content === "string" ? message.content : message.content.map((part) => part.text ?? "").join("");
  const echo = (context, _options, _state, model) => {
    const transcript = context.messages.map((message) => `${message.role}:${text(message)}`).join("\n");
    calls.push({ model: `${model.provider}/${model.id}`, transcript });
    const last = context.messages.toReversed().find((message) => message.role === "user");
    return fauxAssistantMessage(`ok ${last ? text(last) : ""}`);
  };
  faux.setResponses(Array.from({ length: 16 }, () => echo));

  const open = async (name, model) => {
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
    const resourceLoader = new DefaultResourceLoader({
      cwd, agentDir, settingsManager, noExtensions: true, additionalExtensionPaths: [router],
      noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true, systemPrompt: "Smoke test.",
    });
    await resourceLoader.reload();
    const { session } = await createAgentSession({
      cwd, agentDir, modelRuntime, model, thinkingLevel: "low", resourceLoader, settingsManager,
      sessionManager: SessionManager.inMemory(cwd), noTools: "all",
    });
    await session.bindExtensions({});
    sessions.push(session);
    session.testName = name;
    return session;
  };
  const dispose = (session) => { session.dispose(); sessions.splice(sessions.indexOf(session), 1); };
  const lastAssistant = (session) => session.messages.toReversed().find((message) => message.role === "assistant");
  const expectPhysical = (session, marker) => {
    const reply = lastAssistant(session);
    assert.equal(reply.stopReason, "stop", `${session.testName}: ${reply.errorMessage ?? "request failed"}`);
    assert.deepEqual([reply.provider, reply.model, reply.api], [candidateProvider, candidateId, physical.api], `${session.testName}: response must name the physical model`);
    assert.match(text(reply), new RegExp(marker));
    assert.equal(session.model.provider, "route", `${session.testName}: selection must stay virtual`);
    assert.equal(session.model.id, "narrow");
  };
  const callsFor = (marker) => calls.filter((call) => call.transcript.includes(marker));

  // Root loads the router into the shared runtime; workers reuse that runtime like pi-subagents children.
  const root = await open("root", physical);
  const route = modelRuntime.getModel("route", "narrow");
  assert(route, "worker-router must register virtual model route/narrow when the root session binds");

  const worker1 = await open("worker1", route);
  const worker2 = await open("worker2", route);
  await Promise.all([worker1.prompt("MARK-W1"), worker2.prompt("MARK-W2")]);
  expectPhysical(worker1, "MARK-W1");
  expectPhysical(worker2, "MARK-W2");
  for (const marker of ["MARK-W1", "MARK-W2"]) assert.equal(callsFor(marker).length, 1);
  assert(!callsFor("MARK-W1")[0].transcript.includes("MARK-W2"), "worker1 request leaked worker2 context");
  assert(!callsFor("MARK-W2")[0].transcript.includes("MARK-W1"), "worker2 request leaked worker1 context");

  // Completion releases each worker's slot (router lease) without any disposal.
  const leases = globalThis[Symbol.for("dotfiles.worker-router.store")]?.leases;
  assert(leases, "worker-router shared store not found");
  assert.equal(leases.size, 0, "settled workers still hold leases");

  // Worker completion/disposal must not unregister the shared route or disturb a live sibling.
  dispose(worker1);
  assert(modelRuntime.getModel("route", "narrow"), "disposing a worker removed route/narrow from the shared runtime");
  await worker2.prompt("MARK-W2B");
  expectPhysical(worker2, "MARK-W2B");
  const w2b = callsFor("MARK-W2B")[0].transcript;
  assert(w2b.includes("MARK-W2") && !w2b.includes("MARK-W1"), "live sibling must keep only its own history");

  // Next invocation after disposal starts clean.
  const worker3 = await open("worker3", modelRuntime.getModel("route", "narrow"));
  await worker3.prompt("MARK-W3");
  expectPhysical(worker3, "MARK-W3");
  const w3 = callsFor("MARK-W3")[0].transcript;
  assert(!/MARK-W[12]/.test(w3), "next invocation received stale worker context");
  assert(!worker3.sessionManager.getBranch().some((entry) => /MARK-W[12]/.test(JSON.stringify(entry))), "next invocation session holds stale entries");

  // Direct (non-agent-loop) resolution still lands on the eligible physical candidate after workers are gone.
  dispose(worker2);
  dispose(worker3);
  const resolved = await modelRuntime.resolveModel(route, [], { reason: "direct", thinkingLevel: "low" });
  assert.deepEqual([resolved.model.provider, resolved.model.id], [candidateProvider, candidateId]);
  assert.notEqual(resolved.model.api, "pi-virtual");

  // Root is independent of worker lifecycle.
  await root.prompt("MARK-ROOT");
  assert.equal(lastAssistant(root).stopReason, "stop");
  assert.equal(leases.size, 0, "leases remain after all workers settled and disposed");
  assert.equal(calls.length, 5, "unexpected number of faux provider calls");
  assert(calls.every((call) => call.model === `${candidateProvider}/${candidateId}`));
  assert.equal(networkCalls, 0, "network was attempted");
  console.log(`PASS worker-router SDK smoke (${calls.length} faux calls on ${candidateProvider}/${candidateId}, Pi ${JSON.parse(await (await import("node:fs/promises")).readFile(join(host, "package.json"), "utf8")).version})`);
} finally {
  for (const session of sessions) { try { session.dispose(); } catch {} }
  await rm(workspace, { recursive: true, force: true });
  console.log(`CLEANED ${workspace} absent=${!existsSync(workspace)}`);
}
