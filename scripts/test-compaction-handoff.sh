#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

export PI_RUNTIME="${PI_RUNTIME:-$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent}"

# Strict type check against the installed Pi declarations; the global pnpm tsc shim is broken, so use Homebrew's.
# Owned temporary resource: test-compaction-handoff owns $types and removes it on every exit.
types="$(mktemp -d)"
trap 'rm -r "$types"; test ! -e "$types" && echo "Verified temporary directory removed: $types"' EXIT
cat >"$types/tsconfig.json" <<JSON
{ "compilerOptions": { "strict": true, "noEmit": true, "target": "es2023", "lib": ["es2023"], "module": "esnext", "moduleResolution": "bundler", "skipLibCheck": true,
    "types": ["node"], "typeRoots": ["$PI_RUNTIME/node_modules/@types"],
    "paths": { "@earendil-works/pi-coding-agent": ["$PI_RUNTIME/dist/index.d.ts"], "typebox": ["$PI_RUNTIME/node_modules/typebox/build/index.d.mts"] } },
  "files": ["$PWD/home/private_dot_pi/private_agent/private_extensions/compaction-handoff.ts"] }
JSON
"$(brew --prefix)/bin/tsc" -p "$types/tsconfig.json"
echo "Strict TypeScript check passed against installed Pi declarations"

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import { mkdir, mkdtemp, open, readFile, readdir, rm, stat, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { basename, dirname, join } from "node:path"
const runtime = process.env.PI_RUNTIME!
const { createJiti } = await import(join(runtime, "node_modules/jiti/lib/jiti.mjs"))
const jiti = createJiti(join(process.cwd(), "scripts/test-compaction-handoff.sh"), {
  moduleCache: false, fsCache: false,
  alias: { "@earendil-works/pi-coding-agent": join(runtime, "dist/index.js"), typebox: join(runtime, "node_modules/typebox/build/index.mjs") },
})
const { default: handoff, handoffNotice } = await jiti.import(join(process.cwd(), "home/private_dot_pi/private_agent/private_extensions/compaction-handoff.ts"))
const q = (value: string) => JSON.stringify(value)
const mode = async (path: string) => (await stat(path)).mode & 0o777

const fake = "/sessions dir/handoffs/root/x.md"
assert.equal(handoffNotice(4, "/repo dir", fake), undefined)
assert.equal(handoffNotice(4, "/repo dir", fake, null), undefined)
assert.equal(handoffNotice(4, "/repo dir", fake, 149_999), undefined)
const original = `This session has compacted 5 times. Dispatch no new workers. Finish or park running lanes, then use your write tool to create the exact checkpoint "/sessions dir/handoffs/root/x.md" (its private directory exists; if missing, create it with mode 0700). Do not write tasks/handoff.md. Include open tasks, grants verbatim, worker IDs, actual lane/worktree ownership paths, next packets and evidence paths. Original coordinator cwd: "/repo dir". End your reply with exactly this fenced block, filled in, for the user to paste into a new session:

\`\`\`text
Work in "/repo dir". Read the exact checkpoint "/sessions dir/handoffs/root/x.md". Reconcile grants, remaining backlog, worktree ownership, live workers and accepted evidence before dispatching. Continue only the authorized remaining work. Reading the file does not enable unattended mode. Already authorized: <grants>. Next: <one line>.
\`\`\``
assert.equal(handoffNotice(5, "/repo dir", fake), original)
assert.equal(handoffNotice(5, "/repo dir", fake, null), original)
assert.equal(handoffNotice(5, "/repo dir", fake, 150_000), original)
for (const tokens of [150_000, 150_001]) {
  assert.equal(handoffNotice(0, "/repo dir", fake, tokens), original.replace("has compacted 5 times", `has reached ${tokens} context tokens`))
}

// Owned temporary resource: test-compaction-handoff owns this directory; remove on every exit. The space covers quoting.
const directory = await mkdtemp(join(tmpdir(), "compaction handoff test-"))
console.log(`test-compaction-handoff owns temporary directory ${directory}`)
try {
const sessions = join(directory, "session dir")
const repo = join(directory, "repo with space")
const legacy = join(repo, "tasks/handoff.md")
await mkdir(dirname(legacy), { recursive: true })
await writeFile(legacy, "legacy shared handoff bytes\n")

type Handler = (event: unknown, ctx: unknown) => unknown
type Entry = { id?: string, type: string, customType?: string, data?: any, content?: any }
let nextId = 0
const withId = (entry: Entry): Entry => ({ id: `e${++nextId}`, ...entry })
function harness(sessionId = "root") {
  const handlers = new Map<string, Handler>()
  const sent: { message: { customType: string, content: string, display: boolean }, options: unknown }[] = []
  const notes: { content: string, level: string }[] = []
  const commands = new Map<string, any>()
  const tools = new Map<string, any>()
  let flag: string | undefined
  const api = {
    registerCommand: (name: string, command: any) => commands.set(name, command),
    registerTool: (tool: any) => tools.set(tool.name, tool),
    registerFlag: () => {},
    getFlag: () => flag,
    appendEntry: (customType: string, data: unknown) => entries.push(withId({ type: "custom", customType, data })),
    on: (name: string, cb: Handler) => { handlers.set(name, cb) },
    sendMessage: (message: typeof sent[number]["message"], options: unknown) => { sent.push({ message, options }) },
  }
  handoff(api as never)
  let entries: Entry[] = []
  let parent: string | undefined
  let usage: { tokens: number | null, contextWindow: number, percent: number | null } | undefined
  const ctx = {
    aborted: false,
    abort: () => { ctx.aborted = true },
    hasUI: true,
    systemPrompt: "Coordinator",
    getSystemPrompt: () => ctx.systemPrompt,
    cwd: repo,
    sessionDir: sessions,
    ui: { notify: (content: string, level: string) => { notes.push({ content, level }) } },
    sessionManager: { getBranch: () => entries, getSessionId: () => sessionId, getHeader: () => ({ parentSession: parent }),
      getSessionDir: () => ctx.sessionDir, getLeafId: () => entries.at(-1)?.id ?? null },
    getContextUsage: () => usage,
  }
  const fire = (name: string) => assert.equal(handlers.get(name)!({ reason: "startup" }, ctx), undefined)
  const set = (n: number, tokens?: number | null) => {
    entries = Array.from({ length: n }, () => withId({ type: "compaction" }))
    usage = tokens === undefined ? undefined : { tokens, contextWindow: 1_000_000, percent: tokens === null ? null : tokens / 10_000 }
  }
  const boundary = (name = "agent_before_settle", outcome = "completed") => {
    const result = handlers.get(name)!({ type: name, outcome, entries: [], context: { canContinue: false } }, ctx) as any
    if (result?.entries) entries.push(...result.entries.map(withId))
    return result
  }
  const save = (markdown: string, status = "continue", signal?: AbortSignal) => tools.get("unattended_checkpoint").execute("id", { status, markdown }, signal, undefined, ctx)
  return { api, sent, notes, ctx, fire, set, boundary, handlers, tools, save,
    command: (args: string) => commands.get("unattended").handler(args, ctx),
    setFlag: (value: string) => { flag = value },
    branch: () => entries.slice(), switchBranch: (next: Entry[]) => { entries = next },
    setSession: (id: string) => { sessionId = id }, setParent: (value: string) => { parent = value },
    recorded: () => entries.findLast(e => e.type === "custom" && e.customType === "compaction-handoff")?.data,
    receipt: () => entries.findLast(e => e.type === "custom" && e.customType === "unattended-handoff")?.data,
    persist: () => { entries.push(withId({ type: "custom_message", customType: "compaction-handoff" })) } }
}

for (const event of ["session_start", "turn_end", "session_compact"]) {
  const h = harness()
  for (const tokens of [undefined, null, 0, 149_999]) {
    h.set(4, tokens)
    h.fire(event)
  }
  assert.equal(h.sent.length + h.notes.length, 0)
  h.set(4, 150_000)
  h.fire(event)
  const first = h.recorded()
  assert.deepEqual(Object.keys(first), ["sessionId", "checkpointPath", "checkpointCwd"])
  assert.equal(first.sessionId, "root")
  assert.equal(first.checkpointCwd, repo)
  assert.equal(dirname(first.checkpointPath), join(sessions, "handoffs/root"))
  assert.match(basename(first.checkpointPath), /^[0-9a-f-]{36}\.md$/)
  assert.equal(await mode(dirname(first.checkpointPath)), 0o700)
  assert.equal(await mode(join(sessions, "handoffs")), 0o700)
  assert.deepEqual(h.sent, [{
    message: { customType: "compaction-handoff", content: handoffNotice(4, repo, first.checkpointPath, 150_000), display: true },
    options: { deliverAs: "steer" },
  }])
  assert.ok(h.sent[0].message.content.includes(`Work in ${q(repo)}. Read the exact checkpoint ${q(first.checkpointPath)}.`))
  assert.deepEqual(h.notes, [{ content: h.sent[0].message.content.split("\n")[0], level: "warning" }])
  // The interactive allocation never enables unattended authority.
  assert.equal(h.handlers.get("before_agent_start")!({}, h.ctx), undefined)
  assert.equal(h.boundary(), undefined)
  await assert.rejects(h.save("# interactive only"), /not active/)
  // No repeated steer/continuation, even before the queued message is persisted.
  h.fire("turn_end")
  h.set(6, 160_000)
  h.fire("session_compact")
  h.fire("turn_end")
  assert.equal(h.sent.length, 1)
  h.persist()
  h.fire("session_start")
  h.fire("session_tree")
  h.fire("turn_end")
  assert.equal(h.sent.length, 1)
  // A replaced extension runtime reconstructs its guard from the active branch.
  handoff(h.api as never)
  h.fire("session_start")
  h.fire("turn_end")
  assert.equal(h.sent.length, 1)
  // A fresh session resets the guard; abandoned-branch notices do not apply. Each notice gets a fresh file.
  h.set(0, 149_999)
  h.fire("session_start")
  h.set(0, 150_001)
  h.fire("turn_end")
  assert.equal(h.sent.length, 2)
  assert.notEqual(h.recorded().checkpointPath, first.checkpointPath)
  assert.equal(h.sent[1].message.content, handoffNotice(0, repo, h.recorded().checkpointPath, 150_001))
  // The persisted custom entry alone also guards a reload before the steer message is persisted.
  const marked = h.branch().filter(e => e.type !== "custom_message")
  h.switchBranch(marked)
  handoff(h.api as never)
  h.fire("session_start")
  h.fire("turn_end")
  assert.equal(h.sent.length, 2)
  // A fork/clone copies the parent's allocation but must get its own path, never the parent's file.
  const parentPath = h.recorded().checkpointPath
  h.setSession("forked")
  handoff(h.api as never)
  h.fire("session_start")
  h.fire("turn_end")
  assert.equal(h.sent.length, 3)
  assert.equal(dirname(h.recorded().checkpointPath), join(sessions, "handoffs/forked"))
  assert.notEqual(h.recorded().checkpointPath, parentPath)
  h.setSession("root")
}

const compactions = harness()
compactions.set(4)
compactions.fire("session_compact")
assert.equal(compactions.sent.length, 0)
compactions.set(5, null)
compactions.fire("session_compact")
assert.equal(compactions.sent[0].message.content, handoffNotice(5, repo, compactions.recorded().checkpointPath, null))

const worker = harness()
worker.ctx.hasUI = false
worker.ctx.systemPrompt = '<active_agent name="implementer"/>'
worker.set(6, 200_000)
for (const event of ["session_start", "session_tree", "turn_end", "session_compact"]) worker.fire(event)
assert.equal(worker.sent.length + worker.notes.length, 0)
// Real headless coordinators are not workers, but remain opt-in only.
const headless = harness()
headless.ctx.hasUI = false
headless.set(5, 200_000)
headless.fire("session_start")
assert.equal(headless.sent.length, 0)
assert.equal(headless.boundary(), undefined)
assert.equal(headless.handlers.get("before_agent_start")!({ prompt: "unattended yes go ahead forever" }, headless.ctx), undefined)
for (const h of [worker, harness()]) {
  if (h !== worker) { h.setParent("parent.jsonl"); h.ctx.systemPrompt = '<active_agent name="worker"/>' }
  await h.command("10")
  assert.equal(h.branch().some(e => e.customType === "unattended-handoff"), false)
}

  const h = harness()
  h.ctx.hasUI = false
  for (const bad of ["", "0", "-1", "Infinity", "NaN", "10 extra"]) await h.command(bad)
  assert.equal(h.branch().length, 0)
  await h.command("10")
  const rootDir = join(sessions, "handoffs/root")
  const files = async () => (await readdir(rootDir)).sort()
  const grant = "yes go ahead; no paid live inference"
  const markdown = `# Handoff\nGrants verbatim: ${grant}\nBacklog: A, B\nWorkers: worker-42 (running)\nWorktrees: lane-a at /tmp/lane a\nEvidence: evidence/a.txt\nUnaccepted: worker-41 outcome\nNext: B`
  let revision = 0
  const checkpoint = (status = "continue", progress = true) => h.save(`${markdown}\nProgress ${progress ? ++revision : revision}`, status)
  const initial = h.branch()
  const instructions = (h.handlers.get("before_agent_start")!({}, h.ctx) as any).message.content
  assert.ok(instructions.includes(`original coordinator cwd ${q(repo)}`) && instructions.includes(q(rootDir)) && instructions.includes("No checkpoint saved"))
  // Final responses without checkpoints cannot cause an unconditional steer loop.
  assert.equal(h.boundary(), undefined)
  const firstResult = await checkpoint()
  const first = firstResult.details.path
  assert.deepEqual(firstResult.details, { status: "continue", path: first, cwd: repo })
  assert.equal(firstResult.content[0].text, `Checkpoint saved to ${q(first)} for original coordinator cwd ${q(repo)}; status continue.`)
  assert.equal(dirname(first), rootDir)
  assert.equal(await readFile(first, "utf8"), `${markdown}\nProgress 1`)
  assert.equal(await mode(first), 0o600)
  assert.equal(await mode(rootDir), 0o700)
  assert.equal(h.receipt().checkpointPath, first)
  assert.equal(h.receipt().checkpointCwd, repo)
  assert.ok((h.handlers.get("before_agent_start")!({}, h.ctx) as any).message.content.includes(`Latest checkpoint on this branch: ${q(first)} (cwd ${q(repo)})`))
  // Inject an interrupted staging write; earlier checkpoints and receipts survive, nothing new is published.
  const probePath = join(directory, "write-probe")
  const probe = await open(probePath, "wx")
  const filePrototype = Object.getPrototypeOf(probe)
  await probe.close()
  await rm(probePath)
  const writeFileMethod = filePrototype.writeFile
  const beforeFailure = h.branch()
  filePrototype.writeFile = async function () { await writeFileMethod.call(this, "partial staging bytes"); throw new Error("injected interrupted write") }
  try { await assert.rejects(checkpoint, /injected interrupted write/) } finally { filePrototype.writeFile = writeFileMethod; revision-- }
  assert.equal(await readFile(first, "utf8"), `${markdown}\nProgress 1`)
  assert.deepEqual(h.branch(), beforeFailure)
  assert.deepEqual(await files(), [basename(first)], "no owned staging files survive failed writes")
  // Expiry, abort and branch navigation during the async save publish nothing and append no receipt.
  const sync = filePrototype.sync
  const failsDuring = async (during: () => void, signal?: AbortSignal) => {
    const before = h.branch()
    const published = await files()
    filePrototype.sync = async function () { await sync.call(this); during() }
    try { await assert.rejects(h.save(`${markdown}\nRejected`, "continue", signal), /changed during checkpoint/) } finally { filePrototype.sync = sync }
    assert.deepEqual(await files(), published)
    return before
  }
  const now = Date.now
  try { assert.deepEqual(h.branch(), await failsDuring(() => { Date.now = () => now() + 11 * 60_000 })) } finally { Date.now = now }
  const controller = new AbortController()
  assert.deepEqual(h.branch(), await failsDuring(() => controller.abort(), controller.signal))
  const navigated = await failsDuring(() => h.switchBranch(initial))
  assert.deepEqual(h.branch(), initial, "no receipt on the navigated-to branch")
  h.switchBranch(navigated)
  handoff(h.api as never) // Runtime reload reconstructs active-branch opt-in, ready guard and exact location.
  const resumed = h.boundary()
  assert.equal(resumed.continue, true)
  assert.ok(resumed.entries.at(-1).content.startsWith(`Checkpoint saved to ${q(first)} for original coordinator cwd ${q(repo)}.`))
  assert.equal(h.sent.length, 0) // No queued steering/user prompt was needed.
  assert.equal(h.boundary(), undefined)
  await checkpoint("continue", false)
  assert.equal(h.boundary(), undefined, "identical checkpoints must not loop, even under a new filename")
  assert.equal((await files()).length, 2)
  // Sibling branches publish separate immutable files; each branch restores its own exact path.
  const base = h.branch()
  const a = (await h.save(`${markdown}\nBranch A`)).details.path
  const branchA = h.branch()
  h.switchBranch(base.slice())
  const b = (await h.save(`${markdown}\nBranch B`)).details.path
  const branchB = h.branch()
  assert.notEqual(a, b)
  assert.equal(await readFile(a, "utf8"), `${markdown}\nBranch A`)
  assert.equal(await readFile(b, "utf8"), `${markdown}\nBranch B`)
  h.switchBranch(branchA)
  handoff(h.api as never)
  h.fire("session_tree")
  const onA = h.boundary().entries.at(-1).content
  assert.ok(onA.includes(q(a)) && !onA.includes(q(b)))
  h.switchBranch(branchB)
  h.fire("session_tree")
  assert.ok(h.boundary().entries.at(-1).content.includes(q(b)))
  const parallelMarkdown = `${markdown}\nParallel progress`
  const parallel = await Promise.all([1, 2].map(() => h.save(parallelMarkdown)))
  assert.equal(h.boundary(), undefined, "parallel identical receipts cannot arm a checkpoint-only loop")
  assert.notEqual(parallel[0].details.path, parallel[1].details.path)
  for (const { details } of parallel) assert.equal(await readFile(details.path, "utf8"), parallelMarkdown)
  assert.ok((await files()).every(name => /^[0-9a-f-]{36}\.md$/.test(name)), "no staging files survive")
  for (const status of ["blocked", "done"]) {
    await checkpoint(status)
    assert.equal(h.boundary(), undefined)
    const stopped = harness(`stopped-${status}`)
    await stopped.command("10")
    await stopped.save(markdown, status)
    const stoppedBranch = stopped.branch()
    stopped.set(0, 150_000)
    stopped.switchBranch([...stoppedBranch, ...stopped.branch()])
    assert.equal(stopped.boundary("turn_end"), undefined, `${status} must survive a token threshold crossing`)
    stopped.switchBranch([...stopped.branch(), ...Array.from({ length: 5 }, () => withId({ type: "compaction" }))])
    handoff(stopped.api as never)
    assert.equal(stopped.boundary(), undefined, `${status} must survive compaction and runtime reload`)
  }
  await checkpoint()
  assert.equal(h.boundary("agent_before_settle", "error"), undefined)
  assert.equal(h.boundary("agent_before_settle", "aborted"), undefined)
  h.switchBranch(initial)
  assert.equal(h.boundary(), undefined)
  h.switchBranch([])
  assert.equal(h.boundary(), undefined)
  await assert.rejects(checkpoint, /not active/)
  // A fork has a new session ID: no inherited authority; a fresh opt-in saves under its own session directory.
  h.switchBranch(branchB.slice())
  h.setSession("forked")
  assert.equal(h.boundary(), undefined)
  assert.equal(h.handlers.get("before_agent_start")!({}, h.ctx), undefined)
  await assert.rejects(checkpoint, /not active/)
  await h.command("10")
  const forked = (await h.save(`${markdown}\nForked`)).details.path
  assert.equal(dirname(forked), join(sessions, "handoffs/forked"))
  h.setSession("root")
  await h.command("off")
  assert.equal(h.boundary(), undefined)
  await assert.rejects(checkpoint, /not active/)
  await h.command(".000001")
  await Bun.sleep(5)
  assert.equal(h.boundary(), undefined)
  h.fire("turn_start")
  assert.equal(h.ctx.aborted, true)
  const blocked = h.handlers.get("tool_call")!({}, h.ctx) as any
  assert.equal(blocked.block, true)
  assert.equal(blocked.terminate, true)
  await h.command("off")
  assert.equal(h.handlers.get("tool_call")!({}, h.ctx), undefined)

  // Two coordinators started in the same cwd keep their own files; a distinct physical cwd is recorded as such.
  const other = join(directory, "other repo")
  await mkdir(other)
  const coordinators = ["alpha", "beta", "gamma"].map(id => harness(id))
  coordinators[2].ctx.cwd = other
  for (const c of coordinators) await c.command("10")
  const saved = await Promise.all(coordinators.map((c, i) => c.save(`${markdown}\nCoordinator ${i}`)))
  for (const [i, { details }] of saved.entries()) {
    assert.equal(dirname(details.path), join(sessions, "handoffs", ["alpha", "beta", "gamma"][i]))
    assert.equal(await readFile(details.path, "utf8"), `${markdown}\nCoordinator ${i}`)
    assert.equal(coordinators[i].receipt().checkpointPath, details.path)
    assert.ok(coordinators[i].boundary().entries.at(-1).content.includes(`${q(details.path)} for original coordinator cwd ${q(i === 2 ? other : repo)}`))
  }
  assert.deepEqual(saved.map(r => r.details.cwd), [repo, repo, other])

  const thresholds = harness()
  await thresholds.command("10")
  const opted = thresholds.branch()
  thresholds.set(5, 150_000)
  thresholds.switchBranch([...opted, ...thresholds.branch()])
  assert.equal(thresholds.boundary("turn_end").continue, true)
  assert.equal(thresholds.boundary("turn_end"), undefined)
  assert.equal(thresholds.boundary(), undefined)
  thresholds.switchBranch([...thresholds.branch(), ...Array.from({ length: 5 }, () => withId({ type: "compaction" }))])
  assert.equal(thresholds.boundary("turn_end").continue, true)
  assert.equal(thresholds.boundary("turn_end"), undefined)
  assert.equal(thresholds.sent.length, 0)
  const cli = harness()
  cli.ctx.hasUI = false
  cli.switchBranch([withId({ type: "model_change" }), withId({ type: "thinking_level_change" })])
  cli.setFlag("10")
  cli.fire("session_start")
  assert.equal(cli.branch().length, 3)
  cli.fire("session_start")
  assert.equal(cli.branch().length, 3)
  const inherited = harness()
  inherited.ctx.systemPrompt = '<active_agent name="worker"/>'
  inherited.switchBranch(cli.branch())
  assert.equal(inherited.boundary(), undefined)
  inherited.setFlag("10")
  inherited.fire("session_start")
  assert.equal(inherited.branch().length, 3)
  // Installed Pi SDK, real extension runner/persisted session/agent loop; only the provider is mocked.
  const sdk = await import(join(runtime, "dist/index.js"))
  const { createAssistantMessageEventStream } = await import(join(runtime, "node_modules/@earendil-works/pi-ai/dist/utils/event-stream.js"))
  const modelRuntime = await sdk.ModelRuntime.create({ authPath: join(directory, "auth.json"), modelsPath: null, modelsStorePath: join(directory, "models"), refreshOnCreate: false, allowModelNetwork: false })
  let requests = 0
  const observed: string[] = []
  const mockStream = (model: any, context: any) => {
    requests++
    assert.ok(requests <= 6, "unbounded continuation")
    const finalRole = context.messages.at(-1)?.role
    if (requests === 3 || requests === 5) assert.equal(finalRole, "user", "checkpoint custom message must make final assistant response actionable")
    const status = requests === 5 ? "done" : "continue"
    const content = requests % 2 === 1 ? [{ type: "toolCall", id: `checkpoint-${requests}`, name: "unattended_checkpoint", arguments: { status, markdown: `${markdown}\nProgress ${requests}` } }] : [{ type: "text", text: "Packet boundary, no user input needed." }]
    const message = { role: "assistant", content, api: model.api, provider: model.provider, model: model.id,
      usage: { input: 10, output: 10, cacheRead: 0, cacheWrite: 0, totalTokens: 20, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: requests % 2 === 1 ? "toolUse" : "stop", timestamp: Date.now() }
    const stream = createAssistantMessageEventStream()
    stream.push({ type: "start", partial: message })
    stream.push({ type: "done", reason: message.stopReason, message })
    return stream
  }
  modelRuntime.registerProvider("checkpoint-test", { api: "checkpoint-test-api", apiKey: "not-a-real-key", baseUrl: "http://invalid.invalid", models: [{ id: "mock", name: "Mock", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 1_000_000, maxTokens: 1000 }], streamSimple: mockStream })
  const settings = sdk.SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } })
  const loader = new sdk.DefaultResourceLoader({ cwd: repo, agentDir: directory, settingsManager: settings,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    extensionFactories: [handoff, (pi: any) => { for (const name of ["agent_before_settle", "agent_settled"]) pi.on(name, () => { observed.push(name) }) }] })
  await loader.reload()
  const sdkSessions = join(directory, "sdk sessions")
  const manager = sdk.SessionManager.create(repo, sdkSessions)
  const { session } = await sdk.createAgentSession({ cwd: repo, agentDir: directory, resourceLoader: loader, sessionManager: manager, settingsManager: settings, modelRuntime, model: modelRuntime.getModel("checkpoint-test", "mock"), tools: ["unattended_checkpoint"] })
  try {
    const errors: any[] = []
    await session.bindExtensions({ onError: (error: any) => errors.push(error) })
    await session.prompt("/unattended 10")
    assert.equal(requests, 0, "opt-in command must not spend inference")
    await session.prompt(`Backlog: A then B then C. Grants verbatim: ${grant}. Save running worker-42 and unaccepted worker-41 evidence.`)
    assert.equal(requests, 6, "two final responses continued without another user prompt; done stopped")
    assert.deepEqual(errors, [])
    assert.equal(observed.filter(name => name === "agent_settled").length, 1)
    const continuations = manager.getBranch().filter((entry: any) => entry.type === "custom_message" && entry.customType === "unattended-continuation")
    assert.equal(continuations.length, 2)
    assert.equal(manager.getBranch().filter((entry: any) => entry.type === "message" && entry.message.role === "user").length, 1)
    // Reopen the persisted session file: the active branch restores the exact last checkpoint and original cwd.
    const reopened = sdk.SessionManager.open(manager.getSessionFile(), sdkSessions)
    const receipts = reopened.getBranch().filter((entry: any) => entry.type === "custom" && entry.customType === "unattended-handoff" && entry.data.checkpointPath)
    const last = receipts.at(-1).data
    assert.equal(last.sessionId, manager.getSessionId())
    assert.equal(last.checkpointCwd, repo)
    assert.equal(dirname(last.checkpointPath), join(sdkSessions, "handoffs", manager.getSessionId()))
    assert.equal(await readFile(last.checkpointPath, "utf8"), `${markdown}\nProgress 5`)
    const paths = [...new Set(receipts.map((entry: any) => entry.data.checkpointPath))] as string[]
    assert.equal(paths.length, 3, "each checkpoint revision gets a fresh file")
    for (const [i, entry] of continuations.entries()) assert.ok((entry as any).content.startsWith(`Checkpoint saved to ${q(paths[i])} for original coordinator cwd ${q(repo)}.`))
    console.log("Installed Pi lifecycle proof passed: 6 mock requests, 2 checkpoint continuations, 1 user prompt, 1 settlement, persisted reopen, no network/inference")
  } finally { session.dispose() }
  assert.equal(await readFile(legacy, "utf8"), "legacy shared handoff bytes\n", "legacy tasks/handoff.md stays byte-identical")
  assert.deepEqual(await readdir(dirname(legacy)), ["handoff.md"])
  console.log("Compaction handoff and unattended state checks passed")
} finally {
  await rm(directory, { recursive: true, force: true })
  await assert.rejects(readFile(directory), { code: "ENOENT" })
  console.log(`Verified temporary directory removed: ${directory}`)
}
TS
