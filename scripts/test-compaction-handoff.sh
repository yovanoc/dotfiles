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
const original = `This session has compacted 5 times. Dispatch no new workers. Finish or park running lanes, then call handoff_checkpoint once with the Markdown checkpoint; it writes the exact private path "/sessions dir/handoffs/root/x.md". Do not use other tools or write tasks/handoff.md. Include open tasks, grants verbatim, worker IDs, actual lane/worktree ownership paths, next packets and evidence paths. Original coordinator cwd: "/repo dir". After the tool succeeds, end your reply with exactly this fenced block, filled in, for the user to paste into a new session:

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
let nextToolCallId = 0
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
  const toolCall = (toolName: string, input: Record<string, unknown>, toolCallId = `tool${++nextToolCallId}`) => handlers.get("tool_call")!({ toolName, input, toolCallId }, ctx) as any
  const toolResult = (toolName: string, input: Record<string, unknown>, isError = false, toolCallId = "") => handlers.get("tool_result")!({ toolName, input, isError, toolCallId }, ctx)
  const input = (source = "interactive") => handlers.get("input")!({ source, text: "Continue in this session" }, ctx)
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
  return { api, sent, notes, ctx, fire, set, boundary, handlers, tools, save, toolCall, toolResult, input,
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
  // A threshold notice gates every tool except one exact private checkpoint write.
  assert.deepEqual(h.toolCall("bash", { command: "touch /tmp/should-not-run" }).block, true)
  const exactCheckpoint = { path: first.checkpointPath, content: "# checkpoint" }
  assert.equal(h.toolCall("write", exactCheckpoint, "checkpoint-save"), undefined)
  assert.deepEqual(h.toolCall("write", exactCheckpoint, "duplicate-save").block, true)
  assert.deepEqual(h.toolCall("write", { path: join(sessions, "other.md"), content: "# bypass" }).block, true)
  assert.deepEqual(h.toolCall("unattended_checkpoint", { status: "continue", markdown: "# bypass" }).block, true)
  h.toolResult("write", exactCheckpoint, false, "checkpoint-save")
  assert.deepEqual(h.toolCall("write", { path: first.checkpointPath, content: "# overwrite" }).block, true)
  // The interactive allocation never enables unattended authority; only new user input approves further work.
  assert.equal(h.handlers.get("before_agent_start")!({ messageType: "custom" }, h.ctx), undefined)
  assert.deepEqual(h.toolCall("bash", { command: "still-blocked" }).block, true)
  assert.equal(h.handlers.get("before_agent_start")!({ messageType: "user" }, h.ctx), undefined)
  assert.equal(h.input("extension"), undefined)
  assert.deepEqual(h.toolCall("bash", { command: "extension-still-blocked" }).block, true)
  assert.equal(h.input(), undefined)
  assert.equal(h.toolCall("bash", { command: "user-approved" }), undefined)
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
  assert.deepEqual(h.toolCall("bash", { command: "new-session gate" }).block, true)
  assert.equal(h.toolCall("write", { path: h.recorded().checkpointPath, content: "# new session checkpoint" }), undefined)
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
  assert.deepEqual(h.toolCall("bash", { command: "fork gate" }).block, true)
  h.setSession("root")
}

// Approval belongs to the exact session, allocation and branch where real input arrived.
{
  const h = harness("navigation")
  h.set(5)
  h.fire("session_start")
  const pendingBranch = h.branch()
  const original = h.recorded()
  h.input("rpc")
  h.input("rpc")
  const approvedBranch = h.branch()
  assert.equal(approvedBranch.filter(e => e.customType === "compaction-handoff-approved").length, 1, "repeated input does not duplicate approval")
  assert.equal(h.toolCall("bash", {}), undefined)
  h.switchBranch(pendingBranch)
  h.fire("session_tree")
  h.input("extension")
  assert.equal(h.branch().some(e => e.customType === "compaction-handoff-approved"), false)
  assert.equal(h.toolCall("bash", {}).block, true, "approval on an abandoned branch does not release this branch")
  h.switchBranch(approvedBranch)
  h.fire("session_tree")
  assert.equal(h.toolCall("bash", {}), undefined, "returning to the approved branch restores its receipt")
  // A session replacement/fork inherits neither approval nor the parent's checkpoint allocation.
  h.setSession("navigation-fork")
  h.fire("session_start")
  const fork = h.recorded()
  assert.notEqual(fork.checkpointPath, original.checkpointPath)
  assert.equal(fork.sessionId, "navigation-fork")
  assert.equal(h.toolCall("bash", {}).block, true)
  h.input()
  assert.deepEqual(h.branch().at(-1)?.data, { sessionId: "navigation-fork", checkpointPath: fork.checkpointPath })
  assert.equal(h.toolCall("bash", {}), undefined)
  h.setSession("navigation")
  h.switchBranch(pendingBranch)
  h.fire("session_start")
  assert.equal(h.toolCall("bash", {}).block, true, "the fork's input cannot approve its parent's pending allocation")
  // Input received without an allocation cannot pre-approve a later threshold crossing.
  h.switchBranch([])
  h.input()
  h.set(5)
  h.fire("session_tree")
  assert.notEqual(h.recorded().checkpointPath, original.checkpointPath)
  assert.equal(h.toolCall("bash", {}).block, true)
}

const compactions = harness()
compactions.set(4)
compactions.fire("session_compact")
assert.equal(compactions.sent.length, 0)
assert.equal(compactions.toolCall("bash", { command: "not yet" }), undefined)
compactions.set(5, null)
compactions.fire("session_compact")
assert.equal(compactions.sent[0].message.content, handoffNotice(5, repo, compactions.recorded().checkpointPath, null))
assert.deepEqual(compactions.toolCall("bash", { command: "blocked at five" }).block, true)
assert.equal(compactions.toolCall("write", { path: compactions.recorded().checkpointPath, content: "# exact checkpoint" }), undefined)

{
const noPending = harness()
const checkpointTool = noPending.tools.get("handoff_checkpoint")
assert.ok(checkpointTool)
assert.equal(noPending.tools.has("write"), false, "the extension harness has no write tool")
assert.deepEqual(Object.keys(checkpointTool.parameters.properties), ["markdown"])
await assert.rejects(checkpointTool.execute("no-pending", { markdown: "# rejected" }, undefined, undefined, noPending.ctx), /No pending interactive handoff/)

const internal = harness("interactive")
internal.set(5, null)
internal.fire("session_compact")
const internalTool = internal.tools.get("handoff_checkpoint")
const internalPath = internal.recorded().checkpointPath
const internalDir = dirname(internalPath)
const handoffWorker = harness("interactive")
handoffWorker.setParent("parent.jsonl")
handoffWorker.ctx.systemPrompt = '<active_agent name="worker"/>'
handoffWorker.switchBranch(internal.branch())
await assert.rejects(internalTool.execute("worker", { markdown: "# rejected worker" }, undefined, undefined, handoffWorker.ctx), /Workers cannot write/)
for (const source of ["interactive", "rpc", "extension"]) handoffWorker.input(source)
assert.equal(handoffWorker.branch().some(entry => entry.customType === "compaction-handoff-approved"), false, "worker input never approves coordinator handoff")
assert.equal(handoffWorker.toolCall("handoff_checkpoint", { markdown: "# rejected worker" }).block, true)
const originalCheckpoint = "pre-existing checkpoint must not be overwritten"
await writeFile(internalPath, originalCheckpoint)
await assert.rejects(internalTool.execute("collision", { markdown: "# overwrite" }, undefined, undefined, internal.ctx))
assert.equal(await readFile(internalPath, "utf8"), originalCheckpoint)
await rm(internalPath)
const probePath = join(directory, "interactive-write-probe")
const probe = await open(probePath, "wx")
const filePrototype = Object.getPrototypeOf(probe)
await probe.close()
await rm(probePath)
const writeFileMethod = filePrototype.writeFile
internal.toolCall("handoff_checkpoint", { markdown: "# failed checkpoint" }, "failed-checkpoint")
filePrototype.writeFile = async function () { throw new Error("injected checkpoint write failure") }
try {
  await assert.rejects(internalTool.execute("failed-checkpoint", { markdown: "# failed checkpoint" }, undefined, undefined, internal.ctx), /injected checkpoint write failure/)
} finally {
  filePrototype.writeFile = writeFileMethod
  internal.toolResult("handoff_checkpoint", { markdown: "# failed checkpoint" }, true, "failed-checkpoint")
}
await assert.rejects(readFile(internalPath), { code: "ENOENT" })
assert.equal(internal.branch().some(entry => entry.customType === "compaction-handoff-written"), false)
const markdown = "# Final interactive handoff\nBacklog: resume from here"
assert.equal(internal.toolCall("handoff_checkpoint", { markdown }, "successful-checkpoint"), undefined)
const saved = await internalTool.execute("successful-checkpoint", { markdown }, undefined, undefined, internal.ctx)
internal.toolResult("handoff_checkpoint", { markdown }, false, "successful-checkpoint")
assert.deepEqual(saved.details, { path: internalPath, cwd: repo })
assert.equal(await readFile(internalPath, "utf8"), markdown)
assert.equal(await mode(internalPath), 0o600)
assert.equal(await mode(internalDir), 0o700)
assert.equal(internal.branch().some(entry => entry.customType === "compaction-handoff-written" && entry.data.checkpointPath === internalPath), true)
await assert.rejects(internalTool.execute("duplicate-checkpoint", { markdown: "# overwrite" }, undefined, undefined, internal.ctx), /No pending interactive handoff/)
assert.deepEqual(internal.toolCall("handoff_checkpoint", { markdown: "# duplicate" }).block, true)
assert.deepEqual(internal.toolCall("write", { path: internalPath, content: "# overwrite" }).block, true)
assert.equal(await readFile(internalPath, "utf8"), markdown)
}

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
const parentWorker = harness()
parentWorker.setParent("parent.jsonl")
const markedWorker = harness()
markedWorker.setParent("parent.jsonl")
markedWorker.ctx.systemPrompt = '<active_agent name="worker"/>'
for (const h of [worker, markedWorker]) {
  await h.command("10")
  assert.equal(h.branch().some(e => e.customType === "unattended-handoff"), false)
}
await parentWorker.command("10")
assert.ok(parentWorker.branch().some(e => e.customType === "unattended-handoff"), "a forked coordinator may explicitly opt in")
parentWorker.set(0, 150_000)
parentWorker.fire("session_start")
assert.equal(parentWorker.sent.length, 1, "a forked coordinator retains handoff threshold enforcement")
assert.deepEqual(parentWorker.toolCall("bash", { command: "fork threshold" }).block, true)

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
  // Real runner events, including rejected/aborted preparation and consumed steering/follow-up input.
  let fixtureId = 0
  async function interactiveFixture(compactions: number, run: (fixture: any) => Promise<void>, hooks: any = {}) {
    const provider = `interactive-test-${++fixtureId}`
    let requests = 0
    let fixture: any
    const events: any[] = []
    const errors: any[] = []
    modelRuntime.registerProvider(provider, { api: `${provider}-api`, apiKey: "not-a-real-key", baseUrl: "http://invalid.invalid",
      models: [{ id: "mock", name: "Mock", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 1_000_000, maxTokens: 1000 }],
      streamSimple: (model: any, context: any) => {
        assert.ok(++requests <= 6, "unbounded interactive continuation")
        const content = hooks.respond(requests, context)
        const toolUse = content.some((part: any) => part.type === "toolCall")
        const message = { role: "assistant", content, api: model.api, provider, model: model.id,
          usage: { input: 10, output: 10, cacheRead: 0, cacheWrite: 0, totalTokens: 20, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
          stopReason: toolUse ? "toolUse" : "stop", timestamp: Date.now() }
        const stream = createAssistantMessageEventStream()
        stream.push({ type: "start", partial: message })
        stream.push({ type: "done", reason: message.stopReason, message })
        return stream
      } })
    const manager = sdk.SessionManager.create(repo, sdkSessions)
    for (let i = 0; i < compactions; i++) manager.appendCompaction("Fixture compaction", null, 100)
    const loader = new sdk.DefaultResourceLoader({ cwd: repo, agentDir: directory, settingsManager: settings,
      noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true, systemPrompt: hooks.systemPrompt,
      extensionFactories: [handoff, (pi: any) => {
        pi.registerTool({ name: "probe", label: "Probe", description: "Local no-op", parameters: { type: "object", properties: {} },
          execute: async () => ({ content: [{ type: "text", text: "probe executed" }], details: {} }) })
        for (const name of ["before_agent_start", "input", "message_start", "tool_call", "tool_result", "tool_execution_end", "session_tree"]) {
          pi.on(name, (event: any, ctx: any) => { events.push(event); if (name === "tool_call") return hooks.toolCall?.(event, ctx) })
        }
        pi.on("context", async () => { await hooks.beforeRequest?.(requests + 1, fixture) })
      }] })
    await loader.reload()
    const { session } = await sdk.createAgentSession({ cwd: repo, agentDir: directory, resourceLoader: loader, sessionManager: manager,
      settingsManager: settings, modelRuntime, model: modelRuntime.getModel(provider, "mock"), tools: ["handoff_checkpoint", "probe", "write"] })
    fixture = { session, manager, events, errors,
      pending: () => manager.getBranch().findLast((e: any) => e.type === "custom" && e.customType === "compaction-handoff")?.data,
      approvals: () => manager.getBranch().filter((e: any) => e.type === "custom" && e.customType === "compaction-handoff-approved"),
      custom: () => session.sendCustomMessage({ customType: "fixture", content: "Continue", display: false }, { triggerTurn: true }) }
    try {
      await session.bindExtensions({ mode: "rpc", uiContext: { notify() {} } as any, onError: (error: any) => errors.push(error) })
      await run(fixture)
      assert.equal(manager.getBranch().some((e: any) => e.customType === "unattended-handoff"), false, "interactive input never enables unattended")
    } finally { session.dispose() }
  }
  const call = (id: string, name = "handoff_checkpoint") => ({ type: "toolCall", id, name, arguments: name === "handoff_checkpoint" ? { markdown: "# Immutable interactive checkpoint" } : {} })
  const finished = [{ type: "text", text: "Finished." }]
  for (const rejection of ["deny", "throw", "abort"]) {
    await interactiveFixture(5, async (f: any) => {
      await f.custom()
      if (rejection === "abort") await f.custom() // A cancelled run must release its reservation before the next run.
      const ended = f.events.filter((e: any) => e.type === "tool_execution_end")
      assert.equal(ended.find((e: any) => e.toolCallId === "first").isError, true)
      assert.equal(f.events.some((e: any) => e.type === "tool_result" && e.toolCallId === "first"), false, "Pi skips tool_result on pre-execution rejection")
      assert.equal(ended.find((e: any) => e.toolCallId === "retry").isError, false, `${rejection}: checkpoint retry must execute`)
      assert.equal(ended.find((e: any) => e.toolCallId === "duplicate").isError, true, "parallel duplicate stays blocked")
      assert.equal(ended.find((e: any) => e.toolCallId === "after-write").isError, true, "ordinary tools stay gated after publishing")
      assert.equal(await readFile(f.pending().checkpointPath, "utf8"), "# Immutable interactive checkpoint")
      assert.equal(await mode(f.pending().checkpointPath), 0o600)
      assert.equal(await mode(dirname(f.pending().checkpointPath)), 0o700)
      assert.deepEqual(await readdir(dirname(f.pending().checkpointPath)), [basename(f.pending().checkpointPath)])
      assert.equal(f.manager.getBranch().filter((e: any) => e.customType === "compaction-handoff-written").length, 1)
      assert.match(ended.find((e: any) => e.toolCallId === "first").result.content[0].text, rejection === "abort" ? /aborted/i : /fixture permission/)
      assert.deepEqual(f.errors, [])
    }, {
      respond: (n: number) => n === 1 ? [call("first")] : n === 2 ? [call("retry"), call("duplicate")] : n === 3 ? [call("after-write", "probe")] : finished,
      toolCall: (event: any, ctx: any) => {
        if (event.toolCallId !== "first") return
        if (rejection === "abort") { ctx.abort(); return }
        if (rejection === "throw") throw new Error("fixture permission hook failure")
        return { block: true, reason: "fixture permission denial" }
      },
    })
  }
  console.log("Installed Pi checkpoint retry proof passed: later permission denial, hook failure, preparation abort, parallel duplicate guard, immutable private publish")

  let legacyWritePath: string
  await interactiveFixture(5, async (f: any) => {
    await f.custom()
    const resultIndex = f.events.findIndex((e: any) => e.type === "tool_result" && e.toolCallId === "legacy-write")
    const endIndex = f.events.findIndex((e: any) => e.type === "tool_execution_end" && e.toolCallId === "legacy-write")
    assert.ok(resultIndex >= 0 && endIndex > resultIndex, "installed Pi emits successful legacy tool_result before terminal cleanup")
    assert.equal(f.events[endIndex].isError, false)
    const receipts = f.manager.getBranch().filter((e: any) => e.customType === "compaction-handoff-written")
    assert.equal(receipts.length, 1, "terminal cleanup must not lose the legacy write receipt")
    assert.equal(receipts[0].data.checkpointPath, legacyWritePath)
    assert.equal(f.events.find((e: any) => e.type === "tool_execution_end" && e.toolCallId === "legacy-overwrite").isError, true)
    assert.equal(await readFile(legacyWritePath, "utf8"), "# Legacy checkpoint")
    assert.equal(await mode(dirname(legacyWritePath)), 0o700)
    assert.deepEqual(f.errors, [])
  }, {
    beforeRequest: (n: number, f: any) => { if (n === 1) legacyWritePath = f.pending().checkpointPath },
    respond: (n: number) => n <= 2 ? [{ type: "toolCall", id: n === 1 ? "legacy-write" : "legacy-overwrite", name: "write", arguments: { path: legacyWritePath, content: n === 1 ? "# Legacy checkpoint" : "# Must not overwrite" } }] : finished,
  })
  console.log("Installed Pi legacy-write ordering proof passed: tool_result receipt precedes terminal cleanup; second write blocked")

  for (const delivery of ["steer", "followUp", "prompt-steer", "prompt-followUp"]) {
    let requestedAfterUser = false
    await interactiveFixture(4, async (f: any) => {
      await f.session.prompt("Begin bounded work")
      assert.equal(f.events.filter((e: any) => e.type === "before_agent_start").length, 1, "queued input is consumed within the same run")
      const consumed = f.events.filter((e: any) => e.type === "message_start" && e.message.role === "user").map((e: any) => e.message.content[0].text)
      assert.deepEqual(consumed, ["Begin bounded work", "Extension continuation", "Continue in this session"])
      const ended = f.events.filter((e: any) => e.type === "tool_execution_end")
      for (const id of ["threshold", "extension-only"]) assert.equal(ended.find((e: any) => e.toolCallId === id).isError, true)
      assert.equal(ended.find((e: any) => e.toolCallId === "user-approved").isError, false, `${delivery}: consumed user input must release gate`)
      assert.equal(f.approvals().length, 1)
      assert.equal(f.approvals()[0].data.checkpointPath, f.pending().checkpointPath)
      assert.deepEqual(f.errors, [])
    }, {
      beforeRequest: async (n: number, f: any) => {
        if (n === 1) f.manager.appendCompaction("Threshold reached after initial user input", null, 100)
        if (n === 2) {
          assert.equal(f.approvals().length, 0, "the triggering user prompt predates the pending allocation")
          await f.session.sendCustomMessage({ customType: "extension-fixture", content: "Continue", display: false }, { deliverAs: "steer" })
          await f.session.sendUserMessage("Extension continuation", { deliverAs: "steer" })
        }
        if (n === 3) {
          assert.equal(f.approvals().length, 0, "consumed custom and extension-origin user messages cannot approve")
          if (delivery.startsWith("prompt-")) await f.session.prompt("Continue in this session", { source: "rpc", streamingBehavior: delivery.slice(7) })
          else await f.session[delivery]("Continue in this session")
        }
      },
      respond: (n: number, context: any) => {
        if (n === 1) return [call("threshold", "probe")]
        if (n === 2) return [call("extension-only", "probe")]
        // Pi may drain steering one message at a time; request work only after the real user message reaches the model.
        if (!requestedAfterUser && context.messages.some((m: any) => m.role === "user" && m.content[0]?.text === "Continue in this session")) {
          requestedAfterUser = true
          return [call("user-approved", "probe")]
        }
        return finished
      },
    })
  }
  for (const source of ["interactive", "rpc", "extension", "custom"]) {
    await interactiveFixture(5, async (f: any) => {
      if (source === "extension") await f.session.sendUserMessage("Extension continuation")
      else if (source === "custom") await f.custom()
      else await f.session.prompt("Continue in this session", { source })
      const realUser = source === "interactive" || source === "rpc"
      assert.equal(f.events.find((e: any) => e.type === "tool_execution_end").isError, !realUser, `idle ${source} approval provenance`)
      assert.equal(f.approvals().length, realUser ? 1 : 0)
      assert.deepEqual(f.errors, [])
    }, { respond: (n: number) => n === 1 ? [call("idle", "probe")] : finished })
  }
  console.log("Installed Pi user-input proof passed: one start per run, consumed steering/follow-up via direct and prompt APIs, idle interactive/RPC approval, custom/extension rejection, no unattended activation")

  await interactiveFixture(5, async (f: any) => {
    await f.session.prompt("Continue worker task", { source: "rpc" })
    assert.equal(f.pending(), undefined, "worker prompts cannot allocate a coordinator handoff")
    assert.equal(f.approvals().length, 0)
    assert.equal(f.events.find((e: any) => e.type === "tool_execution_end" && e.toolCallId === "worker-checkpoint").isError, true)
    assert.equal(f.events.find((e: any) => e.type === "tool_execution_end" && e.toolCallId === "worker-probe").isError, false, "worker's own work is not gated or cancelled")
    assert.deepEqual(f.errors, [])
  }, { systemPrompt: '<active_agent name="implementer"/>',
    respond: (n: number) => n === 1 ? [call("worker-checkpoint")] : n === 2 ? [call("worker-probe", "probe")] : finished })

  await interactiveFixture(5, async (f: any) => {
    const allocation = f.manager.getBranch().findLast((e: any) => e.customType === "compaction-handoff")
    await f.session.prompt("Continue in this session")
    const approvedLeaf = f.manager.getLeafId()
    const path = f.pending().checkpointPath
    assert.equal(f.approvals().length, 1)
    assert.equal((await f.session.navigateTree(allocation.id, { summarize: false })).cancelled, false)
    assert.equal(f.pending().checkpointPath, path)
    assert.equal(f.approvals().length, 0, "actual tree navigation drops an abandoned approval")
    await f.custom()
    assert.equal(f.approvals().length, 0, "custom run on unapproved branch cannot approve")
    assert.equal((await f.session.navigateTree(approvedLeaf, { summarize: false })).cancelled, false)
    assert.equal(f.approvals().length, 1, "returning to approved branch restores only its receipt")
    await f.custom()
    const ended = f.events.filter((e: any) => e.type === "tool_execution_end")
    assert.deepEqual(ended.map((e: any) => e.isError), [false, true, false])
    assert.equal(f.events.filter((e: any) => e.type === "session_tree").length, 2)
    assert.deepEqual(f.errors, [])
  }, { respond: (n: number) => n % 2 ? [call(`navigation-${n}`, "probe")] : finished })
  console.log("Installed Pi worker/navigation proof passed: no worker allocation/approval/cancellation; actual tree navigation restores branch-specific approval")
  assert.equal(await readFile(legacy, "utf8"), "legacy shared handoff bytes\n", "legacy tasks/handoff.md stays byte-identical")
  assert.deepEqual(await readdir(dirname(legacy)), ["handoff.md"])
  console.log("Compaction handoff and unattended state checks passed")
} finally {
  await rm(directory, { recursive: true, force: true })
  await assert.rejects(readFile(directory), { code: "ENOENT" })
  console.log(`Verified temporary directory removed: ${directory}`)
}
TS
