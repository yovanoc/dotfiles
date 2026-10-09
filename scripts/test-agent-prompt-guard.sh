#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import guard, { gluedPromptReason } from "./home/private_dot_pi/private_agent/private_extensions/agent-prompt-guard.ts"

const glued = "OUTCOME:Quota-optimizeexistingEffect4.0.2cleanupengineinyoutube-triagewithoutdata-lossguardregression,wirepureminimum-movehelper.OWNEDFILESEXCLUSIVE:src/cleanup.tsandtest/cleanup-engine.test.tsONLY.Optionalnewtest/cleanup-quota.test.tsforboundedofflineactualproduction-statemockperformance/regression;donoteditotherfiles."
const plain = "OUTCOME: Quota-optimize the existing Effect cleanup engine in /Users/me/youtube-triage without any data-loss guard regression. OWNED FILES: src/cleanup.ts and test/cleanup-engine.test.ts only. CHECKS: bun test test/cleanup-engine.test.ts passes.\n".repeat(2)
assert.equal(gluedPromptReason("short glued text"), undefined)
assert.equal(gluedPromptReason(plain), undefined)
assert.match(gluedPromptReason(glued) ?? "", /rejected/)

type Handler = (event: { toolName: string; input: unknown }) => { block?: boolean } | undefined
let handler: Handler | undefined
guard({ on: (_name: string, cb: Handler) => { handler = cb } } as never)
assert.equal(handler!({ toolName: "bash", input: { command: glued } }), undefined)
assert.equal(handler!({ toolName: "Agent", input: { prompt: plain } }), undefined)
assert.equal(handler!({ toolName: "Agent", input: { prompt: glued } })?.block, true)
console.log("Agent prompt guard checks passed")
TS
