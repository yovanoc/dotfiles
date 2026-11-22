import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"
import { getAgentDir } from "@earendil-works/pi-coding-agent"
import { Type } from "typebox"
import { createHash } from "node:crypto"
import { readFileSync, realpathSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { join, sep } from "node:path"
import { fileURLToPath } from "node:url"

const EFFORTS = ["off", "minimal", "low", "medium", "high", "xhigh", "max", "unknown"]
const label = /^[A-Za-z0-9_./:@+-]{1,128}$/
const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())

export type TaskOutcomeReceipt = { taskId: string, outcome: "accepted" | "reworked" | "rejected", model: string, effort: string, checkArtifact: string, boardTaskId?: string, attemptId?: string, phase?: "implementation" | "review" | "repair", parentTaskId?: string, reviewerWorkerId?: string, coordinatorReportedDurationMs?: number, observedModels?: string[] }

// Coordinator-reported claim, not runtime proof; completion alone never implies acceptance.
export function validateReceipt(args: TaskOutcomeReceipt): TaskOutcomeReceipt {
  if (!["accepted", "reworked", "rejected"].includes(args.outcome)) throw new Error("outcome must be accepted, reworked or rejected.")
  for (const key of ["taskId", "model"] as const) if (!label.test(args[key])) throw new Error(`${key} must be 1-128 characters from A-Za-z0-9_./:@+-.`)
  if (!EFFORTS.includes(args.effort)) throw new Error(`effort must be one of ${EFFORTS.join(", ")}.`)
  if (!/^[^\s\0-\x1f\x7f]{1,300}$/.test(args.checkArtifact)) throw new Error("checkArtifact must be a path of at most 300 characters without whitespace or control characters.")
  for (const key of ["boardTaskId", "attemptId", "parentTaskId", "reviewerWorkerId"] as const) {
    if (args[key] !== undefined && (typeof args[key] !== "string" || !label.test(args[key]))) throw new Error(`Invalid ${key}.`)
  }
  if (args.phase !== undefined && !["implementation", "review", "repair"].includes(args.phase)) throw new Error("Invalid phase.")
  if (args.coordinatorReportedDurationMs !== undefined && (!Number.isSafeInteger(args.coordinatorReportedDurationMs) || args.coordinatorReportedDurationMs < 0)) throw new Error("Invalid coordinatorReportedDurationMs.")
  const receipt: TaskOutcomeReceipt = { taskId: args.taskId, outcome: args.outcome, model: args.model, effort: args.effort, checkArtifact: args.checkArtifact }
  for (const key of ["boardTaskId", "attemptId", "phase", "parentTaskId", "reviewerWorkerId", "coordinatorReportedDurationMs"] as const) {
    if (args[key] !== undefined) Object.assign(receipt, { [key]: args[key] })
  }
  return receipt
}

// Terminal workers without a receipt on the active branch: advisory only, never a block and never an automatic receipt.
// Worker IDs come from the structured, durable `subagents:record` entries pi-subagents appends once per terminal worker
// (the same ID space task_outcome and the audit use); TaskUpdate list IDs are a different ID space and are never used.
const TERMINAL = ["completed", "steered", "aborted", "stopped", "error"]
export function missingReceipts(entries: readonly { type: string, customType?: string, data?: unknown }[]): string[] {
  const terminal = new Set<string>(), receipted = new Set<string>()
  for (const entry of entries) {
    if (entry.type !== "custom") continue
    const data = entry.data as { id?: unknown, taskId?: unknown, status?: unknown } | undefined
    if (entry.customType === "subagents:record" && typeof data?.id === "string" && label.test(data.id) && TERMINAL.includes(data.status as string)) terminal.add(data.id)
    else if (entry.customType === "task-outcome-receipt" && typeof data?.taskId === "string") receipted.add(data.taskId)
  }
  return [...terminal].filter((id) => !receipted.has(id))
}

// Physical models that actually produced successful assistant turns for a worker, read from its persisted pi session. The path comes
// from the durable `subagents:record` entry but is still untrusted: it must resolve (symlinks included) to a bounded regular
// file under the agent sessions dir, and every transcript line is parsed defensively. Anything unavailable is ["unknown"], never a guess.
const MAX_SESSION_BYTES = 32 * 1024 * 1024
export function observedModels(entries: readonly { type: string, customType?: string, data?: unknown }[], workerId: string, sessionsDir = join(getAgentDir(), "sessions")): string[] {
  const unknown = ["unknown"]
  try {
    let file: unknown
    for (const entry of entries) {
      const data = entry.data as { id?: unknown, sessionFile?: unknown } | null | undefined
      if (entry.type === "custom" && entry.customType === "subagents:record" && data?.id === workerId) file = data.sessionFile
    }
    if (typeof file !== "string" || !file || file.includes("\0")) return unknown
    const real = realpathSync(file), root = realpathSync(sessionsDir)
    const info = statSync(real)
    if (!real.startsWith(root + sep) || !info.isFile() || info.size > MAX_SESSION_BYTES) return unknown
    const seen = new Set<string>()
    for (const line of readFileSync(real, "utf8").split("\n")) {
      if (!line.includes('"assistant"')) continue
      let entry: { type?: unknown, message?: { role?: unknown, provider?: unknown, model?: unknown, stopReason?: unknown } }
      try { entry = JSON.parse(line) } catch { continue }
      const m = entry?.type === "message" ? entry.message : undefined
      if (m?.role !== "assistant" || (m.stopReason !== "stop" && m.stopReason !== "toolUse" && m.stopReason !== "length")) continue
      if (typeof m.provider !== "string" || typeof m.model !== "string") continue
      const id = `${m.provider}/${m.model}`
      if (label.test(id)) seen.add(id)
    }
    return seen.size ? [...seen].sort() : unknown
  } catch { return unknown }
}

function sha256(path: string): string | null {
  try { return createHash("sha256").update(readFileSync(path)).digest("hex") } catch { return null }
}

export default function (pi: ExtensionAPI) {
  // File hashes are observed bytes, not proof that the model read the policy.
  const extensionHash = sha256(fileURLToPath(import.meta.url))
  const status = (ctx: ExtensionContext, missing: string[]) =>
    ctx.ui.setStatus("task-outcome", missing.length ? `${missing.length} workers without outcome receipt` : undefined)
  const refresh = (_event: unknown, ctx: ExtensionContext) => {
    if (isWorker(ctx)) return
    status(ctx, missingReceipts(ctx.sessionManager.getBranch()))
  }
  pi.on("session_start", (event, ctx) => {
    if (isWorker(ctx)) return
    const reasons = ["startup", "reload", "new", "resume", "fork"]
    pi.appendEntry("task-outcome-activation", {
      schemaVersion: 1, extensionVersion: 1, extensionSha256: extensionHash,
      coordinatorPolicySha256: sha256(join(homedir(), ".pi/agent/docs/coordinator.md")),
      timestamp: new Date().toISOString(), source: reasons.includes(event.reason) ? event.reason : "unknown",
    })
    refresh(event, ctx)
  })
  pi.on("session_tree", refresh)
  pi.on("turn_end", refresh)
  pi.on("agent_end", refresh)
  pi.registerTool({
    name: "task_outcome",
    label: "Task outcome",
    description: "Coordinator-only: record the verified outcome of one task with the model and effort you dispatched it with and the path of the check artifact. Reported claim, not runtime proof.",
    parameters: Type.Object({
      taskId: Type.String({ maxLength: 128 }),
      outcome: Type.Union([Type.Literal("accepted"), Type.Literal("reworked"), Type.Literal("rejected")]),
      model: Type.String({ maxLength: 128 }),
      effort: Type.String({ maxLength: 16 }),
      checkArtifact: Type.String({ maxLength: 300 }),
      boardTaskId: Type.Optional(Type.String({ maxLength: 128 })),
      attemptId: Type.Optional(Type.String({ maxLength: 128 })),
      phase: Type.Optional(Type.Union([Type.Literal("implementation"), Type.Literal("review"), Type.Literal("repair")])),
      parentTaskId: Type.Optional(Type.String({ maxLength: 128 })),
      reviewerWorkerId: Type.Optional(Type.String({ maxLength: 128 })),
      coordinatorReportedDurationMs: Type.Optional(Type.Integer({ minimum: 0, maximum: Number.MAX_SAFE_INTEGER })),
    }),
    async execute(_id, args, _signal, _update, ctx) {
      if (isWorker(ctx)) throw new Error("Workers cannot record coordinator task outcomes.")
      const receipt = validateReceipt(args)
      // Aliases are not runtimes: an alias receipt always states which physical models ran (or unknown); a physical one only when evidence exists.
      const observed = observedModels(ctx.sessionManager.getBranch(), receipt.taskId)
      if (receipt.model.startsWith("route/") || observed[0] !== "unknown") receipt.observedModels = observed
      pi.appendEntry("task-outcome-receipt", receipt)
      status(ctx, missingReceipts(ctx.sessionManager.getBranch()).filter((id) => id !== receipt.taskId))
      return { content: [{ type: "text", text: `Recorded ${receipt.outcome} for ${receipt.taskId}.` }], details: receipt }
    },
  })
}
