import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

const DEFAULT_MAX_TIMEOUT_SECONDS = 3600
const MAX_TIMEOUT_ENV = "PI_BASH_MAX_TIMEOUT_SECONDS"

export function validateBashTimeout(timeout: unknown, configuredMax: unknown = DEFAULT_MAX_TIMEOUT_SECONDS): string | undefined {
  const parsedMax = typeof configuredMax === "string" ? Number(configuredMax) : configuredMax
  const maxSeconds = typeof parsedMax === "number" && Number.isFinite(parsedMax) && parsedMax > 0
    ? parsedMax
    : DEFAULT_MAX_TIMEOUT_SECONDS

  if (typeof timeout !== "number" || !Number.isFinite(timeout) || timeout <= 0) {
    return "Set a finite, positive Bash timeout in seconds (for example, 120)."
  }
  if (timeout > maxSeconds) {
    return `Bash timeout exceeds ${maxSeconds} seconds. For longer commands, set ${MAX_TIMEOUT_ENV}=<seconds> before launching Pi (for example, ${MAX_TIMEOUT_ENV}=7200 pi).`
  }
}

export default function (pi: ExtensionAPI) {
  const configuredMax = process.env[MAX_TIMEOUT_ENV]
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return

    const reason = validateBashTimeout(event.input.timeout, configuredMax)
    return reason ? { block: true, reason } : undefined
  })
}
