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
const jiti = createJiti(join(process.cwd(), "scripts/test-agent-prompt-guard.sh"), {
  moduleCache: false, fsCache: false,
  alias: { "@earendil-works/pi-coding-agent": join(runtime, "dist/index.js"), "@earendil-works/pi-ai/models": join(runtime, "node_modules/@earendil-works/pi-ai/dist/models.js") },
})
const { default: guard, gluedPromptReason, agentRouteReason, requiredToolsReason, resolveRole } = await jiti.import(join(process.cwd(), "home/private_dot_pi/private_agent/private_extensions/agent-prompt-guard.ts"))

const glued = "OUTCOME:Quota-optimizeexistingEffect4.0.2cleanupengineinyoutube-triagewithoutdata-lossguardregression,wirepureminimum-movehelper.OWNEDFILESEXCLUSIVE:src/cleanup.tsandtest/cleanup-engine.test.tsONLY.Optionalnewtest/cleanup-quota.test.tsforboundedofflineactualproduction-statemockperformance/regression;donoteditotherfiles."
const plain = "OUTCOME: Quota-optimize the existing Effect cleanup engine in /Users/me/youtube-triage without any data-loss guard regression. OWNED FILES: src/cleanup.ts and test/cleanup-engine.test.ts only. CHECKS: bun test test/cleanup-engine.test.ts passes.\n".repeat(2)
assert.equal(gluedPromptReason("short glued text"), undefined)
assert.equal(gluedPromptReason(plain), undefined)
assert.match(gluedPromptReason(glued) ?? "", /rejected/)

const ctx = { cwd: "/nonexistent-cwd" }
type Handler = (event: { toolName: string; input: unknown }, ctx: unknown) => { block?: boolean } | undefined
let handler: Handler | undefined
guard({ on: (_name: string, cb: Handler) => { handler = cb } } as never)
assert.equal(handler!({ toolName: "bash", input: { command: glued } }, ctx), undefined)
assert.equal(handler!({ toolName: "Agent", input: { prompt: plain } }, ctx), undefined)
assert.equal(handler!({ toolName: "Agent", input: { prompt: glued } }, ctx)?.block, true)

// Route preflight against a synthetic registry using the real SDK level helper.
const model = (id: string, map?: Record<string, string | null>, reasoning = true) => ({ provider: "p", id, reasoning, thinkingLevelMap: map })
const models = [model("kimi", { high: null }), model("plain"), model("adaptive", { xhigh: "max" }), model("nothink", undefined, false)]
const registry = { find: (p: string, id: string) => models.find((m) => m.provider === p && m.id === id), getAvailable: () => models }
const route = (input: object) => agentRouteReason(input, { modelRegistry: registry })
assert.match(route({ model: "p/kimi", thinking: "high" }) ?? "", /does not support thinking "high".*No substitute/)
assert.equal(route({ model: "p/kimi", thinking: "medium" }), undefined)
assert.equal(route({ model: "p/plain", thinking: "high" }), undefined) // absent map: default identity mapping applies
assert.match(route({ model: "p/plain", thinking: "max" }) ?? "", /does not support/) // max needs an explicit mapping
assert.match(route({ model: "p/plain", thinking: "xhigh" }) ?? "", /does not support/)
assert.equal(route({ model: "p/adaptive", thinking: "xhigh" }), undefined)
assert.match(route({ model: "p/nothink", thinking: "low" }) ?? "", /does not support/)
assert.equal(route({ model: "p/nothink", thinking: "off" }), undefined)
assert.match(route({ model: "p/fresh-unknown", thinking: "low" }) ?? "", /not registered/)
assert.match(route({ model: "p/plain", thinking: "bogus" }) ?? "", /thinking must be one of/)
assert.equal(route({ model: "p/fresh-unknown", resume: "abc123", thinking: "high" }), undefined)
assert.equal(route({ thinking: "max" }), undefined) // omitted model keeps the role default
assert.equal(route({ model: "sonnet", thinking: "max" }), undefined) // fuzzy name left to the extension
assert.equal(route({ model: "p/plain" }), undefined)
const unavailable = { find: registry.find, getAvailable: () => [] }
assert.match(agentRouteReason({ model: "p/plain" }, { modelRegistry: unavailable }) ?? "", /not registered/)
const routed = (input: object) => { let h: Handler; guard({ on: (_n: string, cb: Handler) => { h = cb } } as never); return h!({ toolName: "Agent", input: { prompt: plain, ...input } }, { cwd: "/x", modelRegistry: registry })?.block }
assert.equal(routed({ model: "p/kimi", thinking: "high" }), true)
assert.equal(routed({ model: "p/kimi", thinking: "low" }), undefined)

// Role resolution mirrors pi-subagents: global < .agents/agents < .pi/agents, frontmatter name over filename.
const home = process.env.PI_CODING_AGENT_DIR ?? join(process.env.HOME!, ".pi", "agent")
const dirs: Record<string, Record<string, string>> = {
  [join(home, "agents")]: { "g.md": "---\ntools: read\n---\n", "shadow.md": "---\ntools: read\n---\n" },
  "/x/.agents/agents": {
    "shadow.md": "---\ntools: read, bash\n---\n",
    "file-name.md": "---\nname: Declared\ntools: \"read, bash\"\ndisallowed_tools: [grep]\n---\n",
    "bad.md": "---\ntools: [unclosed\n---\n",
    "colon.md": "---\nname: a:b\ntools: read\n---\n",
  },
  "/x/.pi/agents": { "ro.md": "---\ntools: read, grep\ndisallowed_tools: grep\n---\n", "sh.md": "---\ntools: [read, bash]\n---\n", "open.md": "---\ndescription: d\n---\n", "star.md": "---\ntools: *\n---\n", "pin.md": "---\nmodel: p/kimi\nthinking: high\n---\n", "off.md": "---\nenabled: false\ntools: read\n---\n" },
}
const list = (dir: string) => Object.entries(dirs[dir] ?? {}).map(([file, text]) => ({ file, text }))
const resolve = (type: string) => resolveRole(type, "/x", list)
const need = (type: string, line: string, extra: object = {}) => requiredToolsReason({ prompt: `Do work.\nREQUIRED TOOLS: ${line}\nmore`, ...extra }, resolve(type))
assert.match(need("ro", "read, bash") ?? "", /cannot use required tools bash/)
assert.match(need("ro", "grep") ?? "", /cannot use required tools grep/)
assert.equal(need("ro", "read"), undefined)
assert.equal(need("sh", "Read, bash"), undefined) // YAML array
assert.equal(need("open", "bash"), undefined) // unresolvable: policy/manual check retained
assert.equal(need("star", "bash"), undefined)
assert.equal(need("unknown-role", "bash"), undefined)
assert.equal(need("off", "bash"), undefined) // disabled role is refused by pi-subagents itself
assert.match(need("sh", "bash; rm -rf") ?? "", /comma-separated/)
assert.equal(requiredToolsReason({ prompt: "needs bash" }, resolve("ro")), undefined) // no natural-language parsing
assert.match(need("g", "bash") ?? "", /cannot use required tools bash/)
assert.equal(need("shadow", "bash"), undefined) // .agents/agents shadows global
assert.equal(need("Declared", "bash"), undefined) // quoted CSV, name differs from filename
assert.match(need("Declared", "grep") ?? "", /cannot use required tools grep/) // disallowed array
assert.equal(resolve("file-name"), undefined) // filename is not the type once name: is declared
assert.equal(resolve("bad"), undefined) // unparseable file skipped
assert.equal(resolve("a:b"), undefined)
assert.equal(need("ro", "bash", { resume: "abc" }), undefined) // resume ignores role type
assert.match(need("ro", "bash", { resume: "" }) ?? "", /cannot use/)

// Effective pin precedence: role frontmatter outranks call params.
const pinned = (input: object, type: string) => agentRouteReason(input, { modelRegistry: registry }, resolve(type))
assert.match(pinned({ model: "p/plain", thinking: "low" }, "pin") ?? "", /p\/kimi does not support thinking "high"/)
assert.match(pinned({ model: "p/fresh-unknown", thinking: "bogus" }, "pin") ?? "", /p\/kimi does not support/) // the pin is validated, not the ignored input
assert.equal(pinned({ model: "p/kimi", thinking: "medium" }, "ro"), undefined)
assert.match(pinned({ model: "p/kimi", thinking: "high" }, "ro") ?? "", /does not support/) // no pin: input validated
assert.equal(pinned({ model: "p/kimi", thinking: "high", resume: "abc" }, "pin"), undefined)
console.log("Agent prompt guard checks passed")
TS
