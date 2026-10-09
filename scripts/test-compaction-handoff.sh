#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unset NODE_PATH

bun --no-install - <<'TS'
import assert from "node:assert/strict"
import handoff, { handoffNotice } from "./home/private_dot_pi/private_agent/private_extensions/compaction-handoff.ts"

assert.equal(handoffNotice(4, "/repo"), undefined)
assert.match(handoffNotice(5, "/repo") ?? "", /compacted 5 times/)
assert.match(handoffNotice(5, "/repo") ?? "", /Work in \/repo\. Read \/repo\/tasks\/handoff\.md/)

type Handler = (event: unknown, ctx: unknown) => void
let handler: Handler | undefined
const sent: unknown[] = [], notes: string[] = []
handoff({ on: (_name: string, cb: Handler) => { handler = cb }, sendMessage: (m: unknown, o: unknown) => { sent.push(o) } } as never)
const ctx = (hasUI: boolean, n: number) => ({
  hasUI,
  cwd: "/repo",
  ui: { notify: (m: string) => { notes.push(m) } },
  sessionManager: { getBranch: () => [...Array(n).fill({ type: "compaction" }), { type: "message" }] },
})
handler!({}, ctx(true, 4))
handler!({}, ctx(false, 6))
assert.equal(sent.length + notes.length, 0)
handler!({}, ctx(true, 5))
assert.deepEqual(sent, [{ deliverAs: "steer" }])
assert.equal(notes.length, 1)
console.log("Compaction handoff checks passed")
TS
