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
const jiti = createJiti(join(process.cwd(), "scripts/test-task-outcome-receipt.sh"), {
  moduleCache: false, fsCache: false,
  alias: { "@earendil-works/pi-coding-agent": join(runtime, "dist/index.js"), typebox: join(runtime, "node_modules/typebox/build/index.mjs") },
})
const { default: extension, validateReceipt, missingReceipts } = await jiti.import(join(process.cwd(), "home/private_dot_pi/private_agent/private_extensions/task-outcome-receipt.ts"))

const good = { taskId: "task-12:a", outcome: "accepted", model: "anthropic/claude-sonnet-4.5", effort: "medium", checkArtifact: "scripts/test-x.sh" }
assert.deepEqual(validateReceipt(good), good)
assert.equal(validateReceipt({ ...good, outcome: "reworked", effort: "unknown" }).effort, "unknown")
for (const bad of [
  { outcome: "completed" }, { taskId: "" }, { taskId: "a".repeat(129) }, { taskId: "a b" }, { model: "m$" }, { model: "x".repeat(129) },
  { effort: "ultra" }, { effort: "" }, { checkArtifact: "" }, { checkArtifact: "a".repeat(301) }, { checkArtifact: "it passed fine" }, { checkArtifact: "a\nb" },
]) assert.throws(() => validateReceipt({ ...good, ...bad }), Error, JSON.stringify(bad))

const linked = { ...good, boardTaskId: "board-1", attemptId: "attempt-2", phase: "review", parentTaskId: "board-0", reviewerWorkerId: "worker-2", coordinatorReportedDurationMs: 42 }
assert.deepEqual(validateReceipt({ ...linked, prompt: "SECRET prompt" }), linked)
for (const bad of [{ boardTaskId: "x y" }, { attemptId: 3 }, { phase: "done" }, { parentTaskId: "" }, { reviewerWorkerId: "bad!" }, { coordinatorReportedDurationMs: -1 }, { coordinatorReportedDurationMs: 0.5 }, { coordinatorReportedDurationMs: Number.MAX_SAFE_INTEGER + 1 }]) {
  assert.throws(() => validateReceipt({ ...good, ...bad }))
}

let tool: any
const handlers: Record<string, (event: any, ctx: any) => void> = {}
const entries: any[] = []
extension({ registerTool: (t: unknown) => { tool = t }, on: (n: string, cb: any) => { handlers[n] = cb }, appendEntry: (type: string, data: unknown) => entries.push([type, data]) } as never)
const statuses: (string | undefined)[] = [], notes: string[] = []
const ctx = (prompt: string) => ({
  getSystemPrompt: () => prompt,
  sessionManager: { getBranch: () => entries.map(([customType, data]) => ({ type: "custom", customType, data })) },
  ui: { setStatus: (_k: string, t?: string) => statuses.push(t), notify: (m: string) => notes.push(m) },
})
const coord = ctx("coordinator")
for (const reason of ["startup", "reload"]) {
  handlers.session_start({ reason }, coord)
  const [type, evidence] = entries.at(-1)
  assert.equal(type, "task-outcome-activation")
  assert.equal(evidence.schemaVersion, 1)
  assert.equal(evidence.extensionVersion, 1)
  assert.match(evidence.extensionSha256, /^[a-f0-9]{64}$/)
  assert.ok(evidence.coordinatorPolicySha256 === null || /^[a-f0-9]{64}$/.test(evidence.coordinatorPolicySha256))
  assert.equal(evidence.source, reason)
  assert.ok(!Number.isNaN(Date.parse(evidence.timestamp)))
}
handlers.session_start({ reason: "SECRET" }, coord)
assert.equal(entries.at(-1)[1].source, "unknown")
const count = entries.length
handlers.session_start({ reason: "startup" }, ctx('<active_agent name="w"/>'))
assert.equal(entries.length, count)
assert.doesNotMatch(JSON.stringify(entries), /SECRET/)
entries.length = 0
await tool.execute("1", { ...linked, prompt: "SECRET" }, undefined, undefined, coord)
assert.deepEqual(entries.at(-1), ["task-outcome-receipt", linked])
assert.doesNotMatch(JSON.stringify(entries), /SECRET/)
entries.length = 0
await assert.rejects(() => tool.execute("1", good, undefined, undefined, ctx('x <active_agent name="implementer"/>')), /Workers cannot/)
assert.equal(entries.length, 0)
await assert.rejects(() => tool.execute("1", { ...good, effort: "ultra" }, undefined, undefined, coord), /effort/)
assert.equal(entries.length, 0)

// Missing-receipt advisory: keyed on structured worker IDs (subagents:record), never TaskUpdate list IDs.
const workerRec = (id: string, status: string) => entries.push(["subagents:record", { id, status, result: "SECRET raw text" }])
const fire = (name: string, c = coord) => handlers[name]({}, c)
const missing = () => missingReceipts(ctx("").sessionManager.getBranch())
// Four distinct completions must remain visible without producing four popups.
for (const id of ["w-1", "w-2", "w-3", "w-4"]) { workerRec(id, "completed"); fire("turn_end") }
assert.deepEqual(missing(), ["w-1", "w-2", "w-3", "w-4"])
assert.equal(notes.length, 0, "four terminal workers must produce no notifications")
assert.match(statuses.at(-1) ?? "", /^4 .*receipt/i)
entries.length = 0; statuses.length = 0; notes.length = 0
// TaskUpdate completion with a distinct list ID is ignored entirely: no handler, no entry, no advisory.
assert.equal(handlers.tool_result, undefined)
fire("turn_end")
assert.equal(notes.length, 0)
assert.equal(statuses.at(-1), undefined)
// Running/queued workers never appear; only terminal records do.
workerRec("agent-run", "running"); workerRec("agent-q", "queued")
fire("turn_end")
assert.deepEqual(missing(), [])
assert.equal(notes.length, 0)
// Completed worker with list task "3" still unrelated: the worker ID is tracked.
workerRec("w-a1", "completed")
fire("turn_end")
assert.deepEqual(missing(), ["w-a1"])
assert.equal(notes.length, 0)
assert.match(statuses.at(-1) ?? "", /^1 .*receipt/i)
fire("turn_end"); fire("agent_end")
assert.equal(notes.length, 0)
workerRec("w-a1", "completed") // resumed worker finishing again: same ID, still one missing receipt
fire("turn_end")
assert.deepEqual(missing(), ["w-a1"])
assert.equal(notes.length, 0)
workerRec("w-err", "error"); workerRec("w-stop", "stopped"); workerRec("w-abort", "aborted"); workerRec("w-steer", "steered")
fire("agent_end")
assert.deepEqual(missing(), ["w-a1", "w-err", "w-stop", "w-abort", "w-steer"])
assert.equal(notes.length, 0)
assert.match(statuses.at(-1) ?? "", /^5 .*receipt/i)
// Worker sessions never advise.
workerRec("w-x", "completed")
const statusCount = statuses.length
fire("turn_end", ctx('x <active_agent name="w"/>'))
assert.equal(statuses.length, statusCount)
assert.equal(notes.length, 0)
// Unrelated receipt does not clear others; matching worker-ID receipt does.
await tool.execute("1", { ...good, taskId: "3" }, undefined, undefined, coord) // list ID, not a worker
assert.deepEqual(missing(), ["w-a1", "w-err", "w-stop", "w-abort", "w-steer", "w-x"])
await tool.execute("1", { ...good, taskId: "w-a1" }, undefined, undefined, coord)
assert.deepEqual(missing(), ["w-err", "w-stop", "w-abort", "w-steer", "w-x"])
assert.match(statuses.at(-1) ?? "", /^5 .*receipt/i)
// Rebuild from persisted branch: status restored, no repeated notices.
fire("session_start")
assert.match(statuses.at(-1) ?? "", /^5 .*receipt/i)
fire("session_tree"); fire("turn_end")
assert.equal(notes.length, 0)
// Over-long or invalid worker IDs are ignored.
workerRec("bad id", "completed"); workerRec(123 as never, "completed")
assert.deepEqual(missing(), ["w-err", "w-stop", "w-abort", "w-steer", "w-x"])
for (const id of ["w-err", "w-stop", "w-abort", "w-steer", "w-x"]) await tool.execute("1", { ...good, taskId: id }, undefined, undefined, coord)
assert.equal(statuses.at(-1), undefined)
await tool.execute("1", { ...good, taskId: "never-terminal" }, undefined, undefined, coord)
assert.deepEqual(entries.at(-1), ["task-outcome-receipt", { ...good, taskId: "never-terminal" }])
// Branch switch: another branch without these records has nothing missing.
entries.length = 0
fire("session_tree")
assert.equal(statuses.at(-1), undefined)
assert.equal(notes.length, 0)
assert.doesNotMatch(statuses.join(" ") + notes.join(" "), /SECRET/)
console.log("Task outcome receipt checks passed")
TS
