import { getAgentDir, type ExtensionAPI, type ExtensionToolContext, type ToolDefinition } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { Type } from "typebox";
import { observeAnthropicApi } from "./api.ts";
import { observeAnthropic } from "./anthropic.ts";
import { observeCodexbarCredits } from "./credits.ts";
import { readLedger } from "../anthropic-api.ts";
import { observe, PROVIDERS, unavailable, type Helpers } from "./quota.ts";

async function loadHelpers(signal: AbortSignal): Promise<Helpers | undefined> {
  if (signal.aborted) return undefined;
  let abortLoad!: () => void;
  const interrupted = new Promise<never>((_resolve, reject) => {
    abortLoad = () => reject(new Error("Loading interrupted"));
    if (signal.aborted) abortLoad();
    else signal.addEventListener("abort", abortLoad, { once: true });
  });
  const load = (async () => {
    const root = join(getAgentDir(), "npm", "node_modules", "@narumitw", "pi-usage");
    let manifest: unknown;
    try {
      manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
    } catch {
      return undefined;
    }
    if (!manifest || typeof manifest !== "object" || Array.isArray(manifest) || !("name" in manifest) || !("version" in manifest)) return undefined;
    // Exact pin, matching the versioned install in settings.json: bump both together after `node scripts/test-pi-quota-status.mjs --runtime <pi>` passes on the new release.
    if (manifest.name !== "@narumitw/pi-usage" || manifest.version !== "0.66.0") return undefined;
    const addon = await import(pathToFileURL(join(root, "dist", "index.ts")).href);
    // SAFETY: The three helper exports were checked above against the runtime contract.
    return [addon.adapterForProvider, addon.resolveUsageAuth, addon.queryProviderUsage].every((value) => typeof value === "function")
      ? addon as unknown as Helpers
      : undefined;
  })();
  try {
    return await Promise.race([load, interrupted]);
  } finally {
    signal.removeEventListener("abort", abortLoad);
  }
}

const nullableNumber = Type.Union([Type.Number(), Type.Null()]);
const status = Type.Union([Type.Literal("fresh"), Type.Literal("unknown"), Type.Literal("unavailable")]);
const outputSchema = Type.Object({
  codexbarCredits: Type.Optional(Type.Object({
    source: Type.Union([Type.Literal("codexbar-codex-web"), Type.Null()]),
    capturedAt: nullableNumber,
    status: Type.Union([Type.Literal("fresh"), Type.Literal("unavailable")]),
    reason: Type.Union(["ok", "dependency-unavailable", "query-failed", "timeout", "cancelled"].map((reason) => Type.Literal(reason))),
    remainingCredits: nullableNumber,
    balanceIsWorkspace: Type.Union([Type.Boolean(), Type.Null()]),
  }, { additionalProperties: false })),
  providers: Type.Array(Type.Object({
    provider: Type.Union(PROVIDERS.map((provider) => Type.Literal(provider))),
    source: Type.Union([Type.Literal("openai-chatgpt-auth"), Type.Literal("openai-chatgpt-companion-experimental"), Type.Literal("anthropic-oauth-usage"), Type.Literal("codexbar-console-web"), Type.Literal("github-copilot-user"), Type.Literal("opencode-zen-usage"), Type.Null()]),
    capturedAt: nullableNumber,
    status,
    reason: Type.Union(["ok", "unsupported", "no-quota-data", "dependency-unavailable", "auth-unavailable", "auth-failed", "auth-expired", "query-failed", "identity-changed", "timeout", "cancelled"].map((reason) => Type.Literal(reason))),
    console: Type.Optional(Type.Object({
      totalBalanceUsd: Type.Number(),
      grants: Type.Array(Type.Object({ label: Type.Literal("Prepaid grant"), grantUsd: Type.Number(), remainingUsd: Type.Number(), expiresAt: Type.Union([Type.String(), Type.Null()]) }, { additionalProperties: false })),
      monthSpendUsd: Type.Union([Type.Number(), Type.Null()]),
    }, { additionalProperties: false })),
    piLocalRefusal: Type.Optional(Type.Object({ source: Type.Literal("pi-local-exhausted-refusal"), status: Type.Literal("observed") }, { additionalProperties: false })),

    windows: Type.Array(Type.Object({
      label: Type.String(),
      group: Type.Union([Type.Literal("ChatGPT plan"), Type.Literal("ChatGPT app"), Type.Null()]),
      status: Type.Union([Type.Literal("fresh"), Type.Literal("unknown")]),
      unit: Type.Union([Type.Literal("percent"), Type.Literal("count"), Type.Null()]),
      used: nullableNumber,
      remaining: nullableNumber,
      limit: nullableNumber,
      usedPercent: nullableNumber,
      usedFraction: nullableNumber,
      windowMinutes: nullableNumber,
      resetsAt: nullableNumber,
    }, { additionalProperties: false })),
  }, { additionalProperties: false }), { minItems: 6, maxItems: 6 }),
}, { additionalProperties: false });

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "quota_status",
    label: "Subscription quota",
    description: "Fetch Anthropic subscription quota and live Anthropic Console prepaid-credit telemetry through the installed CodexBar CLI (anthropic-api source is codexbar-console-web). Console output exposes its numeric total balance, fixed-label grant rows, and This month (UTC) spend; grants are not summed into the total. A Pi-local exhausted-credit refusal, when present, is separate evidence and never a balance. Also return separate codexbarCredits from the signed-in CodexBar web session: remainingCredits are credit counts, not USD or percentages; account agreement with Pi is unverified and this is not spending authorization. Also fetch native OpenAI ChatGPT companion (experimental telemetry only; inference remains native openai), GitHub Copilot and OpenCode Go quota. OpenCode Zen (opencode) is unsupported and is not a prepaid wallet balance (15s full-operation deadline). No arguments or cache. usedPercent/usedFraction are consumed quota; count windows expose native counts. Count fractions require a known positive limit; fresh counts may have unknown fractions; capturedAt is Unix milliseconds, resetsAt is Unix seconds, windowMinutes is minutes. Null/unknown/unavailable never means zero use or full capacity. Quota may change after observation; no model-to-pool mapping is implied.",
    parameters: Type.Object({}, { additionalProperties: false }),
    outputSchema,
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
    async execute(_id: string, _params: Record<string, never>, signal: AbortSignal | undefined, _onUpdate: Parameters<ToolDefinition["execute"]>[3], ctx: ExtensionToolContext) {
      const signals = [signal, ctx.signal].filter((value): value is AbortSignal => value !== undefined);
      const cancellation = signals.length ? AbortSignal.any(signals) : undefined;
      const deadline = Date.now() + 15000;
      const expired = AbortSignal.timeout(15000);
      const loadingSignal = AbortSignal.any([expired, ...signals]);
      const anthropic = observeAnthropic(ctx, cancellation, Math.max(1, deadline - Date.now()));
      const credits = observeCodexbarCredits(cancellation, Math.max(1, deadline - Date.now()));
      let helpers: Helpers | undefined;
      if (!cancellation?.aborted) {
        try {
          helpers = await loadHelpers(loadingSignal);
        } catch {
          // Other providers remain unavailable when the optional shared helper is missing.
        }
      }
      const missingReason = cancellation?.aborted ? "cancelled" : expired.aborted ? "timeout" : "dependency-unavailable";
      const providers = await Promise.all(PROVIDERS.map((provider) => {
        if (provider === "anthropic") return anthropic;
        if (provider === "anthropic-api") return observeAnthropicApi(readLedger, cancellation, Math.max(1, deadline - Date.now()));
        if (provider === "opencode") return Promise.resolve(unavailable(provider, "unsupported"));
        return helpers
          ? observe(provider, helpers, ctx, cancellation, Math.max(1, deadline - Date.now()), deadline)
          : Promise.resolve(unavailable(provider, missingReason));
      }));
      const snapshot = { providers, codexbarCredits: await credits };
      return { content: [{ type: "text", text: JSON.stringify(snapshot) }], details: snapshot, structuredContent: snapshot };
    },
  });
}
