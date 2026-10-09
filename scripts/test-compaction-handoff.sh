#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import handoff, { handoffNotice } from "./home/private_dot_pi/private_agent/private_extensions/compaction-handoff.ts"

assert.equal(handoffNotice(4), undefined)
assert.match(handoffNotice(5) ?? "", /compacted 5 times/)

type Handler = (event: unknown, ctx: unknown) => void
let handler: Handler | undefined
const sent: unknown[] = [], notes: string[] = []
handoff({ on: (_name: string, cb: Handler) => { handler = cb }, sendMessage: (m: unknown) => { sent.push(m) } } as never)
const ctx = (hasUI: boolean, n: number) => ({
  hasUI,
  ui: { notify: (m: string) => { notes.push(m) } },
  sessionManager: { getBranch: () => [...Array(n).fill({ type: "compaction" }), { type: "message" }] },
})
handler!({}, ctx(true, 4))
handler!({}, ctx(false, 6))
assert.equal(sent.length + notes.length, 0)
handler!({}, ctx(true, 5))
assert.equal(sent.length, 1)
assert.equal(notes.length, 1)
console.log("Compaction handoff checks passed")
TS
