import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

export const HANDOFF_COMPACTIONS = 5

export function handoffNotice(compactions: number): string | undefined {
  if (compactions < HANDOFF_COMPACTIONS) return
  return `This session has compacted ${compactions} times. Finish or park running lanes, write a handoff (open tasks, grants, worker IDs, next packets) and continue in a fresh session.`
}

export default function (pi: ExtensionAPI) {
  pi.on("session_compact", (_event, ctx) => {
    // Subagent sessions run without UI; only interactive coordinator sessions hand off.
    if (!ctx.hasUI) return
    const notice = handoffNotice(ctx.sessionManager.getBranch().filter((entry) => entry.type === "compaction").length)
    if (!notice) return
    ctx.ui.notify(notice, "warning")
    pi.sendMessage({ customType: "compaction-handoff", content: notice, display: true }, { deliverAs: "nextTurn" })
  })
}
