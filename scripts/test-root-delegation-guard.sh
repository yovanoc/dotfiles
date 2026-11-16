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
  "files": ["$PWD/home/private_dot_pi/private_agent/private_extensions/root-delegation-guard.ts"] }
JSON
tsc -p "$types/tsconfig.json"
echo "Strict TypeScript check passed against installed Pi declarations"

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import guard, { createRootDelegationGuard, diskReason, MIN_FREE_BYTES } from "./home/private_dot_pi/private_agent/private_extensions/root-delegation-guard.ts"

const GiB = 1024 ** 3
const fs = (bytes: number) => () => ({ bavail: bytes / 4096, bsize: 4096 })
type Handler = (event: any, ctx: any) => any
function load(deps: Parameters<typeof createRootDelegationGuard>[1]) {
  let handler!: Handler, command: any
  createRootDelegationGuard({ on: (_n: string, cb: Handler) => { handler = cb }, registerCommand: (_n: string, o: unknown) => { command = o } } as never, deps)
  return { handler, command }
}
const root = { cwd: "/work", getSystemPrompt: () => "coordinator" }
const worker = { cwd: "/work", getSystemPrompt: () => '<active_agent name="implementer"/>' }
const call = (toolName: string, input: object = {}) => ({ toolName, input })

// Root bash is blocked by default; workers and other tools are unaffected.
const env: NodeJS.ProcessEnv = {}
const a = load({ statfs: fs(100 * GiB), env })
assert.equal(a.handler(call("bash", { command: "ls", timeout: 5 }), root).block, true)
assert.match(a.handler(call("bash"), root).reason, /delegate/)
assert.equal(a.handler(call("bash"), worker), undefined)
assert.equal(a.handler(call("read"), root), undefined)
for (const tool of ["fast_task_ready", "get_subagent_result", "TaskCreate", "quota_status", "task_outcome", "codemode"]) assert.equal(a.handler(call(tool), root), undefined, tool)

// Escape hatch: env var, then the /root-bash command (session-only, off by default).
env.PI_ROOT_BASH = "1"
assert.equal(a.handler(call("bash"), root), undefined)
env.PI_ROOT_BASH = "0"
assert.equal(a.handler(call("bash"), root).block, true)
const notes: string[] = []
const ui = { ctx: { ui: { notify: (m: string) => notes.push(m) } } }
await a.command.handler("on", ui.ctx)
assert.equal(a.handler(call("bash"), root), undefined)
await a.command.handler("off", ui.ctx)
assert.equal(a.handler(call("bash"), root).block, true)
await a.command.handler("bogus", ui.ctx)
assert.match(notes.at(-1)!, /Usage/)
await a.command.handler("status", ui.ctx)
assert.match(notes.at(-1)!, /blocked/)

// Disk guard: injected statfs below and above 5 GiB.
const low = load({ statfs: fs(3.2 * GiB), env: {} })
for (const input of [{}, { resume: "" }]) {
  const r = low.handler(call("Agent", { prompt: "x", ...input }), root)
  assert.equal(r.block, true)
  assert.match(r.reason, /3\.2 GiB free/)
  assert.match(r.reason, /ENOSPC/)
}
assert.equal(low.handler(call("fast_task_dispatch"), root).block, true)
assert.equal(low.handler(call("fast_task_dispatch"), worker), undefined)
assert.equal(low.handler(call("Agent", { resume: "agent-1" }), root), undefined)
assert.equal(low.handler(call("fast_task_ready"), root), undefined)
assert.equal(low.handler(call("get_subagent_result"), root), undefined)
const high = load({ statfs: fs(5 * GiB), env: {} })
assert.equal(high.handler(call("fast_task_dispatch"), root), undefined)
assert.equal(high.handler(call("Agent", { prompt: "x" }), root), undefined)
assert.equal(diskReason("/work", fs(MIN_FREE_BYTES - 4096)) !== undefined, true)
assert.equal(diskReason("/work", () => { throw new Error("EACCES") }), undefined)
// Real statfs on a real directory returns a number-backed result and does not throw.
assert.ok(diskReason(process.cwd()) === undefined || /ENOSPC/.test(diskReason(process.cwd())!))
// Default export wires the same handlers.
let wired = 0
guard({ on: () => { wired++ }, registerCommand: () => { wired++ } } as never)
assert.equal(wired, 2)
console.log("Root delegation guard checks passed")
TS
