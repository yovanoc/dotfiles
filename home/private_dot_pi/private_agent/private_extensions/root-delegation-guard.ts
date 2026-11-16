import { statfsSync } from "node:fs"
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"

// Same worker marker as fast-task-dispatch.ts and task-outcome-receipt.ts: only workers carry an active agent.
const isWorker = (ctx: ExtensionContext) => /<active_agent\s+name=/.test(ctx.getSystemPrompt())

export const ROOT_BASH_ENV = "PI_ROOT_BASH"
export const MIN_FREE_BYTES = 5 * 1024 ** 3
type Statfs = (path: string) => { bavail: number | bigint, bsize: number | bigint }

export function rootBashReason(enabled: boolean): string | undefined {
  if (enabled) return
  return `Root coordinator bash is blocked: delegate this command to a worker packet (fast_task_dispatch or Agent). The user can allow it with /root-bash on or ${ROOT_BASH_ENV}=1 before launching Pi.`
}

// Fresh dispatch only; resumes and retrievals (fast_task_ready, get_subagent_result) are never blocked.
// A failing statfs does not block: the guard is advisory protection against ENOSPC, not a gate on the tool.
export function diskReason(cwd: string, statfs: Statfs = statfsSync as Statfs): string | undefined {
  let free: number
  try { const s = statfs(cwd); free = Number(s.bavail) * Number(s.bsize) } catch { return }
  if (!(free < MIN_FREE_BYTES)) return
  return `Dispatch blocked: ${(free / 1024 ** 3).toFixed(1)} GiB free on the filesystem of ${cwd} (minimum 5 GiB); ENOSPC risk for worker edits and builds. Free disk space, then dispatch again. Resumes and result retrieval are not blocked.`
}

export function createRootDelegationGuard(pi: ExtensionAPI, deps: { statfs?: Statfs, env?: NodeJS.ProcessEnv } = {}) {
  const env = deps.env ?? process.env
  let allowed = false
  pi.registerCommand("root-bash", {
    description: "Allow or block bash in the root coordinator: /root-bash on|off|status (default off)",
    handler: async (args, ctx) => {
      const arg = args.trim().toLowerCase()
      if (arg === "on" || arg === "off") allowed = arg === "on"
      else if (arg !== "" && arg !== "status") return ctx.ui.notify("Usage: /root-bash on|off|status", "warning")
      ctx.ui.notify(`Root bash is ${allowed || env[ROOT_BASH_ENV] === "1" ? "allowed" : "blocked"}.`, "info")
    },
  })
  pi.on("tool_call", (event, ctx) => {
    if (isWorker(ctx)) return
    let reason: string | undefined
    if (event.toolName === "bash") reason = rootBashReason(allowed || env[ROOT_BASH_ENV] === "1")
    else if (event.toolName === "fast_task_dispatch") reason = diskReason(ctx.cwd, deps.statfs)
    else if (event.toolName === "Agent") {
      const resume = (event.input as { resume?: unknown }).resume
      if (resume === undefined || resume === "") reason = diskReason(ctx.cwd, deps.statfs)
    }
    if (reason) return { block: true, reason }
  })
}

export default function (pi: ExtensionAPI) {
  createRootDelegationGuard(pi)
}
