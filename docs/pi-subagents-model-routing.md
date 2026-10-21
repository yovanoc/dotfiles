# Pi subagents and model routing

This guide describes managed policy for Pi SDK (runtime checked at 1.3.0 on 2026-10-20) and managed `pi-subagents`;
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
`openai/gpt-6-astra`; Sol high and Luna max have identity thinking mappings.
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
Sonnet `medium` for everyday work; Sol for difficult implementation; Opus for deep
review and architecture. User-selected Sol coordinators deliberately use frequent
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

UI/UX starts on Go Kimi K3, with Copilot Luna and native Sol as independent
alternatives (exact efforts in the coordinator). This is a local trial: screenshot
quality is not evidence of accessibility or correct interactions. Verify those
before accepting a result. The SDK advertises K3 reasoning, but adapter effort
mapping must be checked at dispatch; do not claim controlled effort if ignored.

OpenCode Go documents Kimi K3 as zero-retention/no-training.
Gemini 4 Argon Contributor may train Google models and is not zero-retention:
use it only with explicit selection for non-confidential input, never automatic
fallback. Zen is excluded until the user chooses to fund it.
Sources: [Go privacy](https://opencode.ai/docs/en/go/#privacy),
[Kimi K3](https://www.kimi.com/en/blog/kimi-k3),
[Design Arena](https://www.designarena.ai/leaderboard).
Arena rankings conflict and do not establish harness-specific success; compare
accepted UI results, rework and turn limits next period.

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
native startup defaults or reactive fallback routes. Preview and apply these
managed targets when ready:

```bash
chezmoi diff --recursive \
  ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/agents ~/.pi/agent/docs
chezmoi apply --recursive --exclude scripts \
  ~/.pi/agent/settings.json ~/.pi/agent/model-fallback/config.json \
  ~/.pi/agent/agents ~/.pi/agent/docs
```

Restart Pi to refresh role definitions and the policy. If an SDK update left a
missing provider bundle chunk in the running process, use a full exit/start;
`/reload` refreshes extensions but does not fix that stale module reference.
Let running workers finish before restarting. These targets activate the
already-managed native defaults/fallbacks and unpinned policy; role permissions
and concurrency remain unchanged. Neither command is run automatically by
this guide.
