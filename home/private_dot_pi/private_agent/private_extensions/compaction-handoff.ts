import type { ExtensionAPI, ExtensionContext, AgentBeforeSettleEvent, TurnEndEvent } from "@earendil-works/pi-coding-agent"
import { getAgentDir, withFileMutationQueue } from "@earendil-works/pi-coding-agent"
import { createHash, randomUUID } from "node:crypto"
import { Type } from "typebox"
import { mkdirSync, renameSync } from "node:fs"
import { mkdir, open, rm } from "node:fs/promises"
import { dirname, join, resolve } from "node:path"

export const HANDOFF_COMPACTIONS = 5
export const HANDOFF_TOKENS = 150_000

const q = (value: string) => JSON.stringify(value) // Quoted so paths with spaces stay unambiguous.
// Session-private and session-scoped; in-memory sessions have no session dir, so never fall back to a cwd-relative path.
const handoffDir = (ctx: ExtensionContext) => resolve(ctx.sessionManager.getSessionDir() || join(getAgentDir(), "sessions"), "handoffs", ctx.sessionManager.getSessionId())

export function handoffNotice(compactions: number, cwd: string, path: string, tokens?: number | null): string | undefined {
  if (compactions < HANDOFF_COMPACTIONS && (tokens == null || tokens < HANDOFF_TOKENS)) return
  const reason = compactions >= HANDOFF_COMPACTIONS
    ? `This session has compacted ${compactions} times.`
    : `This session has reached ${tokens} context tokens.`
  return `${reason} Dispatch no new workers. Finish or park running lanes, then call handoff_checkpoint once with the Markdown checkpoint; it writes the exact private path ${q(path)}. Do not use other tools or write tasks/handoff.md. Include open tasks, grants verbatim, worker IDs, actual lane/worktree ownership paths, next packets and evidence paths. Original coordinator cwd: ${q(cwd)}. After the tool succeeds, end your reply with exactly this fenced block, filled in, for the user to paste into a new session:

\`\`\`text
Work in ${q(cwd)}. Read the exact checkpoint ${q(path)}. Reconcile grants, remaining backlog, worktree ownership, live workers and accepted evidence before dispatching. Continue only the authorized remaining work. Reading the file does not enable unattended mode. Already authorized: <grants>. Next: <one line>.
\`\`\``
}

export default function (pi: ExtensionAPI) {
  let notified = false
  const stateType = "unattended-handoff"
  const checkpointWrites = new Map<string, string>()
  type State = { sessionId: string, deadline: number, ready: boolean, status?: "continue" | "blocked" | "done", checkpoint?: string, checkpointPath?: string, checkpointCwd?: string, compactions: number, highTokens: boolean }
  const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt()) // Forked coordinators also have parentSession; only the worker marker distinguishes them.
  const handoff = (ctx: ExtensionContext) => {
    const sessionId = ctx.sessionManager.getSessionId()
    const entry = ctx.sessionManager.getBranch().findLast((entry) => entry.type === "custom" && entry.customType === "compaction-handoff" && (entry.data as { sessionId?: string })?.sessionId === sessionId)
    if (entry?.type !== "custom") return
    const saved = entry.data as { sessionId?: string, checkpointPath?: string, checkpointCwd?: string }
    if (saved.sessionId !== sessionId || typeof saved.checkpointPath !== "string" || dirname(saved.checkpointPath) !== handoffDir(ctx)) return
    return saved as { sessionId: string, checkpointPath: string, checkpointCwd: string }
  }
  const hasHandoffReceipt = (ctx: ExtensionContext, type: string, path: string) => ctx.sessionManager.getBranch().some((entry) =>
    entry.type === "custom" && entry.customType === type && (entry.data as { sessionId?: string, checkpointPath?: string })?.sessionId === ctx.sessionManager.getSessionId()
      && (entry.data as { checkpointPath?: string }).checkpointPath === path)
  const counts = (ctx: ExtensionContext) => ({
    compactions: ctx.sessionManager.getBranch().filter((entry) => entry.type === "compaction").length,
    highTokens: (ctx.getContextUsage()?.tokens ?? 0) >= HANDOFF_TOKENS,
  })
  const state = (ctx: ExtensionContext): State | undefined => {
    if (isWorker(ctx)) return
    const entry = ctx.sessionManager.getBranch().findLast((entry) => entry.type === "custom" && entry.customType === stateType)
    if (entry?.type !== "custom") return
    const saved = entry.data as State
    return saved?.sessionId === ctx.sessionManager.getSessionId() ? saved : undefined
  }
  const active = (saved?: State) => saved && saved.deadline > Date.now()
  const instructions = (ctx: ExtensionContext, saved: State) => `Unattended coordinator opt-in expires at ${new Date(saved.deadline).toISOString()}.
Continue only the user's explicit backlog within their existing grants. This mode grants no new permissions or budget. If the prompt lacks an authorized backlog/grants, or safety, budget, approval, or other blockers require the user, checkpoint as blocked and stop. Do not ask again for existing grants.
At each meaningful packet/final-response boundary, call unattended_checkpoint with a complete Markdown checkpoint for original coordinator cwd ${q(resolve(ctx.cwd))}; each save publishes a fresh private file in ${q(handoffDir(ctx))}, never tasks/handoff.md. ${saved.checkpointPath ? `Latest checkpoint on this branch: ${q(saved.checkpointPath)} (cwd ${q(saved.checkpointCwd!)}).` : "No checkpoint saved on this branch yet."} Include grants verbatim (not paraphrased), original backlog and remaining tasks, worker IDs and running lanes, actual lane/worktree ownership paths, evidence paths, completed but unaccepted worker outcomes, blockers and next packets. Preserve existing handoff information. Do not cancel or park workers just to checkpoint. Use status continue only when authorized work remains without blockers; otherwise blocked or done. After checkpointing, continue the original authorized work; do not ask the user to paste a prompt. Do not checkpoint repeatedly without work progress.`
  const enable = (args: string, ctx: ExtensionContext) => {
    if (isWorker(ctx)) { ctx.ui.notify("Workers cannot enable unattended coordinator mode.", "warning"); return }
    const value = args.trim()
    if (value !== "off" && (!/^(?:\d+(?:\.\d+)?|\.\d+)$/.test(value) || !Number.isFinite(Number(value)) || Number(value) <= 0 || !Number.isSafeInteger(Math.ceil(Date.now() + Number(value) * 60_000)))) {
      ctx.ui.notify("Usage: /unattended <positive minutes> | off. Supply the authorized backlog and grants in your prompt.", "warning")
      return
    }
    const saved: State = { sessionId: ctx.sessionManager.getSessionId(), deadline: value === "off" ? 0 : Date.now() + Number(value) * 60_000, ready: false, ...counts(ctx) }
    pi.appendEntry(stateType, saved)
    ctx.ui.notify(value === "off" ? "Unattended mode off." : `Unattended until ${new Date(saved.deadline).toISOString()}; supply backlog and grants in your prompt.`, "info")
  }
  pi.registerCommand("unattended", { description: "Opt in for positive minutes, or off; requires authorized backlog/grants in prompt", handler: async (args, ctx) => enable(args, ctx) })
  pi.registerFlag("unattended-minutes", { type: "string", description: "Explicit bounded unattended coordinator opt-in; requires backlog/grants in prompt" })
  pi.registerTool({
    name: "unattended_checkpoint",
    label: "Unattended checkpoint",
    description: "Save a fresh session-private handoff checkpoint at a meaningful boundary. Cannot enable unattended mode. Include grants verbatim, backlog, worker IDs, evidence and unaccepted outcomes. Report continue only for remaining authorized work with no safety/budget/approval blockers; otherwise blocked or done.",
    parameters: Type.Object({ status: Type.Union([Type.Literal("continue"), Type.Literal("blocked"), Type.Literal("done")]), markdown: Type.String({ minLength: 1 }) }),
    async execute(_id, args, signal, _update, ctx) {
      const sessionId = ctx.sessionManager.getSessionId()
      const deadline = state(ctx)?.deadline
      if (!active(state(ctx))) throw new Error("Unattended mode is not active on this coordinator branch.")
      const cwd = resolve(ctx.cwd)
      const dir = handoffDir(ctx)
      const path = join(dir, `${randomUUID()}.md`)
      await mkdir(dir, { recursive: true, mode: 0o700 })
      // Stable session-scoped key: the directory now exists, so its realpath never changes between saves.
      const leaf = ctx.sessionManager.getLeafId() // Captured before queueing: a navigation while waiting must fail this save.
      await withFileMutationQueue(dir, async () => {
        const saved = state(ctx)
        const valid = () => active(state(ctx)) && state(ctx)!.deadline === deadline && ctx.sessionManager.getSessionId() === sessionId
          && !signal?.aborted && !ctx.signal?.aborted && (leaf === null || ctx.sessionManager.getBranch().some((entry) => entry.id === leaf))
        if (!valid()) throw new Error("Unattended mode is not active on this coordinator branch.")
        // This invocation owns the unique staging path; the published checkpoint is immutable.
        const staging = `${path}.partial`
        try {
          const file = await open(staging, "wx", 0o600)
          try { await file.writeFile(args.markdown, "utf8"); await file.sync() } finally { await file.close() }
          if (!valid()) throw new Error("Unattended session, branch, deadline or abort state changed during checkpoint.")
          // Synchronous publish + receipt: nothing can navigate in between. file.sync is not power-loss durability.
          renameSync(staging, path)
          const checkpoint = createHash("sha256").update(args.markdown).digest("hex")
          // Content hash, not filename: identical checkpoints never re-arm continuation.
          pi.appendEntry(stateType, { ...saved, status: args.status, ready: args.status === "continue" && checkpoint !== saved!.checkpoint, checkpoint, checkpointPath: path, checkpointCwd: cwd, ...counts(ctx) })
        } finally { await rm(staging, { force: true }) }
      })
      return { content: [{ type: "text", text: `Checkpoint saved to ${q(path)} for original coordinator cwd ${q(cwd)}; status ${args.status}.` }], details: { status: args.status, path, cwd } }
    },
  })
  pi.registerTool({
    name: "handoff_checkpoint",
    label: "Interactive handoff checkpoint",
    description: "Save Markdown to the exact private checkpoint allocated for the pending interactive handoff. Accepts no path and cannot enable unattended mode. Use once, then give the final user handoff.",
    parameters: Type.Object({ markdown: Type.String({ minLength: 1 }) }),
    async execute(id, args, signal, _update, ctx) {
      if (isWorker(ctx)) throw new Error("Workers cannot write coordinator handoff checkpoints.")
      const pending = handoff(ctx)
      const sessionId = ctx.sessionManager.getSessionId()
      const path = pending?.checkpointPath
      const dir = path && dirname(path)
      if (!ctx.hasUI || !pending || !path || !dir || (state(ctx)?.deadline ?? 0) > 0
        || hasHandoffReceipt(ctx, "compaction-handoff-approved", path) || hasHandoffReceipt(ctx, "compaction-handoff-written", path)) {
        throw new Error("No pending interactive handoff checkpoint is available.")
      }
      const leaf = ctx.sessionManager.getLeafId()
      await mkdir(dir, { recursive: true, mode: 0o700 })
      await withFileMutationQueue(dir, async () => {
        const valid = () => !isWorker(ctx) && ctx.hasUI && ctx.sessionManager.getSessionId() === sessionId
          && !signal?.aborted && !ctx.signal?.aborted && (leaf === null || ctx.sessionManager.getBranch().some((entry) => entry.id === leaf))
          && handoff(ctx)?.checkpointPath === path && (state(ctx)?.deadline ?? 0) === 0
          && !hasHandoffReceipt(ctx, "compaction-handoff-approved", path) && !hasHandoffReceipt(ctx, "compaction-handoff-written", path)
        if (!valid()) throw new Error("No pending interactive handoff checkpoint is available.")
        let created = false
        let published = false
        try {
          const file = await open(path, "wx", 0o600)
          created = true
          try { await file.writeFile(args.markdown, "utf8"); await file.sync() } finally { await file.close() }
          if (!valid()) throw new Error("Interactive handoff changed during checkpoint.")
          pi.appendEntry("compaction-handoff-written", { sessionId, checkpointPath: path })
          published = true
        } finally {
          if (created && !published) await rm(path, { force: true })
        }
      })
      const cwd = pending.checkpointCwd
      return { content: [{ type: "text", text: `Checkpoint saved to ${q(path)} for original coordinator cwd ${q(cwd)}.` }], details: { path, cwd } }
    },
  })
  // Input retains provenance for idle prompts and queued steering/follow-ups; a user role alone also includes extension messages.
  pi.on("input", (event, ctx) => {
    if (isWorker(ctx) || (event.source !== "interactive" && event.source !== "rpc")) return
    const pending = handoff(ctx)
    if (pending && !hasHandoffReceipt(ctx, "compaction-handoff-approved", pending.checkpointPath)) {
      pi.appendEntry("compaction-handoff-approved", { sessionId: pending.sessionId, checkpointPath: pending.checkpointPath })
    }
  })
  pi.on("before_agent_start", (_event, ctx) => {
    const saved = state(ctx)
    if (active(saved)) return { message: { customType: "unattended-instructions", content: instructions(ctx, saved!), display: false } }
  })
  // Cooperative deadline: don't start another coordinator model turn; never cancel worker sessions.
  pi.on("turn_start", (_event, ctx) => {
    const saved = state(ctx)
    if (saved && saved.deadline > 0 && !active(saved)) ctx.abort()
  })
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "handoff_checkpoint" && isWorker(ctx)) return { block: true, reason: "Workers cannot write coordinator handoff checkpoints." }
    const saved = state(ctx)
    if (saved && saved.deadline > 0 && !active(saved)) return { block: true, terminate: true, reason: "Unattended deadline reached. Stop coordinator work; preserve running workers and resume only with user input/renewed opt-in." }
    checkHandoff(ctx)
    const pending = handoff(ctx)
    if (!pending) return event.toolName === "handoff_checkpoint" ? { block: true, reason: "No pending interactive handoff checkpoint is available." } : undefined
    const approved = hasHandoffReceipt(ctx, "compaction-handoff-approved", pending.checkpointPath)
    const unattended = (state(ctx)?.deadline ?? 0) > 0
    if (approved || unattended) return event.toolName === "handoff_checkpoint" ? { block: true, reason: "No pending interactive handoff checkpoint is available." } : undefined
    const written = hasHandoffReceipt(ctx, "compaction-handoff-written", pending.checkpointPath)
    const writing = [...checkpointWrites.values()].includes(pending.checkpointPath)
    const input = event.input as Record<string, unknown>
    if (!written && !writing && event.toolName === "handoff_checkpoint") {
      checkpointWrites.set(event.toolCallId, pending.checkpointPath)
      return
    }
    if (!written && !writing && event.toolName === "write" && typeof input.path === "string" && typeof input.content === "string" && resolve(ctx.cwd, input.path) === pending.checkpointPath) {
      checkpointWrites.set(event.toolCallId, pending.checkpointPath)
      return
    }
    return { block: true, reason: `Interactive handoff is pending. Only handoff_checkpoint or a write to the exact private checkpoint ${q(pending.checkpointPath)} is allowed; then finish the user handoff. A new user prompt approves further work.` }
  })
  // Pi skips tool_result on pre-execution rejection/abort, but still emits the terminal execution event.
  pi.on("tool_execution_end", (event) => { checkpointWrites.delete(event.toolCallId) })
  pi.on("tool_result", (event, ctx) => {
    const path = checkpointWrites.get(event.toolCallId)
    if (!path) return
    checkpointWrites.delete(event.toolCallId)
    const pending = handoff(ctx)
    if (pending?.checkpointPath === path && !event.isError && event.toolName === "write" && typeof event.input.path === "string" && resolve(ctx.cwd, event.input.path) === path
      && !hasHandoffReceipt(ctx, "compaction-handoff-written", path)) {
      pi.appendEntry("compaction-handoff-written", { sessionId: pending.sessionId, checkpointPath: path })
    }
  })
  const boundary = (event: AgentBeforeSettleEvent | TurnEndEvent, ctx: ExtensionContext) => {
    const saved = state(ctx)
    if (!active(saved) || saved!.status === "blocked" || saved!.status === "done" || event.outcome !== "completed" || ctx.signal?.aborted) return
    const current = counts(ctx)
    const due = current.compactions >= Math.max(HANDOFF_COMPACTIONS, saved!.compactions + HANDOFF_COMPACTIONS) || (current.highTokens && !saved!.highTokens)
    const resume = event.type === "agent_before_settle" && saved!.ready
    if (!due && !resume) return
    // Commit message and guard together. A final assistant message alone cannot continue in Pi.
    return { entries: [...event.entries,
      { type: "custom" as const, customType: stateType, data: { ...saved, ...current, ready: false } },
      { type: "custom_message" as const, customType: "unattended-continuation", display: true,
        content: resume ? `${saved!.checkpointPath ? `Checkpoint saved to ${q(saved!.checkpointPath)} for original coordinator cwd ${q(saved!.checkpointCwd ?? resolve(ctx.cwd))}.` : "Checkpoint saved."} Continue the original authorized backlog within existing grants until ${new Date(saved!.deadline).toISOString()}. Preserve workers; stop on completion, safety/budget/approval blockers or deadline. Make progress before another checkpoint.` : instructions(ctx, saved!) },
    ], continue: true }
  }
  pi.on("agent_before_settle", boundary)

  const checkHandoff = (ctx: ExtensionContext) => {
    // UI availability is not worker identity: headless coordinators may explicitly opt in.
    if (isWorker(ctx) || (state(ctx)?.deadline ?? 0) > 0 || !ctx.hasUI || notified) return
    const cwd = resolve(ctx.cwd)
    const path = join(handoffDir(ctx), `${randomUUID()}.md`)
    const notice = handoffNotice(
      ctx.sessionManager.getBranch().filter((entry) => entry.type === "compaction").length,
      cwd,
      path,
      ctx.getContextUsage()?.tokens,
    )
    if (!notice) return
    // Guard immediately: steer delivery may not be persisted until the next response.
    notified = true
    // The model writes the file; the extension owns its private directory and records the location on this branch only.
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 })
    pi.appendEntry("compaction-handoff", { sessionId: ctx.sessionManager.getSessionId(), checkpointPath: path, checkpointCwd: cwd })
    ctx.ui.notify(notice.split("\n")[0], "warning")
    // "steer" reaches the model before its next response; "nextTurn" waited for the next user prompt (hours).
    pi.sendMessage({ customType: "compaction-handoff", content: notice, display: true }, { deliverAs: "steer" })
  }

  const restore = (ctx: ExtensionContext) => {
    // Only this session's own allocation counts: a fork/clone must get a fresh path, never write its parent's checkpoint.
    const branch = ctx.sessionManager.getBranch()
    const allocations = branch.filter((entry) => entry.type === "custom" && entry.customType === "compaction-handoff")
    notified = allocations.length
      ? allocations.some((entry) => entry.type === "custom" && (entry.data as { sessionId?: string })?.sessionId === ctx.sessionManager.getSessionId())
      : branch.some((entry) => entry.type === "custom_message" && entry.customType === "compaction-handoff") // legacy notice without allocation
    checkHandoff(ctx)
  }
  pi.on("session_start", (event, ctx) => {
    // CLI is a start-only grant, never inherited on resume or branch navigation.
    const flag = pi.getFlag("unattended-minutes")
    if (flag && event.reason === "startup" && ctx.sessionManager.getBranch().every((entry) => entry.type === "model_change" || entry.type === "thinking_level_change")) enable(String(flag), ctx)
    restore(ctx)
  })
  pi.on("session_tree", (_event, ctx) => restore(ctx))
  pi.on("turn_end", (event, ctx) => { checkHandoff(ctx); return boundary(event, ctx) })
  pi.on("session_compact", (_event, ctx) => checkHandoff(ctx))
}
