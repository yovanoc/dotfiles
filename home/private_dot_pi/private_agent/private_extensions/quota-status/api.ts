import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { unavailable, type Observation } from "./quota.ts";

const COMMAND = "codexbar";
const ARGS = ["usage", "--provider", "claudeplatform", "--source", "web", "--json"];
const MAX_OUTPUT_BYTES = 64 * 1024;
const exec = promisify(execFile);

export type RunnerOptions = { encoding: "utf8"; maxBuffer: number; signal: AbortSignal };
export type CodexbarRunner = (file: string, args: string[], options: RunnerOptions) => Promise<{ stdout: string | Buffer }>;
const run: CodexbarRunner = async (file, args, options) => exec(file, args, options);

const record = (value: unknown): Record<string, unknown> | undefined =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : undefined;

const usdText = /^\$(0|[1-9]\d*|[1-9]\d{0,2}(?:,\d{3})+)\.(\d{2})$/u;
const grantText = /^\$(0|[1-9]\d*|[1-9]\d{0,2}(?:,\d{3})+)\.(\d{2})\s+of\s+\$(0|[1-9]\d*|[1-9]\d{0,2}(?:,\d{3})+)\.(\d{2})\s+left(?: · (.+))?$/u;
const months: Record<string, number> = { Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12 };

function dollars(whole: string, cents: string): number {
  const amount = BigInt(whole.replaceAll(",", "")) * 100n + BigInt(cents);
  if (amount > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("USD value out of range");
  return Number(amount) / 100;
}

function parseUsdText(value: unknown): number {
  if (typeof value !== "string") throw new Error("Invalid USD amount");
  const match = usdText.exec(value);
  if (!match) throw new Error("Invalid USD amount");
  return dollars(match[1], match[2]);
}

function parseBalance(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || !/^\d+(?:\.\d{1,2})?$/u.test(String(value)) || !Number.isSafeInteger(Math.round(value * 100))) {
    throw new Error("Invalid balance");
  }
  return value;
}

function parseExpiry(value: unknown, capturedAt: number): string | null {
  if (value === undefined || value === null || (typeof value === "string" && (!value.trim() || /^(?:Expires\s+)?unknown$/iu.test(value.trim())))) return null;
  if (typeof value !== "string") throw new Error("Invalid grant expiry");
  const match = /^Expires ([A-Z][a-z]{2}) (\d{1,2})(?:, (\d{4}))? \(UTC\)$/u.exec(value);
  const month = match && months[match[1]];
  const year = match ? Number(match[3] ?? new Date(capturedAt).getUTCFullYear()) : 0;
  if (!match || !month || year < 1000) throw new Error("Invalid grant expiry");
  const isoDate = `${year}-${String(month).padStart(2, "0")}-${match[2].padStart(2, "0")}`;
  const date = new Date(`${isoDate}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== isoDate) throw new Error("Invalid grant expiry");
  return isoDate;
}

function parseGrant(value: unknown, secondaryValue: unknown, capturedAt: number) {
  if (typeof value !== "string") return undefined;
  const match = grantText.exec(value);
  if (!match) return undefined;
  const remainingUsd = dollars(match[1], match[2]);
  const grantUsd = dollars(match[3], match[4]);
  if (remainingUsd > grantUsd) throw new Error("Invalid grant amount");
  return { label: "Prepaid grant" as const, grantUsd, remainingUsd, expiresAt: parseExpiry(match[5] ?? secondaryValue, capturedAt) };
}

export function parseCodexbarUsage(json: string, capturedAt: number): Observation {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new Error("Invalid usage response");
  }
  if (!Array.isArray(parsed)) throw new Error("Invalid usage response");
  const matching = parsed.filter((item) => record(item)?.provider === "claudeplatform");
  if (matching.length !== 1) throw new Error("Missing or duplicate provider");
  const provider = record(matching[0]);
  const usage = record(provider?.usage);
  const cost = record(usage?.providerCost);
  const capturedDate = new Date(capturedAt);
  if (!usage || !cost || typeof capturedAt !== "number" || !Number.isFinite(capturedAt) || !Number.isFinite(capturedDate.getTime()) || capturedAt < 0) throw new Error("Missing provider cost");
  const totalBalanceUsd = parseBalance(cost.balance);
  if (!Array.isArray(usage?.details)) throw new Error("Missing cost details");

  const grants: NonNullable<Observation["console"]>["grants"] = [];
  let monthSpendUsd: number | null | undefined;
  for (const laneName of ["primary", "secondary"] as const) {
    const laneValue = usage[laneName];
    if (laneValue === undefined || laneValue === null) continue;
    const lane = record(laneValue);
    if (!lane) throw new Error("Invalid provider lane");
    const value = lane.resetDescription;
    const grant = parseGrant(value, undefined, capturedAt);
    if (grant) grants.push(grant);
    else if (typeof value === "string" && value.startsWith("$") && /\b(?:of|left)\b/u.test(value)) throw new Error("Invalid grant detail");
  }
  for (const rawSection of usage.details) {
    const section = record(rawSection);
    if (!section || typeof section.title !== "string" || !Array.isArray(section.rows)) throw new Error("Invalid cost section");
    for (const raw of section.rows) {
      const row = record(raw);
      if (!row) throw new Error("Invalid cost detail");
      const unavailableSpend = section.title === "Billing" && row.label === "Spend" && row.value === "Unavailable";
      if (unavailableSpend) {
        if (monthSpendUsd !== undefined) throw new Error("Duplicate month spend");
        monthSpendUsd = null;
        continue;
      }
      if (row.label === "This month (UTC)") {
        if (monthSpendUsd !== undefined) throw new Error("Duplicate month spend");
        monthSpendUsd = parseUsdText(row.value);
        continue;
      }
      const grant = parseGrant(row.value, row.secondaryValue, capturedAt);
      if (grant) grants.push(grant);
      else if (typeof row.value === "string" && row.value.startsWith("$") && /\b(?:of|left)\b/u.test(row.value)) throw new Error("Invalid grant detail");
    }
  }
  if (monthSpendUsd === undefined) monthSpendUsd = null;
  return {
    provider: "anthropic-api",
    source: "codexbar-console-web",
    capturedAt,
    status: "fresh",
    reason: "ok",
    windows: [],
    console: { totalBalanceUsd, grants, monthSpendUsd },
  };
}

function isMissingExecutable(error: unknown): boolean {
  return record(error)?.code === "ENOENT";
}

async function piLocalRefusal(ledger: () => Promise<{ spentUsd: number; exhausted: boolean }>) {
  try {
    return (await ledger()).exhausted === true
      ? { source: "pi-local-exhausted-refusal" as const, status: "observed" as const }
      : undefined;
  } catch {
    return undefined;
  }
}

export async function observeAnthropicApi(
  ledger: () => Promise<{ spentUsd: number; exhausted: boolean }>,
  signal?: AbortSignal,
  timeoutMs = 15000,
  clock: () => number = Date.now,
  runner: CodexbarRunner = run,
): Promise<Observation> {
  const timeout = AbortSignal.timeout(Math.max(1, timeoutMs));
  const active = signal ? AbortSignal.any([signal, timeout]) : timeout;
  let rejectAbort!: () => void;
  const interrupted = new Promise<never>((_resolve, reject) => {
    rejectAbort = () => reject(new Error("Observation interrupted"));
    if (active.aborted) rejectAbort();
    else active.addEventListener("abort", rejectAbort, { once: true });
  });
  let localRefusal: Awaited<ReturnType<typeof piLocalRefusal>> = undefined;
  const refusal = piLocalRefusal(ledger).then((value) => {
    localRefusal = value;
    return value;
  });
  let observation: Observation;
  try {
    const work = async () => {
      active.throwIfAborted();
      const result = await runner(COMMAND, [...ARGS], { encoding: "utf8", maxBuffer: MAX_OUTPUT_BYTES, signal: active });
      active.throwIfAborted();
      const output = typeof result.stdout === "string" ? result.stdout : result.stdout.toString("utf8");
      if (Buffer.byteLength(output, "utf8") > MAX_OUTPUT_BYTES) throw new Error("Usage output exceeded the size limit");
      return parseCodexbarUsage(output, clock());
    };
    const [live, localRefusal] = await Promise.race([Promise.all([work(), refusal]), interrupted]);
    observation = localRefusal ? { ...live, piLocalRefusal: localRefusal } : live;
  } catch (error) {
    const reason = signal?.aborted ? "cancelled" : timeout.aborted ? "timeout" : isMissingExecutable(error) ? "dependency-unavailable" : "query-failed";
    observation = unavailable("anthropic-api", reason);
    if (localRefusal) observation = { ...observation, piLocalRefusal: localRefusal };
  } finally {
    active.removeEventListener("abort", rejectAbort);
  }
  return observation;
}
