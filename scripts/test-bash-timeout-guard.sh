#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import guard, { validateBashTimeout } from "./home/private_dot_pi/private_agent/private_extensions/bash-timeout-guard.ts"

const maxEnv = "PI_BASH_MAX_TIMEOUT_SECONDS"
for (const timeout of [undefined, null, 0, -1, NaN, Infinity, true, false, "120"]) {
  assert.ok(validateBashTimeout(timeout), `expected ${String(timeout)} to be rejected`)
}
assert.equal(validateBashTimeout(120), undefined)
assert.equal(validateBashTimeout(3600), undefined)
assert.match(validateBashTimeout(30000) ?? "", /3600 seconds/)
assert.equal(validateBashTimeout(7200, "7200"), undefined)
assert.match(validateBashTimeout(3601, "invalid") ?? "", /3600 seconds/)

type Event = { toolName: string; input: { timeout?: unknown } }
type Handler = (event: Event) => unknown
process.env[maxEnv] = "invalid"
let handler: Handler | undefined
guard({ on: (_name: string, callback: Handler) => { handler = callback } } as never)
assert.equal(handler!({ toolName: "bash", input: { timeout: 120 } }), undefined)
assert.equal(handler!({ toolName: "bash", input: { timeout: 3600 } }), undefined)
assert.equal((handler!({ toolName: "bash", input: { timeout: 30000 } }) as { block?: boolean }).block, true)
assert.equal(handler!({ toolName: "read", input: { timeout: 30000 } }), undefined)

process.env[maxEnv] = "7200"
let overrideHandler: Handler | undefined
guard({ on: (_name: string, callback: Handler) => { overrideHandler = callback } } as never)
assert.equal(overrideHandler!({ toolName: "bash", input: { timeout: 7200 } }), undefined)
console.log("Bash timeout guard checks passed")
TS
