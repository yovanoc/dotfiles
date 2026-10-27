import { readdirSync, readFileSync } from "node:fs"
import { basename, join } from "node:path"
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"
import { getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent"
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai/models"

// Glued packets ("Localreversibleedits", "task1220") read badly and hurt small models most.
// Same shape as the scripts/pi-session-audit smushed-prompt metric, counting all whitespace.
export function gluedPromptReason(prompt: unknown): string | undefined {
  if (typeof prompt !== "string" || prompt.length <= 200) return
  const perThousand = ((prompt.match(/\s/g)?.length ?? 0) * 1000) / prompt.length
  if (perThousand >= 80) return
  return `Agent prompt rejected: ${Math.round(perThousand)} whitespace characters per 1000 (minimum 80). Rewrite it for a stranger: plain sentences with spaces, full paths, no glued words or task/hash shorthand, then dispatch again.`
}

const EFFORTS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
const str = (value: unknown) => typeof value === "string" ? value : undefined
// Mirrors pi-subagents parseCsvField: arrays and scalars stringify, "none"/empty mean nothing.
const csv = (value: unknown) => { const text = String(value).trim(); return text === "none" ? [] : text.split(",").map((item) => item.trim().toLowerCase()).filter(Boolean) }

export type Role = { model?: string, thinking?: string, tools?: unknown, disallowed?: unknown, enabled: boolean }
export type ListAgents = (dir: string) => { file: string, text: string }[]
const listAgents: ListAgents = (dir) => {
  try { return readdirSync(dir).filter((f) => f.endsWith(".md")).map((file) => ({ file, text: readFileSync(join(dir, file), "utf8") })) } catch { return [] }
}

// Mirrors pi-subagents custom-agents.ts loadCustomAgents for the user-controlled tiers: global, then <cwd>/.agents/agents, then
// <cwd>/.pi/agents, later wins; the type is frontmatter `name` (not containing ":") else the filename; unparseable files are skipped.
// Package-provided agents (lowest priority, resolved by pi-subagents internals) and built-in default roles are not resolvable: undefined.
export function resolveRole(type: unknown, cwd: string, list: ListAgents = listAgents): Role | undefined {
  if (typeof type !== "string") return
  let role: Role | undefined
  for (const dir of [join(getAgentDir(), "agents"), join(cwd, ".agents", "agents"), join(cwd, ".pi", "agents")]) {
    for (const { file, text } of list(dir)) {
      let fm: Record<string, unknown>
      try { fm = parseFrontmatter<Record<string, unknown>>(text.startsWith("\uFEFF") ? text.slice(1) : text).frontmatter } catch { continue }
      const declared = str(fm.name)?.trim()
      if (declared?.includes(":")) continue
      if ((declared || basename(file, ".md")) !== type) continue
      role = { model: str(fm.model), thinking: str(fm.thinking), tools: fm.tools, disallowed: fm.disallowed_tools, enabled: fm.enabled !== false }
    }
  }
  return role
}

// Target worker tools come from the resolved role's explicit `tools:` allowlist. Roles without one (all built-ins plus inherited
// extension tools), wildcard or ext: selectors, unresolved or built-in default roles, and resumes (the role type is ignored there) skip the check.
export function requiredToolsReason(input: { prompt?: unknown, resume?: unknown }, role: Role | undefined): string | undefined {
  if (input.resume !== undefined && input.resume !== "") return
  const line = typeof input.prompt === "string" ? input.prompt.match(/^REQUIRED TOOLS:[ \t]*(.*)$/m)?.[1] : undefined
  if (line === undefined) return
  const required = line.split(",").map((item) => item.trim())
  if (!required.every((tool) => /^[A-Za-z0-9_.:-]+$/.test(tool))) return "Agent prompt rejected: REQUIRED TOOLS must be a comma-separated list of tool names."
  if (!role?.enabled || role.tools === undefined || role.tools === null) return
  const allowed = csv(role.tools)
  if (allowed.some((tool) => tool === "*" || tool === "all" || tool.startsWith("ext:"))) return
  const denied = role.disallowed === undefined || role.disallowed === null ? [] : csv(role.disallowed)
  const last = required[required.length - 1].toLowerCase()
  // Exact declarations win; tolerate one sentence-final period only for an allowed name.
  if (last.endsWith(".") && !last.endsWith("..") && !allowed.includes(last) && !denied.includes(last) && allowed.includes(last.slice(0, -1))) {
    required[required.length - 1] = required[required.length - 1].slice(0, -1)
  }
  const missing = required.filter((tool) => !allowed.includes(tool.toLowerCase()) || denied.includes(tool.toLowerCase()))
  if (missing.length) return `Agent preflight rejected: this role cannot use required tools ${missing.join(", ")}. Choose a role whose tools allowlist includes them or drop them from REQUIRED TOOLS.`
}

// Validates the effective pin pi-subagents will use (role frontmatter outranks call params). Only an explicit "provider/model" is
// checked, using exact registered IDs; fuzzy names, omitted models and resumes keep the extension's own resolution.
export function agentRouteReason(input: { model?: unknown, thinking?: unknown, resume?: unknown }, ctx: Pick<ExtensionContext, "modelRegistry">, role?: Role): string | undefined {
  if (input.resume !== undefined && input.resume !== "") return
  const model = role?.enabled ? role.model ?? input.model : input.model
  const thinking = role?.enabled ? role.thinking ?? input.thinking : input.thinking
  if (typeof model !== "string" || !model.includes("/")) return
  const slash = model.indexOf("/")
  const found = ctx.modelRegistry.find(model.slice(0, slash), model.slice(slash + 1))
  if (!found || !ctx.modelRegistry.getAvailable().some((m) => m.provider === found.provider && m.id === found.id)) {
    return `Agent preflight rejected: model ${model} is not registered with usable auth. Pick a registered provider/model; no fallback is substituted.`
  }
  if (thinking === undefined) return
  if (typeof thinking !== "string" || !EFFORTS.includes(thinking)) return `Agent preflight rejected: thinking must be one of ${EFFORTS.join(", ")}.`
  const levels = getSupportedThinkingLevels(found)
  if (!levels.includes(thinking as never)) return `Agent preflight rejected: ${model} does not support thinking "${thinking}" (supported: ${levels.join(", ")}). No substitute level is applied; choose a supported level or another model.`
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName !== "Agent") return
    const input = event.input as { prompt?: unknown, subagent_type?: unknown, model?: unknown, thinking?: unknown, resume?: unknown }
    const glued = gluedPromptReason(input.prompt)
    if (glued) return { block: true, reason: glued }
    const resumed = input.resume !== undefined && input.resume !== ""
    const role = resumed ? undefined : resolveRole(input.subagent_type, ctx.cwd)
    const reason = agentRouteReason(input, ctx, role) ?? requiredToolsReason(input, role)
    if (reason) return { block: true, reason }
  })
}
