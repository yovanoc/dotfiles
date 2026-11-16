#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

export PI_RUNTIME="${PI_RUNTIME:-$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent}"

# Strict type check against the installed Pi declarations.
# Owned temporary resource: this test owns $types and removes it on every exit.
types="$(mktemp -d)"
trap 'rm -r "$types"' EXIT
cat >"$types/tsconfig.json" <<JSON
{ "compilerOptions": { "strict": true, "noEmit": true, "target": "es2023", "lib": ["es2023"], "module": "esnext", "moduleResolution": "bundler", "skipLibCheck": true,
    "types": ["node"], "typeRoots": ["$PI_RUNTIME/node_modules/@types"],
    "paths": { "@earendil-works/pi-coding-agent": ["$PI_RUNTIME/dist/index.d.ts"] } },
  "files": ["$PWD/home/private_dot_pi/private_agent/private_extensions/task-graph-check.ts"] }
JSON
tsc -p "$types/tsconfig.json"
echo "Strict TypeScript check passed against installed Pi declarations"

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import extension, { STALE_AFTER_PASSES, TaskGraph, workerLiveness } from "./home/private_dot_pi/private_agent/private_extensions/task-graph-check.ts"

assert.equal(STALE_AFTER_PASSES, 3)
const dead = () => false

// Pure ledger: in_progress without a worker, stale after 3 completion passes, dependency named without a link.
const g = new TaskGraph()
g.created("1", { description: "split part", metadata: {} })
g.created("2", { description: "Runs after #1 lands", metadata: {} })
g.created("3", { description: "plain", metadata: { dependsOn: ["1"] } })
g.created("4", { description: "linked via parent", metadata: { parentTaskId: "1", dependsOn: ["1"] } })
g.updated({ taskId: "1", status: "in_progress" })
let w = g.warnings(dead).join("|")
assert.match(w, /#1 in_progress without a live worker/)
assert.match(w, /#2, #3 names a dependency but has no parent or blockedBy\/blocks link/)
assert.doesNotMatch(w, /#4/)
assert.deepEqual(g.warnings(dead), [], "warnings are reported once")
g.updated({ taskId: "2", addBlockedBy: ["1"] })
g.updated({ taskId: "3", metadata: { parentTaskId: "1" } })
assert.deepEqual(g.warnings(() => true), [])
g.pass = 2
assert.deepEqual(g.warnings(() => true), [])
g.pass = 3
w = g.warnings(() => true).join("|")
assert.match(w, /#1, #2, #3, #4 stale: no update in 3 worker completions/)
g.updated({ taskId: "1", status: "completed" })
g.updated({ taskId: "2", status: "completed" })
g.updated({ taskId: "3", status: "deleted" })
assert.deepEqual(g.warnings(() => true), [], "completed and deleted tasks are not judged")
assert.equal(g.warnings(() => undefined).some(x => /live worker/.test(x)), false, "unverifiable liveness is not flagged")

// Liveness: ID from owner / metadata / fast-task-dispatch entry, checked against the subagents manager.
const manager = { getRecord: (id: string) => id === "w1" ? { status: "running" } : id === "w2" ? { status: "completed" } : undefined }
const entry = (data: object) => ({ type: "custom", customType: "fast-task-dispatch", data })
const live = workerLiveness([entry({ taskId: "9", workerId: "w1" }), entry({ taskId: "8", workerId: "w2" }), entry({ taskId: "7", state: "submitted" })], manager)
assert.equal(live({ id: "1", owner: "w1", metadata: {} }), true)
assert.equal(live({ id: "1", metadata: { agentId: "w1" } }), true)
assert.equal(live({ id: "9", metadata: {} }), true)
assert.equal(live({ id: "8", metadata: {} }), false)
assert.equal(live({ id: "1", metadata: {} }), false)
assert.equal(live({ id: "7", metadata: {} }), undefined, "dispatch in flight")
assert.equal(workerLiveness([], undefined)({ id: "1", owner: "w1", metadata: {} }), undefined)

// Extension wiring: tool_result warnings, nested calls recorded but not judged, completion notification.
const handlers: Record<string, (e: any, c: any) => any> = {}, bus: Record<string, () => void> = {}
extension({ on: (n: string, cb: any) => { handlers[n] = cb }, events: { on: (n: string, cb: () => void) => { bus[n] = cb; return () => { delete bus[n] } } } } as never)
const notes: string[] = []
const ctx = { getSystemPrompt: () => "coordinator", sessionManager: { getBranch: () => [] }, ui: { notify: (m: string) => notes.push(m) } }
handlers.session_start({ reason: "startup" }, ctx)
const text = (t: string) => [{ type: "text", text: t }]
const result = (toolName: string, input: object, t: string, extra: object = {}) => handlers.tool_result({ toolName, input, content: text(t), isError: false, ...extra }, ctx)
assert.equal(result("TaskCreate", { subject: "a", description: "work" }, "Task #1 created successfully: a"), undefined)
const r = result("TaskCreate", { subject: "b", description: "blocked by #1" }, "Task #2 created successfully: b")
assert.match(r.content.at(-1).text, /Task graph warning: #2 names a dependency/)
assert.equal(result("TaskUpdate", { taskId: "1", status: "in_progress" }, "Updated task #1 status", { parentToolCallId: "p" }), undefined)
assert.match(result("TaskUpdate", { taskId: "1", status: "in_progress" }, "Updated task #1 status").content.at(-1).text, /#1 in_progress without a live worker/)
assert.equal(result("TaskUpdate", { taskId: "9", status: "completed" }, "Task #9 not found"), undefined)
assert.equal(handlers.tool_result({ toolName: "bash", input: {}, content: text("x"), isError: false }, ctx), undefined)
const workerCtx = { ...ctx, getSystemPrompt: () => '<active_agent name="w"/>' }
assert.equal(handlers.tool_result({ toolName: "TaskCreate", input: { description: "after #1" }, content: text("Task #5 created successfully: x"), isError: false }, workerCtx), undefined)
for (let i = 0; i < 3; i++) bus["subagents:completed"]()
assert.match(notes.at(-1)!, /Task graph: .*stale/)
handlers.session_shutdown({}, ctx)
assert.equal(Object.keys(bus).length, 0)
console.log("Task graph check passed")
TS
