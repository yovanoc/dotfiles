import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { ResolvedUsageAuth, UsageBucket, UsageProviderAdapter, UsageReport, UsageRequestGuard } from "@narumitw/pi-usage/src/types.ts";

export const PROVIDERS = ["openai", "anthropic", "github-copilot", "opencode-go", "opencode"] as const;
type Provider = (typeof PROVIDERS)[number];
export type Helpers = {
  adapterForProvider(id: string): UsageProviderAdapter | undefined;
  resolveUsageAuth(ctx: ExtensionContext, adapter: UsageProviderAdapter): Promise<ResolvedUsageAuth | undefined>;
  queryProviderUsage(adapter: UsageProviderAdapter, auth: ResolvedUsageAuth, signal: AbortSignal, timeoutMs: number, guard?: UsageRequestGuard): Promise<UsageReport>;
};
export type Reason = "ok" | "unsupported" | "no-quota-data" | "dependency-unavailable" | "auth-unavailable" | "auth-failed" | "query-failed" | "identity-changed" | "timeout" | "cancelled";
export type Window = {
  label: string;
  group: "ChatGPT plan" | "ChatGPT app" | null;
  status: "fresh" | "unknown";
  unit: "percent" | "count" | null;
  used: number | null;
  remaining: number | null;
  limit: number | null;
  usedPercent: number | null;
  usedFraction: number | null;
  windowMinutes: number | null;
  resetsAt: number | null;
};
export type Observation = {
  provider: Provider;
  source: "openai-chatgpt-auth" | "openai-chatgpt-companion-experimental" | "anthropic-oauth-usage" | "github-copilot-user" | "opencode-zen-usage" | null;
  capturedAt: number | null;
  status: "fresh" | "unknown" | "unavailable";
  reason: Reason;
  windows: Window[];
};

const SOURCES = { openai: null, anthropic: "anthropic-oauth-usage", "github-copilot": "github-copilot-user", "opencode-go": "opencode-zen-usage", opencode: null } as const;

export function unavailable(provider: Provider, reason: Reason): Observation {
  if (provider === "opencode") reason = "unsupported";
  return { provider, source: SOURCES[provider], capturedAt: null, status: reason === "no-quota-data" || reason === "unsupported" ? "unknown" : "unavailable", reason, windows: [] };
}

const LABELS = {
  anthropic: new Set(["Five-hour", "Weekly", "Weekly Sonnet", "Weekly Opus", "Weekly OAuth apps"]),
  "github-copilot": new Set(["AI credits", "Premium requests", "Chat requests"]),
  "opencode-go": new Set(["Rolling window", "Weekly window", "Monthly window"]),
};
const nonnegative = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value) && value >= 0;
const validTimestamp = (value: unknown): value is number => nonnegative(value) && value <= 8640000000000000;

export function sanitize(provider: Provider, report: UsageReport): Observation {
  if (provider === "openai") return sanitizeOpenAI(report);
  if (provider === "opencode") return unavailable(provider, "unsupported");
  return sanitizeBuckets(provider, report.capturedAt, report.buckets);
}

function sanitizeOpenAI(report: UsageReport): Observation {
  const capturedAt = validTimestamp(report.capturedAt) ? report.capturedAt : null;
  if (report.providerId !== "openai") return unavailable("openai", "no-quota-data");
  if (report.source === "openai-chatgpt-auth" && report.buckets.length === 0) {
    return { ...unavailable("openai", "no-quota-data"), source: "openai-chatgpt-auth", capturedAt };
  }
  if (report.source !== "openai-chatgpt-companion" || report.semantics?.kind !== "consumer-subscription") {
    return unavailable("openai", "no-quota-data");
  }
  const windows: Window[] = (Array.isArray(report.buckets) ? report.buckets : []).flatMap((bucket: UsageBucket) => {
    const group = bucket?.groupId === "chatgpt-plan" && bucket.groupLabel === "Plan limits"
      ? "ChatGPT plan"
      : bucket?.groupId === "chatgpt-app" && bucket.groupLabel === "App limits" ? "ChatGPT app" : null;
    if (!group || bucket.label !== "Subscription limit" || bucket.unit !== "percent") return [];
    const used = nonnegative(bucket.used) && bucket.used <= 100 ? bucket.used : null;
    const fraction = used === null ? null : used / 100;
    return [{
      label: group,
      group,
      status: used === null ? "unknown" : "fresh",
      unit: "percent",
      used,
      remaining: null,
      limit: null,
      usedPercent: used,
      usedFraction: fraction,
      windowMinutes: nonnegative(bucket.windowMinutes) && bucket.windowMinutes > 0 ? bucket.windowMinutes : null,
      resetsAt: nonnegative(bucket.resetsAt) && bucket.resetsAt <= 253402300799 ? bucket.resetsAt : null,
    }];
  });
  const fresh = capturedAt !== null && windows.some((window) => window.status === "fresh");
  return {
    ...unavailable("openai", fresh ? "ok" : "no-quota-data"),
    source: "openai-chatgpt-companion-experimental",
    capturedAt,
    status: fresh ? "fresh" : "unknown",
    windows,
  };
}

export function sanitizeBuckets(provider: Provider, capturedAtValue: unknown, buckets: readonly UsageBucket[]): Observation {
  if (provider === "openai" || provider === "opencode") return unavailable(provider, "unsupported");
  const windows: Window[] = (Array.isArray(buckets) ? buckets : []).map((bucket: UsageBucket) => {
    const unit = bucket?.unit === "percent"
      ? "percent"
      : provider === "github-copilot" && bucket?.unit === "count" ? "count" : null;
    const used = unit !== null && nonnegative(bucket?.used) ? bucket.used : null;
    const remaining = unit === "count" && nonnegative(bucket?.remaining) ? bucket.remaining : null;
    const limit = unit === "count" && nonnegative(bucket?.limit) ? bucket.limit : null;
    const fraction = unit === "percent" && used !== null ? used / 100 : used !== null && limit !== null && limit > 0 ? used / limit : null;
    const usedFraction = fraction !== null && Number.isFinite(fraction) ? fraction : null;
    const percent = unit === "percent" ? used : usedFraction === null ? null : usedFraction * 100;
    const label = LABELS[provider].has(bucket?.label) ? bucket.label : "Quota window";
    return {
      label,
      group: null,
      status: used === null && remaining === null ? "unknown" : "fresh",
      unit,
      used,
      remaining,
      limit,
      usedPercent: percent !== null && Number.isFinite(percent) ? percent : null,
      usedFraction,
      windowMinutes: nonnegative(bucket?.windowMinutes) && bucket.windowMinutes > 0 ? bucket.windowMinutes : null,
      // Helper resetsAt is Unix seconds, not capturedAt's milliseconds. Reject out-of-range dates.
      resetsAt: nonnegative(bucket?.resetsAt) && bucket.resetsAt <= 253402300799 ? bucket.resetsAt : null,
    };
  });
  const capturedAt = validTimestamp(capturedAtValue) ? capturedAtValue : null;
  const fresh = capturedAt !== null && windows.some((window) => window.status === "fresh");
  return { ...unavailable(provider, fresh ? "ok" : "no-quota-data"), capturedAt, status: fresh ? "fresh" : "unknown", windows };
}

export async function observe(provider: Provider, helpers: Helpers, ctx: ExtensionContext, signal?: AbortSignal, timeoutMs = 15000, deadlineAt = Date.now() + timeoutMs): Promise<Observation> {
  if (provider === "opencode") return unavailable(provider, "unsupported");
  const controller = new AbortController();
  let phase: Reason = "auth-failed";
  let stopped: "timeout" | "cancelled" | undefined;
  let identityChanged = false;
  let stop!: (result: Observation) => void;
  const interruption = new Promise<Observation>((resolve) => { stop = resolve; });
  const interrupt = (reason: "timeout" | "cancelled") => {
    if (stopped) return;
    stopped = reason;
    controller.abort();
    stop(unavailable(provider, reason));
  };
  const abort = () => interrupt("cancelled");
  if (signal?.aborted) abort();
  else signal?.addEventListener("abort", abort, { once: true });
  const startedAt = Date.now();
  const expiresAt = Math.min(startedAt + timeoutMs, deadlineAt);
  const timer = setTimeout(() => interrupt("timeout"), Math.max(0, expiresAt - Date.now()));
  const ensureActive = () => {
    if (stopped) throw new Error("Quota observation interrupted.");
    if (signal?.aborted) {
      interrupt("cancelled");
      throw new Error("Quota observation interrupted.");
    }
    if (Date.now() >= expiresAt) {
      interrupt("timeout");
      throw new Error("Quota observation interrupted.");
    }
  };
  const work = async (): Promise<Observation> => {
    try {
      ensureActive();
      const adapter = helpers.adapterForProvider(provider);
      if (!adapter) return unavailable(provider, "dependency-unavailable");
      const auth = await helpers.resolveUsageAuth(ctx, adapter);
      ensureActive();
      if (!auth) return unavailable(provider, "auth-unavailable");
      phase = "query-failed";
      const guard: UsageRequestGuard = async () => {
        ensureActive();
        const current = await helpers.resolveUsageAuth(ctx, adapter);
        ensureActive();
        if (!auth.fingerprint || !current || current.fingerprint !== auth.fingerprint) {
          identityChanged = true;
          controller.abort();
          throw new Error("Quota observation identity changed.");
        }
      };
      const remaining = expiresAt - Date.now();
      if (remaining <= 0) {
        interrupt("timeout");
        return unavailable(provider, "timeout");
      }
      const report = await helpers.queryProviderUsage(adapter, auth, controller.signal, remaining, provider === "openai" ? guard : undefined);
      ensureActive();
      phase = "auth-failed";
      if (provider === "openai") await guard();
      else {
        const current = await helpers.resolveUsageAuth(ctx, adapter);
        ensureActive();
        if (!current || !auth.fingerprint || current.fingerprint !== auth.fingerprint) return unavailable(provider, "identity-changed");
      }
      ensureActive();
      return sanitize(provider, report);
    } catch (error) {
      if (stopped) return unavailable(provider, stopped);
      if (identityChanged) return unavailable(provider, "identity-changed");
      const noQuota = phase === "query-failed" && error instanceof Error && [
        "Claude usage endpoint returned no displayable usage data.",
        "OpenCode Zen usage endpoint returned no displayable usage data.",
        "GitHub Copilot usage response contained no supported quota.",
      ].includes(error.message);
      return unavailable(provider, noQuota ? "no-quota-data" : phase);
    }
  };
  try {
    return await Promise.race([interruption, work()]);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", abort);
  }
}
