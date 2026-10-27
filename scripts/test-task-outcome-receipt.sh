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
const { default: extension, validateReceipt } = await jiti.import(join(process.cwd(), "home/private_dot_pi/private_agent/private_extensions/task-outcome-receipt.ts"))

const good = { taskId: "task-12:a", outcome: "accepted", model: "anthropic/claude-sonnet-4.5", effort: "medium", checkArtifact: "scripts/test-x.sh" }
assert.deepEqual(validateReceipt(good), good)
assert.equal(validateReceipt({ ...good, outcome: "reworked", effort: "unknown" }).effort, "unknown")
for (const bad of [
  { outcome: "completed" }, { taskId: "" }, { taskId: "a".repeat(129) }, { taskId: "a b" }, { model: "m$" }, { model: "x".repeat(129) },
  { effort: "ultra" }, { effort: "" }, { checkArtifact: "" }, { checkArtifact: "a".repeat(301) }, { checkArtifact: "it passed fine" }, { checkArtifact: "a\nb" },
]) assert.throws(() => validateReceipt({ ...good, ...bad }), Error, JSON.stringify(bad))

let tool: any
const entries: unknown[] = []
extension({ registerTool: (t: unknown) => { tool = t }, appendEntry: (type: string, data: unknown) => entries.push([type, data]) } as never)
const ctx = (prompt: string) => ({ getSystemPrompt: () => prompt })
await assert.rejects(() => tool.execute("1", good, undefined, undefined, ctx('x <active_agent name="implementer"/>')), /Workers cannot/)
assert.equal(entries.length, 0)
await assert.rejects(() => tool.execute("1", { ...good, effort: "ultra" }, undefined, undefined, ctx("coordinator")), /effort/)
assert.equal(entries.length, 0)
await tool.execute("1", good, undefined, undefined, ctx("coordinator"))
assert.deepEqual(entries, [["task-outcome-receipt", good]])
console.log("Task outcome receipt checks passed")
TS
