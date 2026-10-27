# Pi subagents and model routing

This guide describes managed policy for Pi SDK (preflight checked at 1.4.0 on 2026-10-27) and managed `pi-subagents`;
it does not claim runtime configuration was applied. The operational
model/effort routes, quota contract, and retry policy live only in the [root
coordinator](../home/private_dot_pi/private_agent/private_docs/coordinator.md).
Benchmark evidence and transfer caveats are in the [routing research](model-routing-research.md).
The [fallback guide](model-fallback.md) describes reactive switching; the
[managed fallback JSON](../home/private_dot_pi/private_agent/private_model-fallback/config.json)
remains its authority.

## Model selection

The seven roles in **managed source** no longer pin `model` or `thinking`.
Unapplied runtime copies may still pin both; source edits alone do not unlock
coordinator choices. On a fresh
coordinator-created `Agent` call, explicit user/task model and effort choices
come first; otherwise use the coordinator's route and pass both fields. A
resume omits both to retain the worker's established runtime. The root startup
default is `openai/gpt-6.1-sol` medium, while Pi's active runtime
model controls the root session. The catalog statically
registers native `openai/gpt-6.1-sol`, `openai/gpt-6-luna`, and
`openai/gpt-6-astra`; managed `models.json` supplements this with
`openai/gpt-6.1-terra` over Responses without changing native authentication.
Sol high and Luna max have identity thinking mappings.
Catalog registration and mappings do not prove account entitlement, live
runtime behavior, effort equivalence, or quota debit. Managed inference uses
only the native route; OpenAI quota reporting uses the retained login as
documented in [quota access](pi-quota-usage.md).

A direct `@agent` mention bypasses coordinator routing. With roles unpinned it
inherits the parent model; if thinking is omitted, the selected model's default
may apply rather than the parent's live thinking level. An explicit model or
thinking pin in role frontmatter would take precedence over Agent call
parameters, including project-level definitions that shadow the managed roles.
Report conflicting project pins rather than claiming the requested route ran.
Keep the managed routing fields unpinned. `strictAgentFiles: true`
is a parsing guard, not a model-selection mechanism.

Workflows remain caller-first: use `SubagentWorkflow` only when explicitly
requested, and honor any user-selected model/effort before a default route.
Ordinary delegation uses native `Agent` calls. The coordinator owns ordered
task priorities, soft quota states, scope checks and reset handling; this is
prompt policy, not an automatic routing engine. Do not duplicate that table here.
In short: Haiku/Luna first for bounded mapping, extraction and checkable leaves;
Copilot Luna is preferred over native Luna for equal-fit bounded work with headroom;
Sonnet `medium` for everyday work outside Terra’s task-fit cases below; Sol for
difficult implementation; Opus for deep review and architecture. User-selected Sol coordinators deliberately use frequent
OpenAI resets; they are not policy failures. Quota pacing is reset-aware, while
`anthropic-api/` is budget-checked relief only (no daily credit-burning formula). Handoff checkpoints are per-session
files whose exact path the notice names; legacy `tasks/handoff.md` is not authority.

## Haiku availability

The refreshed catalog now includes `anthropic/claude-haiku-5-5`,
`opencode/claude-haiku-5-5`, and `opencode-go/claude-haiku-5-5` with 1M context
and 128k output. Installed adapters advertise low/medium and adaptive thinking.
No custom registration is needed. These are separate provider routes, not
interchangeable billing pools; the coordinator owns their task selection.

## Visual work and privacy

The Go Kimi K3 `high` trial is on hold: the inspected Pi 1.4.0 catalog maps
`high` to unsupported and only advertises `max`. Do not silently select max.
Use the eligible alternatives in the coordinator until the requested effort is
qualified. Screenshot quality is not evidence of accessibility or correct
interactions; verify those before accepting a result. Registration alone does
not establish live behavior.

OpenCode Go documents Kimi K3 as zero-retention/no-training.
Gemini 4 Argon Contributor may train Google models and is not zero-retention:
use it only with explicit selection for non-confidential input, never automatic
fallback. Zen is excluded until the user chooses to fund it.
Sources: [Go privacy](https://opencode.ai/docs/en/go/#privacy),
[Kimi K3](https://www.kimi.com/en/blog/kimi-k3),
[Design Arena](https://www.designarena.ai/leaderboard).
Arena rankings conflict and do not establish harness-specific success; compare
accepted UI results, rework and turn limits next period.

## Terra selective routing

The user authorized task-fit `openai/gpt-6.1-terra` use through the existing native
ChatGPT login. This is selective worker routing, not a startup or automatic
fallback change. The coordinator is the single authority for ordered routes:
Terra starts at `medium` for concise supplied-material writing, scoped code fixes
with regression checks and defined visual/computer tasks with verifiable saved
outcomes. Cheap extraction/mechanical routes and hard/security/cross-layer routes
stay separate. Role tool permissions still apply; model computer-use capability
does not install a browser or desktop tool.

The bundled Pi 1.4.0 catalog inspected on 2026-10-27 lacks `gpt-6.1-terra`.
Managed `models.json` therefore adds it under native `openai`, rather than using
`modelOverrides` (which ignores absent IDs). It specifies `openai-responses`,
text/image input, a 1,050,000-token context and 128,000-token maximum output.
The published maximum **input** is 922,000 tokens; the installed Pi model schema
cannot encode that separate ceiling. Keep task inputs below it; the context
window is not permission to send 1,050,000 input tokens. Pi effort `off` maps to
`none`, `minimal` is unsupported, and `low`/`medium`/`high`/`xhigh`/`max` map
identically. No speculative compatibility flags or hard image-count limits are
added. `enabledModels` includes Terra for selection/cycling; Sol medium remains
startup. A future native catalog entry with the same ID is replaced by this
managed definition, so recheck it on SDK/catalog upgrades.

Standard API input/cached-input/cache-write/output rates per million tokens are
$1/$0.05/$1.25/$5. The cache-write estimate is for 30-minute retention, not the
higher 12-hour rate. Above 272k input tokens, full-request input/cache rates double
and output rates increase 1.5×. Those rates are encoded as a request-wide tier.
These are API-equivalent estimates, **not ChatGPT credit-debit rates** or measured
savings. Compare accepted outputs, rework, review/repair time and actual account
usage rather than promising savings from API price ratios.

### Native availability and acceptance

Offline checks (no inference, credential reads or live target writes):

```bash
python3 scripts/test-pi-routing.py
./scripts/test-agent-prompt-guard.sh
```

The guard check loads the managed registration through the installed SDK schema
and native provider composer, preserves the OAuth method, and checks Terra’s
supported efforts without resolving credentials. This proves local registration,
not account entitlement. After applying source, restart Pi, open `/model` and
confirm `openai/gpt-6.1-terra` and `medium` are selectable through the existing
OpenAI ChatGPT login. No API key, alternate provider or new funding is required
or authorized. Do not print credentials. A missing model or actual auth/usage
refusal is an affected-route blocker to reconcile, not permission to try an API key.

Before relying on Terra, the coordinator should perform one bounded native check
with a harmless read-only fixture tool and supplied-material answer at `medium`,
recording the actual provider/model/effort, successful terminal completion, tool
result and checked answer. Registration and an available picker alone do not
prove that inference works. A bounded coordinator check on 2026-10-27 passed through the existing native
login at `medium`: Terra called the fixture read tool and returned a factual
supplied-material answer with terminal `stop`. Evidence for this local check is
`/tmp/pi-terra-routing-check/smoke-result.log` (temporary, not a durable benchmark).
This establishes current inference and basic tool behavior, not representative
code/UI quality or measured ChatGPT credit savings.

For real work, define acceptance first: writing needs factual/qualification,
audience, voice and length checks; code needs regression tests; computer tasks
need the saved record/page reopened and the report checked against it. Interactive
UI changes additionally need rendered desktop/mobile, keyboard and accessibility
checks. On verified misses, escalate to Sol on the same inputs and `medium` effort,
including repair time in the evidence. Do not duplicate runs solely to claim a
cost comparison. Retain stronger routes for hard work.

Sources: [model selection](https://developers.openai.com/api/docs/guides/model-selection),
[Terra model](https://developers.openai.com/api/docs/models/gpt-6.1-terra),
[pricing](https://developers.openai.com/api/docs/pricing),
[native model discovery](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

## Installed behavior worth preserving

- Role frontmatter continues to own tools, permissions, prompt mode, and other
  role constraints; model choice does not grant tools or change permissions.
  Built-in tool allowlists and extension-tool access are separate controls.
- The roles use `prompt_mode: replace`, so parent system/project instructions
  are not implicitly copied into the child prompt. Read applicable project
  instructions from disk when the assigned work depends on them; `inherit_context`
  is a separate call option.
- Native background dispatch, turn limits, concurrency, retries, and task
  accounting remain governed by the coordinator and installed extension
  behavior, not model pins in role files.

## Quota and failover boundary

The managed `quota_status` tool's provider coverage, source identity and
limitations are documented in [quota access](pi-quota-usage.md); root calls it
before dispatch batches when available. Treat missing, unavailable, unknown or
old observations as unknown, or use an explicit fresh user snapshot. UI `/usage`
output and footers alone are not model-visible evidence. A native OpenAI app
cap and a whole-plan limit are distinct; `subscription_sharing_usage_limit_exceeded`
may indicate either and does not prove whole-plan exhaustion. Native usage-limit
errors can arrive during streaming without a matching HTTP status, so configured
status-based fallback is not guaranteed to catch them. The fallback extension
reports configuration/cooldowns, not quota or reset allowance, and a generic
429 is not proof that the subscription pool is exhausted. The tool has returned
fresh live observations; dashboard/account/app agreement, per-model debit,
streamed failover and effort equivalence remain unverified.
The coordinator owns any dispatch stop/retry decision. See the [fallback
guide](model-fallback.md) for matching, cooldown, and configuration details.

## Activating source policy

Applying only the quota extension does not update role pins, the coordinator,
native model registration/startup defaults or reactive fallback routes. Preview
and apply these managed targets when ready:

```bash
chezmoi diff --recursive \
  ~/.pi/agent/models.json ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/agents ~/.pi/agent/docs \
  ~/.pi/agent/extensions/agent-prompt-guard.ts \
  ~/.pi/agent/extensions/task-outcome-receipt.ts
chezmoi apply --recursive --exclude scripts \
  ~/.pi/agent/models.json ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/agents ~/.pi/agent/docs \
  ~/.pi/agent/extensions/agent-prompt-guard.ts \
  ~/.pi/agent/extensions/task-outcome-receipt.ts
```

Restart Pi to refresh role definitions and the policy. If an SDK update left a
missing provider bundle chunk in the running process, use a full exit/start;
`/reload` refreshes extensions but does not fix that stale module reference.
Let running workers finish before restarting. These targets activate the
already-managed native defaults/fallbacks, unpinned policy and preflight/receipt
extensions; role permissions and concurrency remain unchanged. Neither command is run automatically by
this guide.
