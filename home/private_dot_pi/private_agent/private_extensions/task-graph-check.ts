import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"

// A task untouched across this many worker completion notifications is reported as stale.
export const STALE_AFTER_PASSES = 3

const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())
const object = (x: unknown): x is Record<string, unknown> => !!x && typeof x === "object" && !Array.isArray(x)
const DEPENDENCY_TEXT = /\b(?:depends on|blocked by|waits? (?:for|on)|after|requires|follows|split from|part of)\s+(?:task\s+)?#\d+/i
const DEPENDENCY_META = ["dependencies", "dependsOn", "depends_on", "blockedBy"]
const PARENT_META = ["parentTaskId", "parent", "parentId"]
const WORKER_META = ["agentId", "workerId"]

type Task = { id: string, status: string, owner?: string, description: string, metadata: Record<string, unknown>, blocks: Set<string>, blockedBy: Set<string>, touched: number }
export type Liveness = (task: { id: string, owner?: string, metadata: Record<string, unknown> }) => boolean | undefined

// The pi-tasks store is private to its extension (task-store.ts / index.ts closure, one store per session), so this ledger
// is rebuilt from the TaskCreate/TaskUpdate calls and results this extension observes, not read from the store.
export class TaskGraph {
  pass = 0
  private tasks = new Map<string, Task>()
  private reported = new Set<string>()

  private ensure(id: string): Task {
    let t = this.tasks.get(id)
    if (!t) { t = { id, status: "pending", description: "", metadata: {}, blocks: new Set(), blockedBy: new Set(), touched: this.pass }; this.tasks.set(id, t) }
    return t
  }
  created(id: string, input: Record<string, unknown>) {
    const t = this.ensure(id)
    t.description = typeof input.description === "string" ? input.description : ""
    t.metadata = object(input.metadata) ? { ...input.metadata } : {}
    t.touched = this.pass
  }
  updated(input: Record<string, unknown>) {
    const id = input.taskId
    if (typeof id !== "string") return
    if (input.status === "deleted") { this.tasks.delete(id); return }
    const t = this.ensure(id)
    if (typeof input.status === "string") t.status = input.status
    if (typeof input.owner === "string") t.owner = input.owner
    if (typeof input.description === "string") t.description = input.description
    if (object(input.metadata)) for (const [k, v] of Object.entries(input.metadata)) { if (v === null) delete t.metadata[k]; else t.metadata[k] = v }
    for (const other of Array.isArray(input.addBlockedBy) ? input.addBlockedBy : []) if (typeof other === "string") { t.blockedBy.add(other); this.ensure(other).blocks.add(id) }
    for (const other of Array.isArray(input.addBlocks) ? input.addBlocks : []) if (typeof other === "string") { t.blocks.add(other); this.ensure(other).blockedBy.add(id) }
    t.touched = this.pass
  }

  // Compact warnings not yet reported; a warning that stops applying may be reported again if it recurs.
  warnings(liveness: Liveness): string[] {
    const current = new Set<string>()
    const stale: string[] = [], noWorker: string[] = [], noLink: string[] = []
    for (const t of this.tasks.values()) {
      if (t.status === "completed") continue
      if (t.status === "in_progress" && liveness(t) === false) { noWorker.push(`#${t.id}`); current.add(`worker:${t.id}`) }
      if (this.pass - t.touched >= STALE_AFTER_PASSES) { stale.push(`#${t.id}`); current.add(`stale:${t.id}`) }
      const names = DEPENDENCY_TEXT.test(t.description) || DEPENDENCY_META.some(k => { const v = t.metadata[k]; return Array.isArray(v) ? v.length > 0 : v !== undefined && v !== null && v !== "" })
      const linked = t.blocks.size > 0 || t.blockedBy.size > 0 || PARENT_META.some(k => t.metadata[k] !== undefined && t.metadata[k] !== "")
      if (names && !linked) { noLink.push(`#${t.id}`); current.add(`link:${t.id}`) }
    }
    const fresh = (kind: string, ids: string[]) => ids.filter(id => !this.reported.has(`${kind}:${id.slice(1)}`))
    const out: string[] = []
    const add = (kind: string, ids: string[], text: string) => { const f = fresh(kind, ids); if (f.length) out.push(`${f.join(", ")} ${text}`) }
    add("worker", noWorker, "in_progress without a live worker ID (owner or metadata.agentId)")
    add("stale", stale, `stale: no update in ${STALE_AFTER_PASSES} worker completions`)
    add("link", noLink, "names a dependency but has no parent or blockedBy/blocks link")
    this.reported = current
    return out
  }
}

type Manager = { getRecord?: (id: string) => { status?: string } | undefined }
// Live means pi-subagents' own manager reports the worker running or queued. Without a manager (or any ID) only an
// absent ID is provable, so an unverifiable ID is not flagged.
export function workerLiveness(entries: readonly { type: string, customType?: string, data?: unknown }[], manager: Manager | undefined = (globalThis as Record<symbol, Manager | undefined>)[Symbol.for("pi-subagents:manager")]): Liveness {
  const dispatch = new Map<string, { workerId?: unknown, state?: unknown }>()
  for (const e of entries) if (e.type === "custom" && e.customType === "fast-task-dispatch" && object(e.data) && typeof e.data.taskId === "string") dispatch.set(e.data.taskId, e.data)
  return (task) => {
    const attempt = dispatch.get(task.id)
    const ids = [task.owner, ...WORKER_META.map(k => task.metadata[k]), attempt?.workerId].filter((x): x is string => typeof x === "string" && x !== "")
    if (!ids.length) return attempt && (attempt.state === "submitted" || attempt.state === "ready") ? undefined : false
    if (typeof manager?.getRecord !== "function") return undefined
    try { return ids.some(id => { const s = manager.getRecord!(id)?.status; return s === "running" || s === "queued" }) } catch { return undefined }
  }
}

const textOf = (content: readonly { type: string, text?: string }[]) => content.find(c => c.type === "text")?.text ?? ""

export default function (pi: ExtensionAPI) {
  let graph = new TaskGraph()
  let context: ExtensionContext | undefined
  const subscriptions: (() => void)[] = []
  const check = (ctx: ExtensionContext) => graph.warnings(workerLiveness(ctx.sessionManager.getBranch()))
  pi.on("session_start", (_event, ctx) => {
    if (isWorker(ctx)) return
    graph = new TaskGraph(); context = ctx
    for (const name of ["completed", "failed"]) subscriptions.push(pi.events.on(`subagents:${name}`, () => {
      if (!context) return
      graph.pass++
      const found = check(context)
      if (found.length) context.ui.notify(`Task graph: ${found.join("; ")}`, "warning")
    }))
  })
  pi.on("session_shutdown", () => { context = undefined; for (const off of subscriptions.splice(0)) off() })
  pi.on("tool_result", (event, ctx) => {
    if (isWorker(ctx) || event.isError || (event.toolName !== "TaskCreate" && event.toolName !== "TaskUpdate")) return
    if (event.toolName === "TaskCreate") {
      const id = textOf(event.content).match(/^Task #(\S+) created successfully/)?.[1]
      if (!id) return
      graph.created(id, event.input)
    } else {
      if (/not found$/.test(textOf(event.content))) return
      graph.updated(event.input)
    }
    // Nested calls (fast_task_dispatch bookkeeping) are recorded but not judged mid-dispatch.
    if (event.parentToolCallId) return
    const found = check(ctx)
    if (found.length) return { content: [...event.content, { type: "text" as const, text: `\nTask graph warning: ${found.join("; ")}` }] }
  })
}
