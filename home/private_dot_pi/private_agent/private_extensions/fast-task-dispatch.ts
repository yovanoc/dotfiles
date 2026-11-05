import { createHash, randomUUID } from "node:crypto"
import { realpathSync } from "node:fs"
import { basename, dirname, isAbsolute, join, resolve } from "node:path"
import type { ExtensionAPI, ExtensionContext, ExtensionToolContext, ToolLoadout } from "@earendil-works/pi-coding-agent"
import { Type } from "typebox"
import { agentResumeReason, agentRouteReason, gluedPromptReason, requiredToolsReason, resolveRole, solRationaleReason } from "./agent-prompt-guard"

const TYPE = "fast-task-dispatch"
const EFFORTS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
const PHASES = ["implementation", "review", "repair"]
const label = /^[A-Za-z0-9_./:@+-]{1,128}$/
const route = /^[A-Za-z0-9_.:@+-]+\/[A-Za-z0-9_./:@+-]+$/
const uuid = /^[a-f0-9-]{36}$/
const hash = (s: string) => createHash("sha256").update(s).digest("hex")
const worker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())
const object = (x: unknown): x is Record<string, unknown> => !!x && typeof x === "object" && !Array.isArray(x)
const terminal = new Set(["completed", "steered", "aborted", "stopped", "error"])
export const REASONS = ["eligible", "reserved", "invalid_packet", "missing_grants", "preflight", "missing_tools", "board_unverified", "dependency", "ownership", "duplicate", "capacity", "busy", "cancelled", "native_submission", "worker_linked", "native_started", "native_terminal", "native_failed", "startup_failed", "submission_unknown", "timeout", "recovery_unknown", "runtime_observed"] as const
export type Reason = typeof REASONS[number]
type State = "ready" | "submitted" | "started" | "blocked" | "terminal"
type Ownership = { self: string, ancestors: string[] }
type Packet = { schemaVersion: 1, approved: true, prompt: string, role: string, model: string, effort: string, maxTurns: number, ownedPaths: string[], dependencies: string[], grants: string[], phase?: string, parentTaskId?: string }
type NativeSource = "subagents:completed" | "subagents:failed" | "subagents:record"
type Attempt = { schemaVersion: 1, coordinatorSessionId: string, taskId: string, attemptId: string, state: State, timestamp: number, reason: Reason, workerId?: string, phase?: string, parentTaskId?: string, requestedModel?: string, requestedEffort?: string, actualModel?: string, actualEffort?: string, actualSource?: "subagents:usage", ownership?: Ownership[], ownershipVersion?: 2, observationSource?: "live" | "recovered", nativeStatus?: "completed" | "steered" | "aborted" | "stopped" | "error", nativeDurationMs?: number, nativeStartedAt?: number, nativeCompletedAt?: number, nativeSource?: NativeSource }
class Refusal extends Error { constructor(readonly code: Reason, readonly field?: string, readonly hint?: string) { super(code) } }
function refuse(code: Reason, field?: string, hint?: string): never { throw new Refusal(code, field, hint) }
const active = (a: Attempt) => a.state === "submitted" || a.state === "started" || (a.state === "ready" && a.reason === "reserved")
const result = (rows: unknown) => ({ content: [{ type: "text" as const, text: JSON.stringify(rows) }], details: rows })

// Resolve the nearest existing ancestor too: two new paths behind a symlink must share a lock.
export function ownershipKeys(paths: string[]): Ownership[] {
  return paths.map(path => {
    if (!isAbsolute(path) || /[\0\r\n*?\[\]{}]/.test(path)) refuse("invalid_packet", "ownedPaths", "absolute_literal_paths")
    let base = resolve(path), tail: string[] = []
    for (;;) {
      try { base = realpathSync(base); break } catch (err) {
        if ((err as NodeJS.ErrnoException).code !== "ENOENT" || dirname(base) === base) refuse("invalid_packet", "ownedPaths", "resolvable_ancestor")
        tail.unshift(basename(base)); base = dirname(base)
      }
    }
    // Conservatively collide case/normalization variants, even on case-sensitive volumes.
    const canonical = join(base, ...tail).normalize("NFD").toLowerCase(), ancestors: string[] = []
    for (let p = canonical;; p = dirname(p)) { ancestors.push(hash(p)); if (dirname(p) === p) break }
    return { self: hash(canonical), ancestors }
  })
}
const overlaps = (a: Ownership[], b: Ownership[]) => a.some(x => b.some(y => x.ancestors.includes(y.self) || y.ancestors.includes(x.self)))

export function validatePacket(value: unknown, ctx: ExtensionToolContext): Packet {
  if (!object(value)) refuse("invalid_packet", "packet", "metadata.fastTask_v1_object")
  const keys = ["schemaVersion", "approved", "prompt", "role", "model", "effort", "maxTurns", "ownedPaths", "dependencies", "grants", "phase", "parentTaskId"]
  if (Object.keys(value).some(k => !keys.includes(k))) refuse("invalid_packet", "packet", "v1_keys_only")
  if (value.schemaVersion !== 1) refuse("invalid_packet", "schemaVersion", "literal_1")
  if (value.approved !== true) refuse("invalid_packet", "approved", "literal_true")
  if (typeof value.prompt !== "string" || !value.prompt.trim() || value.prompt.length > 64000) refuse("invalid_packet", "prompt", "nonempty_string_max_64000")
  if (typeof value.role !== "string" || !label.test(value.role)) refuse("invalid_packet", "role", "role_name_max_128")
  if (typeof value.model !== "string" || !route.test(value.model) || value.model.length > 128) refuse("invalid_packet", "model", "provider/model_max_128")
  if (typeof value.effort !== "string" || !EFFORTS.includes(value.effort)) refuse("invalid_packet", "effort", "off_minimal_low_medium_high_xhigh_max")
  if (typeof value.maxTurns !== "number" || !Number.isSafeInteger(value.maxTurns) || value.maxTurns < 1 || value.maxTurns > 1000) refuse("invalid_packet", "maxTurns", "integer_1_to_1000")
  for (const key of ["ownedPaths", "dependencies", "grants"]) if (!Array.isArray(value[key]) || value[key].length > 100 || value[key].some((x: unknown) => typeof x !== "string" || x.length > 4096)) refuse("invalid_packet", key, "string_array_max_100_items_4096_chars_each")
  const p = value as Packet
  if (!p.grants.length || p.grants.some(g => !g.trim() || !p.prompt.includes(g))) refuse("missing_grants", "grants", "nonempty_verbatim_in_prompt")
  if (p.dependencies.some(id => !label.test(id)) || new Set(p.dependencies).size !== p.dependencies.length) refuse("invalid_packet", "dependencies", "unique_task_ids")
  if (p.phase !== undefined && !PHASES.includes(p.phase)) refuse("invalid_packet", "phase", "implementation_review_repair")
  if (p.parentTaskId !== undefined && (typeof p.parentTaskId !== "string" || !label.test(p.parentTaskId))) refuse("invalid_packet", "parentTaskId", "task_id")
  const role = resolveRole(p.role, ctx.cwd)
  if (!role?.enabled || role.inheritContext || role.runInBackground === false || (role.maxTurns !== undefined && (role.maxTurns === 0 || role.maxTurns > p.maxTurns))) refuse("preflight", "role", "enabled_background_role_within_turn_cap_no_inherited_context")
  const model = role.model ?? p.model, effort = role.thinking ?? p.effort
  if (!route.test(model) || model.length > 128 || !EFFORTS.includes(effort)) refuse("preflight", "role", "explicit_effective_route_and_effort")
  const input = { prompt: p.prompt, model: p.model, thinking: p.effort }
  if (gluedPromptReason(p.prompt)) refuse("preflight", "prompt", "plain_spaced_sentences")
  if (agentRouteReason(input, ctx, role)) refuse("preflight", "model", "available_effective_route_and_supported_effort")
  if (requiredToolsReason(input, role)) refuse("preflight", "prompt", "required_tools_allowed_by_role")
  if (solRationaleReason(input, role)) refuse("preflight", "prompt", "model_rationale_required")
  return p
}

export default function (pi: ExtensionAPI) {
  const attempts = new Map<string, Attempt>()
  let context: ExtensionContext | undefined, busy = false, epoch = 0
  const subscriptions: (() => void)[] = []
  type Tool = ToolLoadout["registered"][number]
  const resumeWrappers = new Map<Tool, { original: Tool["execute"], wrapped: Tool["execute"] }>()
  const protectResumes = (loadout: ToolLoadout) => {
    // Pi 1.5 supplies the executable registry objects, shared by direct and nested calls.
    const tool = loadout.registered.find(t => t.name === "Agent")
    if (tool && !resumeWrappers.has(tool)) {
      const original = tool.execute
      const wrapped: Tool["execute"] = (...args) => {
        const reason = context && agentResumeReason((args[1] as { resume?: unknown }).resume, context)
        if (reason) return Promise.resolve({ content: [{ type: "text", text: reason }], details: undefined, isError: true })
        // No await here: native 0.23.1 selects live vs saved and admits resume synchronously.
        return original(...args)
      }
      tool.execute = wrapped
      resumeWrappers.set(tool, { original, wrapped })
    }
    return {}
  }
  const pending = new Set<() => void>()
  const gates = new Map<string, { parent: string, attempt: Attempt, packet: Packet, signal?: AbortSignal }>()
  const emit = (a: Attempt, state: State, reason: Reason, locks?: Ownership[], observationSource: "live" | "recovered" = "live") => {
    a.state = state; a.reason = reason; a.timestamp = Date.now()
    // An explicit projection: never spread packet, native event, tool result or Error into telemetry.
    const data: Attempt = { schemaVersion: 1, coordinatorSessionId: a.coordinatorSessionId, taskId: a.taskId, attemptId: a.attemptId, state, timestamp: a.timestamp, reason, observationSource }
    for (const key of ["workerId", "phase", "parentTaskId", "requestedModel", "requestedEffort", "actualModel", "actualEffort", "actualSource", "ownershipVersion", "nativeStatus", "nativeDurationMs", "nativeStartedAt", "nativeCompletedAt", "nativeSource"] as const) if (a[key] !== undefined) Object.assign(data, { [key]: a[key] })
    if (locks) data.ownership = locks.map(x => ({ self: x.self, ancestors: [...x.ancestors] }))
    pi.appendEntry(TYPE, data)
  }
  const locate = (event: Record<string, unknown>) => {
    if (typeof event.id !== "string" || !label.test(event.id)) return
    return [...attempts.values()].find(a => a.workerId === event.id || event.description === `fast-task:${a.attemptId}`)
  }
  const bind = (a: Attempt, id: unknown) => {
    if (typeof id !== "string" || !label.test(id) || (a.workerId && a.workerId !== id)) return false
    a.workerId = id; return true
  }
  const nativeEvidence = (a: Attempt, raw: Record<string, unknown>, source: NativeSource) => {
    for (const key of ["nativeStatus", "nativeDurationMs", "nativeStartedAt", "nativeCompletedAt", "nativeSource"] as const) delete a[key]
    a.nativeSource = source
    if (typeof raw.status === "string" && terminal.has(raw.status)) a.nativeStatus = raw.status as Attempt["nativeStatus"]
    const time = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= 8640000000000000
    if (time(raw.startedAt)) a.nativeStartedAt = raw.startedAt
    if (time(raw.completedAt) && (a.nativeStartedAt === undefined || raw.completedAt >= a.nativeStartedAt)) a.nativeCompletedAt = raw.completedAt
    if (source === "subagents:record") {
      if (a.nativeStartedAt !== undefined && a.nativeCompletedAt !== undefined) a.nativeDurationMs = a.nativeCompletedAt - a.nativeStartedAt
    } else if (typeof raw.durationMs === "number" && Number.isFinite(raw.durationMs) && raw.durationMs >= 0 && raw.durationMs <= Number.MAX_SAFE_INTEGER) a.nativeDurationMs = raw.durationMs
  }
  const observe = (name: string, raw: unknown) => {
    if (!context || !object(raw)) return
    const a = locate(raw)
    if (!a || !bind(a, raw.id)) return
    if (name === "usage") {
      if (typeof raw.model === "string" && route.test(raw.model) && raw.model.length <= 128) a.actualModel = raw.model
      if (typeof raw.thinking === "string" && EFFORTS.includes(raw.thinking)) a.actualEffort = raw.thinking
      if (a.actualModel || a.actualEffort) { a.actualSource = "subagents:usage"; emit(a, a.state, "runtime_observed") }
    } else if (name === "started") {
      if (active(a)) emit(a, "started", "native_started")
    } else if (active(a)) {
      nativeEvidence(a, raw, name === "completed" ? "subagents:completed" : "subagents:failed")
      emit(a, "terminal", name === "completed" ? "native_terminal" : "native_failed")
    }
  }
  const restore = (_event: unknown, ctx: ExtensionContext) => {
    if (worker(ctx)) return
    context = ctx
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type !== "custom" || entry.customType !== TYPE || !object(entry.data)) continue
      const d = entry.data
      if (d.schemaVersion !== 1 || typeof d.taskId !== "string" || !label.test(d.taskId) || typeof d.attemptId !== "string" || !uuid.test(d.attemptId) || typeof d.state !== "string" || !["ready", "submitted", "started", "blocked", "terminal"].includes(d.state) || !REASONS.some(r => r === d.reason)) continue
      const old = attempts.get(d.taskId)
      const savedLocks = d.ownership === undefined && old?.attemptId === d.attemptId ? old.ownership : d.ownership
      const version = d.ownership === undefined && old?.attemptId === d.attemptId ? d.ownershipVersion ?? old.ownershipVersion : d.ownershipVersion
      const validLocks = version === 2 && Array.isArray(savedLocks) && savedLocks.length <= 100 && savedLocks.every(x => object(x) && typeof x.self === "string" && /^[a-f0-9]{64}$/.test(x.self) && Array.isArray(x.ancestors) && x.ancestors.length > 0 && x.ancestors[0] === x.self && x.ancestors.every(k => typeof k === "string" && /^[a-f0-9]{64}$/.test(k)))
      const a = { ...d, ownership: validLocks ? savedLocks : undefined, ownershipVersion: validLocks ? 2 : undefined } as Attempt
      for (const key of ["nativeStatus", "nativeDurationMs", "nativeStartedAt", "nativeCompletedAt", "nativeSource"] as const) delete a[key]
      if (d.nativeSource === "subagents:completed" || d.nativeSource === "subagents:failed" || d.nativeSource === "subagents:record") nativeEvidence(a, { status: d.nativeStatus, durationMs: d.nativeDurationMs, startedAt: d.nativeStartedAt, completedAt: d.nativeCompletedAt }, d.nativeSource)
      if (old?.attemptId === a.attemptId) for (const key of ["nativeStatus", "nativeDurationMs", "nativeStartedAt", "nativeCompletedAt", "nativeSource"] as const) delete old[key]
      attempts.set(d.taskId, old?.attemptId === a.attemptId ? Object.assign(old, a) : a)
    }
    // Terminal records are durable native evidence even if the completion event raced shutdown.
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type !== "custom" || entry.customType !== "subagents:record" || !object(entry.data) || typeof entry.data.status !== "string" || !terminal.has(entry.data.status)) continue
      const id = entry.data.id
      const a = [...attempts.values()].find(a => a.workerId === id)
      if (a && active(a)) {
        nativeEvidence(a, entry.data, "subagents:record")
        emit(a, "terminal", entry.data.status === "completed" ? "native_terminal" : "native_failed", undefined, "recovered")
      }
    }
  }
  pi.on("session_start", (event, ctx) => {
    restore(event, ctx)
    if (!context) return
    for (const name of ["started", "completed", "failed", "usage"]) subscriptions.push(pi.events.on(`subagents:${name}`, data => observe(name, data)))
  })
  pi.on("session_tree", restore)
  pi.on("session_shutdown", () => {
    epoch++; context = undefined; busy = false
    for (const cancel of pending) cancel()
    pending.clear(); gates.clear()
    for (const off of subscriptions.splice(0)) off()
    for (const [tool, { original, wrapped }] of resumeWrappers) if (tool.execute === wrapped) tool.execute = original
    resumeWrappers.clear()
  })
  // Native Agent still traverses every other installed guard. This extra gate prevents a late
  // permission prompt or a mutating guard from turning cancellation into an unowned spawn.
  pi.on("tool_call", (event, ctx) => {
    if (worker(ctx)) return
    if (event.toolName === "TaskExecute") return { block: true, reason: "Use fast_task_dispatch for approved packets; native TaskExecute bypasses packet preflight and acceptance dependencies." }
    if (event.toolName !== "Agent") return
    const id = (event.input as { resume?: unknown }).resume
    if (id !== undefined && id !== "" && !pi.getActiveTools().some(n => n === "fast_task_ready" || n === "fast_task_dispatch")) return { block: true, reason: "Agent resume rejected: execution_guard_unavailable. Enable fast_task_ready or fast_task_dispatch before resuming; no worker was dispatched." }
    const resume = agentResumeReason(id, ctx)
    if (resume) return { block: true, reason: resume }
    if (!event.parentToolCallId) return
    const candidates = [...gates.values()].filter(g => g.parent === event.parentToolCallId)
    if (!candidates.length) return
    const i = event.input as Record<string, unknown>
    const gate = candidates.find(g => i.description === `fast-task:${g.attempt.attemptId}`)
    if (!gate) return { block: true, reason: "fast-task-dispatch: preflight" }
    const p = gate.packet, a = gate.attempt
    if (!context || gate.signal?.aborted || !active(a) || i.description !== `fast-task:${a.attemptId}` || i.prompt !== p.prompt || i.subagent_type !== p.role || i.model !== p.model || i.thinking !== p.effort || i.max_turns !== p.maxTurns || i.run_in_background !== true || i.inherit_context !== false || Object.keys(i).some(k => !["prompt", "description", "subagent_type", "model", "thinking", "max_turns", "run_in_background", "inherit_context"].includes(k))) return { block: true, reason: "fast-task-dispatch: preflight" }
  })

  // Native refusals have no details; structured run results may contain these same words.
  pi.on("tool_result", (event, ctx) => {
    if (worker(ctx) || event.toolName !== "Agent" || !(event.input as { resume?: unknown }).resume || event.isError || event.details != null || event.structuredContent !== undefined) return
    const text = event.content.length === 1 && event.content[0].type === "text" ? event.content[0].text : ""
    if (/^Agent "[^"\n]*" is still (?:running|queued) — it can only be resumed once its current run finishes\.\nUse steer_subagent to send it a message mid-run, or get_subagent_result to wait for it\.$/.test(text)) return {
      isError: true,
      content: [{ type: "text", text: "Agent resume rejected: still_running. Use steer_subagent for new information or await its completion notification; no worker was dispatched." }],
    }
    if (/^(?:Agent not found:|Agent "[^"\n]*" (?:has no active session to resume|cannot be resumed)|Failed to resume agent )/.test(text)) return {
      isError: true,
      content: [{ type: "text", text: "Agent resume failed: native_record_unavailable; fresh_handoff_required. Retrieve saved evidence or the notification's <output-file>, inspect partial edits and prepare an explicit approved fresh packet. No automatic fresh dispatch was attempted." }],
    }
  })

  const toolsPresent = (ctx: ExtensionToolContext) => typeof ctx.executeTool === "function" && ["Agent", "TaskGet", "TaskUpdate"].every(n => ctx.tools.some(t => t.name === n))
  const load = async (id: string, ctx: ExtensionToolContext, signal: AbortSignal | undefined, check: () => void) => {
    check()
    const nonce = randomUUID()
    const update = await ctx.executeTool("TaskUpdate", { taskId: id, metadata: { fastDispatchReadToken: nonce } }, { signal })
    check()
    if (update.isError) refuse("board_unverified")
    const r = await ctx.executeTool("TaskGet", { taskId: id }, { signal })
    check()
    if (r.isError || r.result.content.length !== 1 || r.result.content[0].type !== "text") refuse("board_unverified")
    const text = r.result.content[0].text, at = text.lastIndexOf("\nMetadata: ")
    let metadata: unknown
    try { metadata = JSON.parse(text.slice(at + 11)) } catch { refuse("board_unverified") }
    if (at < 0 || !object(metadata) || metadata.fastDispatchReadToken !== nonce || !text.startsWith(`Task #${id}: `)) refuse("board_unverified")
    return metadata
  }
  const accepted = (id: string, ctx: ExtensionToolContext) => {
    const a = attempts.get(id)
    if (!a || a.state !== "terminal" || !a.workerId) return false
    const receipts = ctx.sessionManager.getBranch().filter(e => e.type === "custom" && e.customType === "task-outcome-receipt").map(e => (e as { data?: unknown }).data).filter(d => object(d) && d.boardTaskId === id && d.attemptId === a.attemptId && d.taskId === a.workerId)
    return (receipts.at(-1) as Record<string, unknown> | undefined)?.outcome === "accepted"
  }
  const idsSchema = Type.Array(Type.String({ pattern: "^[A-Za-z0-9_./:@+-]{1,128}$" }), { minItems: 1, maxItems: 50, uniqueItems: true })
  const execute = async (callId: string, ids: string[], capacity: number | undefined, signal: AbortSignal | undefined, ctx: ExtensionToolContext) => {
    if (worker(ctx)) throw new Error("fast-task-dispatch: coordinator_only")
    if (!context || busy) return result({ reason: "busy", rows: [] })
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 50 || ids.some(id => typeof id !== "string" || !label.test(id)) || new Set(ids).size !== ids.length) return result({ reason: "duplicate", rows: [] })
    busy = true
    const run = epoch, rows: { taskId: string, attemptId: string, state: State, reason: Reason, workerId?: string, field?: string, hint?: string }[] = []
    const row = (a: Attempt) => ({ taskId: a.taskId, attemptId: a.attemptId, state: a.state, reason: a.reason, ...(a.workerId ? { workerId: a.workerId } : {}) })
    const check = () => { if (!context || signal?.aborted || run !== epoch) refuse("cancelled") }
    try {
      const count = [...attempts.values()].filter(active).length
      let slots = capacity === undefined ? Infinity : capacity >= count && capacity <= 50 && Number.isInteger(capacity) ? 50 - capacity : 0
      const prepared: { a: Attempt, p: Packet }[] = []
      for (const id of ids) {
        if (!context || run !== epoch) break
        const previous = attempts.get(id)
        if (previous && (previous.ownership || previous.workerId || active(previous) || previous.state === "terminal")) { rows.push({ ...row(previous), reason: "duplicate" }); continue }
        const a: Attempt = previous ?? { schemaVersion: 1, coordinatorSessionId: ctx.sessionManager.getSessionId(), taskId: id, attemptId: randomUUID(), state: "blocked", timestamp: Date.now(), reason: "invalid_packet" }
        attempts.set(id, a)
        try {
          if (!toolsPresent(ctx)) refuse("missing_tools")
          check()
          const meta = await load(id, ctx, signal, check)
          check()
          if (meta.agentId || meta.fastDispatch) refuse("duplicate")
          const p = validatePacket(meta.fastTask, ctx)
          a.requestedModel = p.model; a.requestedEffort = p.effort; a.phase = p.phase; a.parentTaskId = p.parentTaskId
          if (p.dependencies.includes(id) || p.dependencies.some(d => !accepted(d, ctx))) refuse("dependency")
          if ([...attempts.values()].some(other => active(other) && !Array.isArray(other.ownership))) refuse("recovery_unknown")
          const locks = ownershipKeys(p.ownedPaths)
          if ([...attempts.values()].some(other => other !== a && active(other) && overlaps(locks, other.ownership ?? [])) || prepared.some(other => overlaps(locks, other.a.ownership ?? []))) refuse("ownership")
          if (slots <= 0) refuse("capacity")
          emit(a, "ready", "eligible")
          a.ownership = locks; a.ownershipVersion = 2
          prepared.push({ a, p }); slots--
        } catch (err) {
          if (!context || run !== epoch) break
          emit(a, "blocked", err instanceof Refusal ? err.code : "board_unverified")
          rows.push({ ...row(a), ...(err instanceof Refusal && err.field ? { field: err.field, hint: err.hint } : {}) })
        }
      }
      if (!context || run !== epoch) return result({ capacitySource: capacity === undefined ? "not_checked" : "coordinator-ledger", aggregateOccupancy: "unverified", rows })
      if (capacity === undefined) {
        for (const { a } of prepared) { rows.push(row(a)); delete a.ownership }
      } else {
        // All reservations are made synchronously before any startup await. Each map callback
        // reaches native Agent independently; native manager, not this adapter, owns its queue.
        await Promise.all(prepared.map(async ({ a, p }) => {
          if (!context || run !== epoch) return undefined
          if (signal?.aborted) { delete a.ownership; emit(a, "blocked", "cancelled"); rows.push(row(a)); return undefined }
          emit(a, "ready", "reserved", a.ownership)
          const marker = { attemptId: a.attemptId, coordinatorSessionId: a.coordinatorSessionId }
          let sent = false
          try {
            const updated = await ctx.executeTool("TaskUpdate", { taskId: a.taskId, status: "in_progress", metadata: { fastDispatch: marker } }, { signal })
            check()
            const checked = await load(a.taskId, ctx, signal, check)
            check()
            if (updated.isError || !object(checked.fastDispatch) || checked.fastDispatch.attemptId !== a.attemptId || JSON.stringify(checked.fastTask) !== JSON.stringify(p)) refuse("board_unverified")
            check()
            gates.set(`${callId}:${a.attemptId}`, { parent: callId, attempt: a, packet: p, signal })
            sent = true
            emit(a, "submitted", "native_submission")
            const promise = ctx.executeTool("Agent", { prompt: p.prompt, description: `fast-task:${a.attemptId}`, subagent_type: p.role, model: p.model, thinking: p.effort, max_turns: p.maxTurns, run_in_background: true, inherit_context: false }, { signal })
            const settle = promise.then(r => {
              if (run !== epoch || !context) return
              const id = object(r.result.details) ? r.result.details.agentId : undefined
              if (bind(a, id)) { if (active(a)) emit(a, a.state, "worker_linked") }
              // Even an error without an ID can follow admission (for example transcript failure).
              else if (active(a)) emit(a, a.state, "submission_unknown")
            }, () => { if (run === epoch && context && active(a)) emit(a, a.state, "submission_unknown") })
            await new Promise<void>(resolve => {
              let done = false
              const finish = () => { if (done) return; done = true; clearTimeout(timer); pending.delete(cancel); signal?.removeEventListener("abort", cancel); resolve() }
              const cancel = () => { if (run === epoch && context && active(a)) emit(a, a.state, "cancelled"); finish() }
              const timer = setTimeout(() => { if (run === epoch && context && active(a)) emit(a, a.state, "timeout"); finish() }, 30000)
              pending.add(cancel); signal?.addEventListener("abort", cancel, { once: true })
              if (signal?.aborted || run !== epoch) cancel()
              void settle.then(() => { gates.delete(`${callId}:${a.attemptId}`); finish() })
            })
          } catch (err) {
            if (run === epoch && context) {
              if (!sent) { delete a.ownership; emit(a, "blocked", err instanceof Refusal ? err.code : "board_unverified") }
              else emit(a, a.state, "submission_unknown")
            }
          }
          rows.push(row(a))
          return undefined
        }))
      }
      return result({ capacitySource: capacity === undefined ? "not_checked" : "coordinator-ledger", aggregateOccupancy: "unverified", rows })
    } finally { if (run === epoch) busy = false }
  }
  pi.registerTool({ name: "fast_task_ready", label: "Ready tasks", description: "Coordinator bookkeeping: compact readiness for up to 50 approved metadata.fastTask packets; writes only a metadata read nonce. Not a historic task dump or capacity proof.", parameters: Type.Object({ task_ids: idsSchema }, { additionalProperties: false }), prepareLoadout: protectResumes, execute: (id, p, signal, _update, ctx) => execute(id, p.task_ids, undefined, signal, ctx) })
  pi.registerTool({ name: "fast_task_dispatch", label: "Dispatch ready tasks", description: "Coordinator-only concurrent native Agent dispatch by task ID. capacity.active is the coordinator ledger's count of all occupied/reserved campaign lanes, including this adapter's unresolved submissions; not a native/global occupancy measurement. Native Agent owns background queue/caps. No automatic retry, cascade or acceptance.", parameters: Type.Object({ task_ids: idsSchema, capacity: Type.Object({ source: Type.Literal("coordinator-ledger"), active: Type.Integer({ minimum: 0, maximum: 50 }) }, { additionalProperties: false }) }, { additionalProperties: false }), prepareLoadout: protectResumes, execute: (id, p, signal, _update, ctx) => execute(id, p.task_ids, p.capacity.source === "coordinator-ledger" ? p.capacity.active : 50, signal, ctx) })
}
