# Model-visible subscription quota in Pi

## The light tool

The managed [quota-status extension](../home/private_dot_pi/private_agent/private_extensions/quota-status/index.ts) adds **`quota_status({})`**. It reuses the user's already-working Pi subscription authentication and the already-installed `@narumitw/pi-usage` **0.64.1** auth/query helpers for native OpenAI, Copilot and Go. Narumitw has no Anthropic adapter, so the tool retains the small Claude collector/normalization logic from the original integration, using native Pi auth and no second package. It does not invoke the addon factory or install a second copy. No runtime installation or application was performed. [^1][^4][^8]

Each call queries **`openai`, `anthropic`, `github-copilot`, and `opencode-go`** independently, with a 15-second deadline per provider including auth and identity revalidation. **`opencode`** is included as explicitly unsupported telemetry: no credential lookup or HTTP request is made for it. There is no cache, disk state, automatic polling, configuration, or quota-reset mutation. The coordinator owns calls before dispatch batches and reuses a result within the batch; workers do not poll independently.

The result is identical in model-facing text, details and structured content:

- `providers`: five observations with fixed public `provider` and allowlisted `source` (null when unavailable or unsupported), `capturedAt` in Unix **milliseconds**, `status` (`fresh`, `unknown`, `unavailable`), fixed `reason`, and `windows`.
- Each window has a safe `label`, `group` (`ChatGPT plan`, `ChatGPT app`, or `null`), `status`, native `unit`/`used`/`remaining`/`limit` when known, consumed `usedPercent`/`usedFraction`, duration `windowMinutes`, and reset `resetsAt` in Unix **seconds**.
- Copilot preserves native credit/request counts, including known used, remaining and limit. Its percentage is derived only from a finite positive known limit; unlimited, missing or zero denominators do not imply free headroom. Credits are not dollars.
- Unknown/invalid values are `null`, not zero. Zero usage is valid; overages remain above 100%. Successful providers are retained when another fails.
- Only known public labels survive; trusted native plan/app scopes use fixed labels and groups. Other labels become **`Quota window`** with no inferred scope; raw model/account IDs, credentials, headers, fingerprints, notes, metrics and error bodies are omitted. A generic window cannot establish a particular model's or the whole account's exhaustion. [^5][^10]

Auth identity is rechecked before publishing. An account/credential change discards the observation. Pi may refresh OAuth while resolving auth; therefore read-only refers to quota operations, not a guarantee that the credential store remains untouched. Cancelling or timing out stops waiting and quota HTTP work; Pi's underlying auth refresh may finish later, but no late quota query or result is published. [^8]

## Enable it (commands not executed)

Preview and apply the native routing, fallback, extension, coordinator and unpinned roles without running setup scripts:

```sh
chezmoi diff --recursive ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/extensions/quota-status ~/.pi/agent/docs ~/.pi/agent/agents
chezmoi apply --recursive --exclude scripts ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/extensions/quota-status ~/.pi/agent/docs ~/.pi/agent/agents
# Restart Pi, then ask the coordinator to call quota_status.
```

The tool explicitly resolves the user's global Pi npm installation using Pi's
agent directory. It loads the shipped **`@narumitw/pi-usage/dist/index.ts`**
helpers, not a sibling extension's undeclared dependency or private UI cache.
The installed addon must be the qualified **0.64.1** release. A missing,
unqualified or unusable helper returns `dependency-unavailable` for OpenAI,
Copilot and Go, not invented quota. Claude remains independent; Zen remains
explicitly unsupported. No `npm install` is needed in the quota-status folder, and no
`settings.json` package entry is needed for the local tool: Pi discovers its
extension folder. [^2][^3][^5][^9]

The user already installed the addon. On another machine, install the qualified
release once before loading this tool (command not executed here):

```sh
pi install npm:@narumitw/pi-usage@0.64.1
```

The same installation supplies the human `/usage` menu/footer. Its UI/cache are
not automatically model-visible, and the tool performs fresh independent
queries without consuming that cache. Pi resolves its SDK at runtime; the
repository has no dependency installation or development-link setup. See
[credential-free tests](../README.md#testing-pi-extensions) for verification.

## Native OpenAI quota authentication and provenance

The user retains Pi's legacy OAuth login **for quota reporting only**. Native
`openai` remains the inference provider. Narumitw **0.64.1** first validates the
native login, then uses the independently validated legacy credential for its
experimental ChatGPT usage endpoints. Both logins must use the same ChatGPT
account/workspace. The native token is never forwarded to those backend routes;
registration matching is not independent proof of shared identity. [Native usage contract](https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage#chatgpt-companion-usage)

The bridge queries the native `openai` adapter and reports numerical windows
only for allowlisted subscription data, with explicit
**`openai-chatgpt-companion-experimental`** provenance. Plan and app scopes remain
separate. App allowance metrics are caps and are omitted, not interpreted as
consumed/remaining quota; absent percentage fields stay unknown. The addon UI
hides app percentages, while its typed helper retains validated backend values;
any app values reported here remain explicitly experimental, not live-qualified. Auth-only reports
have source **`openai-chatgpt-auth`**, no windows, and `unknown`/`no-quota-data`.
Missing, invalid or mismatched credentials never imply zero use or exhaustion.

The native and companion auth fingerprint is revalidated before each request
and before publication, within the full-operation deadline. A generic or app
window does not establish whole-plan exhaustion. No live same-account, quota,
app-cap or reset-window agreement is claimed. Logging out of the retained
credential removes numerical reporting, not native inference.

## Why Claude is absent from `/usage`

Installed Narumitw **0.64.1** has no Anthropic adapter. Its menu and footer
therefore do not display Claude usage, even when Pi's Claude OAuth login works.
The tool's local Claude collector serves **`quota_status`**, not the
third-party menu. It reuses native Pi-resolved OAuth, checks official origins,
revalidates the token identity, and reads the same undocumented usage endpoint.
No extra usage addon, copied credentials, or API-key billing path is added.
After the user applied and reloaded the tool, live calls returned fresh Claude
observations. Dashboard/account agreement remains unverified; later managed
source updates still require applying the extension and reloading it.

## Coverage and limits

The tool reuses three installed Narumitw collectors and retains the local Claude collector. Native OpenAI uses the helper's experimental read-only ChatGPT usage routes; Anthropic uses the **undocumented** `api.anthropic.com/api/oauth/usage`; Copilot uses `api.github.com/copilot_internal/user` with the matching stored original GitHub OAuth credential; OpenCode Go uses its official gateway's `/usage` endpoint. Narumitw verifies matching runtime/stored credentials and official origins for its collectors. The local Claude collector uses only native Pi-resolved auth, validates official origins, and rechecks identity before publication. Zen is not queried. A working inference login does not guarantee that a quota endpoint accepts it; failures remain unavailable rather than prompting automatic credential copying or re-login. [^8]

**This tool has no `opencode` balance collector**, even though Haiku is registered there. The [official Go usage handler](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts) returns subscription windows, not Zen wallet balance; [the requested balance API remains an open issue](https://github.com/anomalyco/opencode/issues/44189). Model availability, Go entitlement and Zen credits are separate. OpenRouter is outside this tool's requested coverage.

Report only the endpoint's actual buckets: the user's Team plan label does not prove workspace-wide scope or entitlement. Percent consumed is not a remaining-message count. Provider data may lag and usage can change after capture; a reset timestamp is not guaranteed renewed capacity. Quota lookup failures do not establish inference failure or allowance exhaustion.

## Verification

```sh
node scripts/test-pi-quota-status.mjs
node scripts/test-pi-quota-status.mjs --runtime \
  /opt/homebrew/Cellar/pi-coding-agent/1.0.4/libexec/lib/node_modules/@earendil-works/pi-coding-agent
```

Replace the example host path with your installed Pi package directory; the test prints its manifest version, which need not match the directory name.

The first command runs credential-free fixture checks. The opt-in runtime check uses a disposable directory to check Pi folder discovery/Jiti imports and schemas, and invokes shipped Narumitw helpers with fake credentials and mocked HTTP. It does not read real auth or contact inference/quota endpoints. Tests cover native companion/auth-only provenance, plan/app scopes, cap omission, request-boundary identity guards, no-lookup behavior for unsupported Zen, missing dependencies, mixed success/failure, unknown/zero/overage values, reset units, hostile labels/errors, identity changes, deadlines and cancellation. Separately,
after user deployment/reload, live calls returned fresh OpenAI, Claude, Copilot
and Go observations with Zen unsupported. These confirm endpoint responses,
not dashboard/account/app agreement, per-model debit or reset replenishment.

## Primary sources

[^1]: Installed `@narumitw/pi-usage@0.64.1` package manifest, [versioned registry metadata](https://registry.npmjs.org/@narumitw%2fpi-usage/0.64.1), and [published artifact](https://registry.npmjs.org/@narumitw/pi-usage/-/pi-usage-0.64.1.tgz). Source repository: [narumiruna/pi-extensions](https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage); `main` is not the versioned authority.
[^2]: Installed Pi SDK **1.1.0**, despite its `1.0.4` Homebrew directory: `docs/extensions.md`, `dist/core/extensions/types.d.ts`, `dist/core/model-registry.d.ts`, `dist/core/auth-storage.d.ts`, and `dist/index.d.ts`. [Upstream extension reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) is a moving reference, not the installed-version authority.
[^3]: Installed Pi `docs/packages.md`: host-provided dependencies and isolated package module roots; `docs/environment-variables.md`: `PI_PACKAGE_DIR` and `PI_CODING_AGENT_DIR` overrides. [Upstream packages reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md).
[^4]: Installed Narumitw **0.64.1** `src/usage.ts`: addon commands, lifecycle and UI/cache; entrypoint declaration in its package manifest.
[^5]: Installed Narumitw **0.64.1** `src/index.ts` and `src/core.ts`: named helper exports, fingerprinting, redaction and deadlines.
[^8]: Installed Narumitw **0.64.1** `src/query.ts`, `src/usage-helpers.ts` and `src/providers/{openai-chatgpt,openai-companion-usage,github-copilot,opencode-zen}.ts`: adapters, official origins, auth matching and collectors.
[^9]: Installed Narumitw **0.64.1** `dist/index.ts`, from the published artifact in [^1], loaded by the actual Pi Jiti test with fake credentials/HTTP.
[^10]: Local Claude normalization derives from the [original 0.53.1 helper source][Original-helper-source]; its retained MIT notice covers reused source. Installed Narumitw **0.64.1** `src/types.ts` and provider normalizers: report/bucket fields and native units.

## Existing options checked — 2026-10-08

**Historical candidate check; current integration uses the user-installed Narumitw 0.64.1 helpers.** Keep the model-facing bridge, not new collectors. Existing extensions do the fetching, but none of the releases checked below supplies the required fresh, account-matched, model-callable quota snapshot across Codex, Anthropic, Copilot and OpenCode Go/Zen. This is a bounded candidate check, not a claim that no such extension exists anywhere. Search results advertising “usage”, “chat report” or “warnings” were checked against actual entrypoints, tool/context registration and published npm artifacts.

| Candidate / published version | Actual model visibility and replacement gap |
| --- | --- |
| Previous helper fork **0.53.1** | At the check date, registry latest was 0.53.1 (published Oct 5): no release delta in that package. Existing source inspection found `/usage`/UI, not a registered quota tool or quota-context injection. The original helper integration used this release; it is now superseded by Narumitw reuse. Its addon alone does not replace the model tool. [^11] |
| `@pi-plugins/usage` **0.7.1** (Sep 14) | `/usage` calls `appendEntry`, with a custom entry renderer and widget. The README explicitly says its transcript report **is not sent to the model**; published bundle exports only the default extension. Supports Claude/Codex/GLM, not Copilot/Go/Zen. Its report includes account email/plan, so forwarding it wholesale would also violate our output boundary. [^12] |
| `@yasuhito/pi-usage` **0.1.1** (Sep 25) | `src/register.ts` gates operation on TUI mode and calls `ui.setStatus`; response/activity hooks update the display, not model context. Codex/Claude/OpenRouter only. Claude acquisition requires Linux/private `XDG_RUNTIME_DIR`, explicitly unavailable on this macOS host. Strong documented origin/schema protections do not fix these functional gaps. [^13] |
| `@specode/pi-subscription-usage` **1.3.1** (Sep 30) | Best existing **structured seam**: `subscription-usage/status/v1` events contain provider, capture time and numeric windows. However `src/usage.ts` emits to Pi's extension event bus; this is neither `registerTool` nor model context. It tracks the selected provider, with automatic refresh/cache; an event listener alone cannot guarantee a fresh all-provider tool call. Codex/OpenAI/Go/Grok/Kimi, not Anthropic/Copilot/Zen. Would still need a bridge, freshness/unknown semantics and broader collectors; full addon also includes confirmed reset-credit redemption, unlike our read-only tool. [^14] |
| `@kaishin/pi-usage` **2.3.0** (Oct 7; newly found) | Six UI/settings/status/warning entrypoints, **no quota tool/context snapshot**. `src/lib/quotas.ts` exports `fetchProviderQuotas({force, signal})` for Codex/Anthropic/Copilot/Go, but not Zen. A migration still needs our registration, safe projection and identity guarantees. Safety changes are material: cache keyed only by provider; auth adapter reads stored Pi auth separately from resolved auth; Codex account-ID fallback reads `.codex/auth.json`, Copilot fallback invokes `gh auth token`, Go searches external OpenCode config/auth. Do not reuse unfiltered results or silently mix these accounts. [^15] |
| `@mtrojnar/pi-usage` **0.2.0** (Sep 7; newly found) | `/usage` and UI, no quota tool. Copilot and generic subscription checks can **POST inference probes** (“Reply with exactly: ok”); Go skips its probe only when dashboard quota succeeds. Zen availability probes are not a balance/quota snapshot. Declared Pi peer range is `>=0.85.0 <1`, excluding native SDK **1.1.0**. Not a safe drop-in under the no-inference/no-spend requirement. [^16] |
| `pi-go-bars` **0.4.0** (newly found) | `setFooter` plus `/gobars`/setup commands, not a quota tool. Go API parsing helpers exist; optional Zen billing uses workspace/browser-cookie scraping, not Pi's inference login. Requires extra sensitive credentials and a model-facing wrapper; no Codex/Anthropic/Copilot coverage. [^17] |

**Integration cost:** replacing the bridge with any checked UI addon saves no model-interface work. Specode's event contract reduces formatting work only for a selected-provider cached observation; Kaishin's wider fetch helpers increase account-safety work. That check supports retaining the safe helper bridge to **Copilot and `opencode-go`**, with separate credential/identity and fixture checks; it does not justify rebuilding their collectors. Keep **`opencode`/Zen explicitly unsupported/unknown**, rather than treating Go entitlement, model availability or a browser billing scrape as equivalent quota.

Most candidates declare wildcard host peers, which permits SDK 1.1.0 installation but does **not** prove runtime compatibility; Kaishin/Yasuhito development manifests still target 0.85.1. No candidate runtime was loaded/tested during that historical research pass. No auth was read, packages installed/applied, external Codex/Claude CLI invoked, or quota/inference/reset requests made. Research downloaded only public registry/source artifacts.

[^11]: Historical [helper source][Original-helper-source] and public registry metadata were checked at the stated date, not repeatedly audited. This is provenance, not an active dependency.

[Original-helper-source]: https://github.com/janvitos/pi-usage/tree/v0.53.1
[^12]: [0.7.1 npm manifest](https://registry.npmjs.org/@pi-plugins%2fusage/0.7.1), [published bundle/README](https://registry.npmjs.org/@pi-plugins/usage/-/usage-0.7.1.tgz) (inspected), [repository entrypoint](https://github.com/k3dom/pi-plugins/blob/4cff3b03a0a97e56f724818aaeceee73bcb07c07/plugins/usage/src/index.ts).
[^13]: [0.1.1 npm manifest](https://registry.npmjs.org/@yasuhito%2fpi-usage/0.1.1), [published source](https://registry.npmjs.org/@yasuhito/pi-usage/-/pi-usage-0.1.1.tgz), [register hooks](https://github.com/yasuhito/pi-usage/blob/04d2c0510fd900f6b31b504d5352360002dd487a/src/register.ts), [platform/security limits](https://github.com/yasuhito/pi-usage/blob/04d2c0510fd900f6b31b504d5352360002dd487a/README.md).
[^14]: [1.3.1 npm manifest](https://registry.npmjs.org/@specode%2fpi-subscription-usage/1.3.1), [status contract](https://github.com/specode/pi-subscription-usage/blob/1015f9f419dfef9ac27c9845ec2318394928fa38/src/status.ts), [event publishing, refresh and command](https://github.com/specode/pi-subscription-usage/blob/1015f9f419dfef9ac27c9845ec2318394928fa38/src/usage.ts), [supported providers/security](https://github.com/specode/pi-subscription-usage/blob/1015f9f419dfef9ac27c9845ec2318394928fa38/README.md).
[^15]: [2.3.0 entrypoints/host peers](https://github.com/kaishin/pi-usage/blob/f9aedd945e281a925fbecc350f1f04952e6633ca/package.json), [helpers/cache](https://github.com/kaishin/pi-usage/blob/f9aedd945e281a925fbecc350f1f04952e6633ca/src/lib/quotas.ts), [auth adapter](https://github.com/kaishin/pi-usage/blob/f9aedd945e281a925fbecc350f1f04952e6633ca/src/lib/auth.ts), [credential fallbacks/fetchers](https://github.com/kaishin/pi-usage/blob/f9aedd945e281a925fbecc350f1f04952e6633ca/src/providers/fetch.ts), [Go config search](https://github.com/kaishin/pi-usage/blob/f9aedd945e281a925fbecc350f1f04952e6633ca/src/providers/opencode-go-config.ts). The core's `sendMessage` is a migration notice, not quota; quota warnings call `ui.notify`.
[^16]: [0.2.0 manifest](https://registry.npmjs.org/@mtrojnar%2fpi-usage/0.2.0), [UI entrypoint](https://github.com/mtrojnar/pi-usage/blob/bab49aed024f76b60877bc08f6854a8ffcb6d4b1/index.ts), [Copilot inference probe](https://github.com/mtrojnar/pi-usage/blob/bab49aed024f76b60877bc08f6854a8ffcb6d4b1/src/copilot.ts), [generic probe](https://github.com/mtrojnar/pi-usage/blob/bab49aed024f76b60877bc08f6854a8ffcb6d4b1/src/subscription-probe.ts), [Go probe fallback](https://github.com/mtrojnar/pi-usage/blob/bab49aed024f76b60877bc08f6854a8ffcb6d4b1/src/opencode-go.ts).
[^17]: [0.4.0 source manifest](https://github.com/donrami/pi-go-bars/blob/e089664e8579b801f0f465c7861c0b1f60fdf8ea/package.json), [footer/commands](https://github.com/donrami/pi-go-bars/blob/e089664e8579b801f0f465c7861c0b1f60fdf8ea/extensions/pi-go-bars/index.ts), [Go/Zen auth and exported utilities](https://github.com/donrami/pi-go-bars/blob/e089664e8579b801f0f465c7861c0b1f60fdf8ea/README.md).
