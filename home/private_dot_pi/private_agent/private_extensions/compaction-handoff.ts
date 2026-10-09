import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

export const HANDOFF_COMPACTIONS = 5

export function handoffNotice(compactions: number, cwd: string): string | undefined {
  if (compactions < HANDOFF_COMPACTIONS) return
  return `This session has compacted ${compactions} times. Dispatch no new workers. Finish or park running lanes, then write ${cwd}/tasks/handoff.md (open tasks, grants verbatim, worker IDs, next packets, evidence paths) and end your reply with exactly this fenced block, filled in, for the user to paste into a new session:

\`\`\`text
Work in ${cwd}. Read ${cwd}/tasks/handoff.md and continue. Already authorized: <grants>. Next: <one line>.
\`\`\``
}

export default function (pi: ExtensionAPI) {
  pi.on("session_compact", (_event, ctx) => {
    // Subagent sessions run without UI; only interactive coordinator sessions hand off.
    if (!ctx.hasUI) return
    const notice = handoffNotice(ctx.sessionManager.getBranch().filter((entry) => entry.type === "compaction").length, ctx.cwd)
    if (!notice) return
    ctx.ui.notify(notice.split("\n")[0], "warning")
    // "steer" reaches the model before its next response; "nextTurn" waited for the next user prompt (hours).
    pi.sendMessage({ customType: "compaction-handoff", content: notice, display: true }, { deliverAs: "steer" })
  })
}
