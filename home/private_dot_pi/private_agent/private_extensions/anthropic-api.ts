import { appendFile, readFile } from "node:fs/promises"
import { join } from "node:path"
import { getAgentDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent"

// Temporary prepaid Console key: provider "anthropic-api" in models.json, key in Keychain service "anthropic-api".
// Remove this file, its models.json provider and the quota-status entry when the credits expire.
export const PROVIDER = "anthropic-api"
const LEDGER = join(getAgentDir(), "anthropic-api-spend.jsonl")
// Anthropic's 400 when prepaid credits or a spend limit run out.
const OUT_OF_CREDITS = /credit balance is too low|reached your specified (workspace )?API usage limits/i

type Entry = { usd?: number; exhausted?: boolean }

// Pi-local cumulative cost estimate only; refused requests are not a percentage quota or a balance.
export function summarize(text: string): { spentUsd: number; exhausted: boolean } {
  let spentUsd = 0
  let exhausted = false
  for (const line of text.split("\n")) {
    if (!line) continue
    const entry = JSON.parse(line) as Entry
    if (entry.exhausted) exhausted = true
    else if (typeof entry.usd === "number" && Number.isFinite(entry.usd) && entry.usd >= 0) { spentUsd += entry.usd; exhausted = false } // a later success means credits were topped up
  }
  return { spentUsd, exhausted }
}

export async function readLedger() {
  return summarize(await readFile(LEDGER, "utf8").catch((error) => {
    if (error.code === "ENOENT") return ""
    throw error
  }))
}

export default function (pi: ExtensionAPI) {
  pi.on("message_end", async ({ message }) => {
    if (message.role !== "assistant" || message.provider !== PROVIDER) return
    const usd = message.usage?.cost?.total
    const exhausted = message.stopReason === "error" && OUT_OF_CREDITS.test(message.errorMessage ?? "")
    if (exhausted || usd) await appendFile(LEDGER, JSON.stringify({ t: Date.now(), model: message.model, ...(exhausted ? { exhausted } : { usd }) }) + "\n")
  })
}
