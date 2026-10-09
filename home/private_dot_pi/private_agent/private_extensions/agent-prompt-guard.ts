import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

// Glued packets ("Localreversibleedits", "task1220") read badly and hurt small models most.
// Same shape as the scripts/pi-session-audit smushed-prompt metric, counting all whitespace.
export function gluedPromptReason(prompt: unknown): string | undefined {
  if (typeof prompt !== "string" || prompt.length <= 200) return
  const perThousand = ((prompt.match(/\s/g)?.length ?? 0) * 1000) / prompt.length
  if (perThousand >= 80) return
  return `Agent prompt rejected: ${Math.round(perThousand)} whitespace characters per 1000 (minimum 80). Rewrite it for a stranger: plain sentences with spaces, full paths, no glued words or task/hash shorthand, then dispatch again.`
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    if (event.toolName !== "Agent") return
    const reason = gluedPromptReason((event.input as { prompt?: unknown }).prompt)
    if (reason) return { block: true, reason }
  })
}
