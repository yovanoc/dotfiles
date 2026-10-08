/*
 * MIT License
 * Copyright (c) 2026 narumiruna
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import { createHash } from "node:crypto";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { UsageBucket } from "@narumitw/pi-usage/src/types.ts";
import { sanitizeBuckets, unavailable, type Observation, type Reason } from "./quota.ts";

const PROVIDER = "anthropic" as const;
const ENDPOINT = "https://api.anthropic.com/api/oauth/usage";
const MAX_BODY_BYTES = 64 * 1024;
const LEGACY_LIMITS = [
  ["five_hour", "Five-hour", 300],
  ["seven_day", "Weekly", 10080],
  ["seven_day_sonnet", "Weekly Sonnet", 10080],
  ["seven_day_opus", "Weekly Opus", 10080],
  ["seven_day_oauth_apps", "Weekly OAuth apps", 10080],
] as const;

type AnthropicAuth = { token: string; fingerprint: string };
type RequestAuth = { apiKey?: string; headers?: Record<string, string | null>; baseUrl?: string };
type AuthEntry = { present: boolean; value?: string | null };
type WindowDefinition = { label: string; minutes?: number };

export function normalizeAnthropicUsagePayload(payload: unknown, capturedAt: number): Observation {
  const value = record(payload);
  if (!value) return sanitizeBuckets(PROVIDER, capturedAt, []);
  const structured = Array.isArray(value.limits)
    ? value.limits.flatMap((entry, index) => normalizeStructuredLimit(entry, index))
    : [];
  const buckets = structured.length ? structured : LEGACY_LIMITS.flatMap(([key, label, minutes]) => {
    if (!(key in value)) return [];
    return [normalizeBucket(key, label, minutes, value[key])];
  });
  return sanitizeBuckets(PROVIDER, capturedAt, buckets);
}

function normalizeStructuredLimit(value: unknown, index: number): UsageBucket[] {
  const entry = record(value);
  if (!entry) return [];
  const kind = typeof entry.kind === "string" ? entry.kind.toLowerCase() : "";
  const definition = structuredWindow(kind, entry);
  if (!definition) return [];
  return [normalizeBucket(`limit-${index}`, definition.label, definition.minutes, entry)];
}

function structuredWindow(kind: string, entry: Record<string, unknown>): WindowDefinition | undefined {
  if (kind === "session") return { label: "Five-hour", minutes: 300 };
  if (kind === "weekly_all") return { label: "Weekly", minutes: 10080 };
  if (kind === "weekly_scoped") {
    const modelName = record(record(entry.scope)?.model)?.display_name;
    const normalized = typeof modelName === "string" ? modelName.trim().toLowerCase() : "";
    if (normalized === "sonnet") return { label: "Weekly Sonnet", minutes: 10080 };
    if (normalized === "opus") return { label: "Weekly Opus", minutes: 10080 };
    return { label: "Quota window", minutes: 10080 };
  }
  return undefined;
}

function normalizeBucket(id: string, label: string, knownMinutes: number | undefined, value: unknown): UsageBucket {
  const entry = record(value);
  const used = firstNonnegative(entry?.percent, entry?.utilization, entry?.used_percent);
  const resetsAt = epochSeconds(entry?.resets_at ?? entry?.reset_at ?? entry?.resetsAt);
  const minutes = knownMinutes ?? positiveMinutes(entry);
  return {
    id,
    label,
    unit: "percent",
    ...(used === undefined ? {} : { used }),
    ...(minutes === undefined ? {} : { windowMinutes: minutes }),
    ...(resetsAt === undefined ? {} : { resetsAt }),
  };
}

function positiveMinutes(value: Record<string, unknown> | undefined): number | undefined {
  if (!value) return undefined;
  const minutes = firstNonnegative(value.window_minutes, value.windowMinutes);
  if (minutes !== undefined && minutes > 0) return minutes;
  const seconds = firstNonnegative(value.window_seconds, value.windowSeconds);
  return seconds !== undefined && seconds > 0 ? Math.ceil(seconds / 60) : undefined;
}

function firstNonnegative(...values: unknown[]): number | undefined {
  return values.find((value): value is number => typeof value === "number" && Number.isFinite(value) && value >= 0);
}

function epochSeconds(value: unknown): number | undefined {
  if (typeof value === "number") return Number.isFinite(value) && value >= 0 && value <= 253402300799 ? value : undefined;
  if (typeof value !== "string" || !value.trim()) return undefined;
  if (/^\d+(?:\.\d+)?$/u.test(value)) {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= 253402300799 ? parsed : undefined;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed / 1000) : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

function officialOrigin(value: string | undefined): boolean {
  try {
    return new URL(value ?? "").origin === "https://api.anthropic.com";
  } catch {
    return false;
  }
}

function authHeader(headers: RequestAuth["headers"]): AuthEntry {
  const key = Object.keys(headers ?? {}).find((name) => name.toLowerCase() === "authorization");
  return key === undefined ? { present: false } : { present: true, value: headers?.[key] };
}

function bearerToken(auth: RequestAuth): string | undefined {
  const authorization = authHeader(auth.headers);
  if (authorization.present) {
    if (typeof authorization.value !== "string") throw new Error("Anthropic authorization override is empty.");
    const match = /^Bearer\s+(\S+)$/iu.exec(authorization.value.trim());
    if (!match) throw new Error("Anthropic authorization override is invalid.");
    return match[1];
  }
  return typeof auth.apiKey === "string" && auth.apiKey.trim() ? auth.apiKey.trim() : undefined;
}

async function resolveAnthropicAuth(ctx: ExtensionContext): Promise<AnthropicAuth | undefined> {
  const registry = ctx.modelRegistry;
  const selected = ctx.model?.provider === PROVIDER ? ctx.model : undefined;
  const model = selected ?? registry.getAll().find((candidate) => candidate.provider === PROVIDER);
  const provider = registry.getProvider(PROVIDER);
  if (!model || !provider) return undefined;
  if (!officialOrigin(provider.baseUrl) || !officialOrigin(model.baseUrl)) throw new Error("Anthropic usage origin is not official.");

  const resolved = await registry.getProviderAuth(PROVIDER);
  if (!resolved || resolved.source !== "OAuth" || !registry.isUsingOAuth(model)) return undefined;
  if (resolved.auth.baseUrl !== undefined && !officialOrigin(resolved.auth.baseUrl)) throw new Error("Anthropic resolved auth origin is not official.");
  const providerToken = bearerToken(resolved.auth);
  if (!providerToken) return undefined;
  let token = providerToken;

  if (selected) {
    const modelAuth = await registry.getApiKeyAndHeaders(selected);
    if (!modelAuth.ok) throw new Error("Anthropic selected-model auth could not be resolved.");
    if (modelAuth.baseUrl !== undefined && !officialOrigin(modelAuth.baseUrl)) throw new Error("Anthropic model auth origin is not official.");
    const modelAuthorization = authHeader(modelAuth.headers);
    if (modelAuthorization.present && (typeof modelAuthorization.value !== "string" || !modelAuthorization.value.trim())) {
      throw new Error("Anthropic selected-model authorization override is empty.");
    }
    const modelToken = bearerToken(modelAuth);
    if (modelToken && modelToken !== providerToken) throw new Error("Anthropic selected-model identity changed.");
    token = modelToken ?? providerToken;
  }

  return { token, fingerprint: createHash("sha256").update(token).digest("hex") };
}

async function fetchAnthropicUsage(auth: AnthropicAuth, signal: AbortSignal): Promise<unknown> {
  const response = await fetch(ENDPOINT, {
    method: "GET",
    headers: { Authorization: `Bearer ${auth.token}` },
    redirect: "error",
    signal,
  });
  if (response.redirected || !response.ok || !response.body) throw new Error("Anthropic usage request failed.");

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  const cancelReader = () => void reader.cancel().catch(() => undefined);
  if (signal.aborted) cancelReader();
  else signal.addEventListener("abort", cancelReader, { once: true });
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new Error("Anthropic usage response exceeded the size limit.");
      }
      chunks.push(value);
    }
  } finally {
    signal.removeEventListener("abort", cancelReader);
    reader.releaseLock();
  }
  if (signal.aborted) throw new Error("Anthropic usage request was cancelled.");
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new Error("Anthropic usage response was invalid.");
  }
}

export async function observeAnthropic(
  ctx: ExtensionContext,
  signal?: AbortSignal,
  timeoutMs = 15000,
): Promise<Observation> {
  const controller = new AbortController();
  let stopped: "timeout" | "cancelled" | undefined;
  let phase: Reason = "auth-failed";
  let stop!: (observation: Observation) => void;
  const interruption = new Promise<Observation>((resolve) => { stop = resolve; });
  const interrupt = (reason: "timeout" | "cancelled") => {
    if (stopped) return;
    stopped = reason;
    controller.abort();
    stop(unavailable(PROVIDER, reason));
  };
  const abort = () => interrupt("cancelled");
  if (signal?.aborted) abort();
  else signal?.addEventListener("abort", abort, { once: true });
  const timer = setTimeout(() => interrupt("timeout"), timeoutMs);
  const work = async (): Promise<Observation> => {
    try {
      if (stopped) return unavailable(PROVIDER, stopped);
      const auth = await resolveAnthropicAuth(ctx);
      if (stopped) return unavailable(PROVIDER, stopped);
      if (!auth) return unavailable(PROVIDER, "auth-unavailable");
      phase = "query-failed";
      const payload = await fetchAnthropicUsage(auth, controller.signal);
      if (stopped) return unavailable(PROVIDER, stopped);
      phase = "auth-failed";
      const current = await resolveAnthropicAuth(ctx);
      if (stopped) return unavailable(PROVIDER, stopped);
      if (!current || current.fingerprint !== auth.fingerprint) return unavailable(PROVIDER, "identity-changed");
      return normalizeAnthropicUsagePayload(payload, Date.now());
    } catch {
      if (stopped) return unavailable(PROVIDER, stopped);
      return unavailable(PROVIDER, phase);
    }
  };
  try {
    return await Promise.race([interruption, work()]);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", abort);
  }
}
