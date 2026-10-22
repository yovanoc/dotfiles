import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { CodexbarRunner } from "./api.ts";

const exec = promisify(execFile);
const run: CodexbarRunner = async (file, args, options) => exec(file, args, options);
const MAX_OUTPUT_BYTES = 64 * 1024;
type Failure = "dependency-unavailable" | "query-failed" | "timeout" | "cancelled";
export type CreditsObservation = {
  source: "codexbar-codex-web" | null;
  capturedAt: number | null;
  status: "fresh" | "unavailable";
  reason: "ok" | Failure;
  remainingCredits: number | null;
  balanceIsWorkspace: boolean | null;
};
const record = (value: unknown): Record<string, unknown> | undefined =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
const unavailable = (reason: Failure): CreditsObservation => ({
  source: null, capturedAt: null, status: "unavailable", reason, remainingCredits: null, balanceIsWorkspace: null,
});

export function parseCodexbarCredits(json: string, capturedAt: number): CreditsObservation {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new Error("Invalid credits response");
  }
  if (!Array.isArray(parsed)) throw new Error("Invalid credits response");
  const matching = parsed.filter((item) => record(item)?.provider === "codex");
  if (matching.length !== 1) throw new Error("Missing or duplicate provider");
  const provider = record(matching[0]);
  const credits = record(provider?.credits);
  if (provider?.source !== "openai-web" || !credits || credits.balanceReadSucceeded !== true || typeof credits.balanceIsWorkspace !== "boolean"
    || typeof credits.remaining !== "number" || !Number.isFinite(credits.remaining) || credits.remaining < 0
    || credits.remaining > Number.MAX_SAFE_INTEGER || !Number.isFinite(capturedAt) || capturedAt < 0
    || !Number.isFinite(new Date(capturedAt).getTime())) throw new Error("Invalid credits balance");
  return {
    source: "codexbar-codex-web", capturedAt, status: "fresh", reason: "ok",
    remainingCredits: credits.remaining, balanceIsWorkspace: credits.balanceIsWorkspace,
  };
}

export async function observeCodexbarCredits(
  signal?: AbortSignal,
  timeoutMs = 15000,
  clock: () => number = Date.now,
  runner: CodexbarRunner = run,
): Promise<CreditsObservation> {
  const timeout = AbortSignal.timeout(Math.max(1, timeoutMs));
  const active = signal ? AbortSignal.any([signal, timeout]) : timeout;
  let rejectAbort!: () => void;
  const interrupted = new Promise<never>((_resolve, reject) => {
    rejectAbort = () => reject(new Error("Observation interrupted"));
    if (active.aborted) rejectAbort();
    else active.addEventListener("abort", rejectAbort, { once: true });
  });
  try {
    const work = async () => {
      active.throwIfAborted();
      // Explicit web source avoids CodexBar's automatic CLI/inference-agent fallback.
      const result = await runner("codexbar", ["usage", "--provider", "codex", "--source", "web", "--web-timeout", "8", "--json"], {
        encoding: "utf8", maxBuffer: MAX_OUTPUT_BYTES, signal: active,
      });
      active.throwIfAborted();
      const output = typeof result.stdout === "string" ? result.stdout : result.stdout.toString("utf8");
      if (Buffer.byteLength(output, "utf8") > MAX_OUTPUT_BYTES) throw new Error("Credits output exceeded the size limit");
      return parseCodexbarCredits(output, clock());
    };
    return await Promise.race([work(), interrupted]);
  } catch (error) {
    return unavailable(signal?.aborted ? "cancelled" : timeout.aborted ? "timeout" : record(error)?.code === "ENOENT" ? "dependency-unavailable" : "query-failed");
  } finally {
    active.removeEventListener("abort", rejectAbort);
  }
}
