# Pi subagents and model routing

This note describes managed source policy and installed-source behavior for
**Pi 0.87.1** and **`@tintinweb/pi-subagents` 0.19.0**. Managed values here
are not evidence that a live session loaded them. No live or multi-hour
unattended-campaign validation is claimed; re-check installed sources after
upgrades.

## Selected defaults

| Concern | Choice | Reason |
| --- | --- | --- |
| Main-session startup default | `openai-codex/gpt-6-luna`, max | Applies to new sessions only; Pi's runtime model/thinking selection governs the active session, independent of its coordination role. |
| Routing gate | Native leaf `Agent` dispatch by default; `SubagentWorkflow` only on explicit user request | Keep routine delegation direct while preserving user-opted workflow orchestration. |
| Implementer | `openai-codex/gpt-6-luna`, max | Bounded implementation lane. |
| Explore | `openai-codex/gpt-6-luna`, max | Bounded repository mapping lane. |
| Effect specialist | `openai-codex/gpt-6-luna`, max | `effect-senior` handles well-scoped Effect work. |
| Reviewer | `openai-codex/gpt-6-astra`, low | Independent read-only review lane. |
| UI/UX | `openai-codex/gpt-6-luna`, max | Current managed role pin for visual and interaction work. |
| Background concurrency | 50 total active lanes per campaign, shared across root-direct and nested work | Managed global `maxConcurrent` is 50; root-direct lanes use at most `min(50, effective maxConcurrent)`. Project settings override global settings; pending campaign backlog is not capped at 50. |
| Foreground concurrency | omitted (`0`, unlimited) | Keep the extension default; ordinary root delegation is explicitly background, while explicit workflows/tasks retain foreground support. |
| Turn limits | no default cap (`defaultMaxTurns` omitted); named roles omit `max_turns` | Avoids a global interruption ceiling; add a limit only when requested. |
| Nesting | depth 2 | Ordinary specialist roles do not grant child-agent tools by default. |
| Join and dispatch | `defaultJoinMode: async`; `backgroundByDefault: true` | The model-neutral main session returns after ordinary direct-background dispatch; specialists do the work. |
| Workflows | enabled; execution requires explicit user opt-in | `workflowsEnabled: true` registers `SubagentWorkflow`; direct `Agent` dispatch remains the default. |
| Scheduling | enabled; session-scoped | `schedulingEnabled: true` preserves the feature; explicit authorization is required by policy, and unattended campaign reliability is unvalidated. |
| Task retries | At most one retry for a recoverable failure on a safe/idempotent task; persist attempt counts in task metadata | Stop launching work on a provider after a hard auth, quota, or configuration failure and report the blocker; avoid retry storms. |
| Result retrieval | Use native `pi-subagents` 0.19.0 behavior; upgrade only after the upstream fix is merged and released | An unread completed result may become unavailable after 10 minutes. PR [#348](https://github.com/tintinweb/pi-subagents/pull/348) was open and unmerged when last checked. |
| Dispatch | strict fallback (`none`) | A misspelled or disabled type fails instead of silently running `general-purpose`. |
| Agent mentions | `direct` | Avoids an extra root-model turn when starting a mentioned agent. |
| Tool description | compact | Reduces always-loaded tool-schema context. |

The startup default is managed in `settings.json`; named-role pins come from
agent frontmatter. The default applies only to new sessions; `/model` choices
control active and resumed sessions. Provider-prefixed strings are Pi registry
IDs/aliases; re-check availability with `pi --list-models` after upgrades.

## Provider fallback policy

`home/private_dot_pi/private_agent/private_model-fallback/config.json` keeps the
subscription-backed providers first, with one matching fallback switch:

| Source | Fallback | Purpose |
| --- | --- | --- |
| `opencode/gemini-3.8-flash` | `openai-codex/gpt-5.6-luna` | Keep the existing Gemini path on Codex first. |
| `openai-codex/*`, `anthropic/*` | `github-copilot/gpt-5.6-luna` | Use Copilot before the final Go destination. |
| `github-copilot/*` | `opencode-go/gpt-5.6-luna` | Last configured destination; no new paid OpenCode target. |

Rules cover `429`, `500`, `502`, `503`, and `504`, use a ten-minute cooldown,
and let provider `Retry-After`/`x-ratelimit-reset*` headers override that
window. `autoRetry` is disabled: a failed user prompt is not replayed, avoiding
duplicate side effects.

The extension performs a single fallback switch, not an automatic multi-hop
chain. A later manual continuation can match the next provider's rule, but it
is not an automatic retry or a guarantee that rate limits will be recovered.

## Coordination and write ownership

The active main session follows Pi's selected model and coordinates directly,
dispatching specialists without model-based routing. It owns coordination and
evidence; route edits to `implementer` or the relevant writer specialist.
Preserve existing PR heads and protections; do not auto-merge without explicit
authorization.

## `subagents.json` settings

Global settings live at `$PI_CODING_AGENT_DIR/subagents.json` (normally
`~/.pi/agent/subagents.json`); project settings live at
`<cwd>/.pi/subagents.json`. Project keys shallowly override global keys.
Invalid or out-of-range fields are dropped individually.

| Field | Installed default and accepted values |
| --- | --- |
| `maxConcurrent` | Installed default `10`; integer `1..1024`. Top-level background pool. Managed global source sets `50`; a project value overrides it. |
| `maxConcurrentForeground` | `0` (unlimited); integer `0..1024`. Blocking foreground spawn pool. |
| `defaultMaxTurns` | omitted/`0` (unlimited); integer `0..10000`. |
| `graceTurns` | `5`; integer `1..1000`. |
| `defaultJoinMode` | Installed default `smart`; `smart`, `async`, or `group`. Background only. Managed global source sets `async`. |
| `backgroundByDefault` | `true`; explicit call/frontmatter wins. |
| `schedulingEnabled` | `true`; false removes scheduling from the next session's Agent schema. Managed global source keeps it enabled. |
| `scopeModels` | `false`; when enabled, checks Pi `enabledModels` exact entries. |
| `strictAgentFiles` | `false`; true fails startup on malformed agent files. |
| `disableDefaultAgents` | `false`; controls built-in `general-purpose`, `Explore`, and `Plan`. |
| `toolDescriptionMode` | `full`; `full`, `compact`, or `custom`. |
| `fleetView` | `true`. |
| `agentMentions` | `model`; `model`, `direct`, or `off` (legacy booleans accepted). |
| `rememberAgents` | `true`; default for persisted top-level Pi sessions. |
| `widgetMode` | `background`; `all`, `background`, or `off`. |
| `outputTranscript` | `true`; separate from session persistence and worktrees. |
| `worktreeIsolation` | `true`; false removes the schema field next session and refuses worktrees. |
| `workflowsEnabled` | Unset means auto-on unless another workflow tool exists; explicit boolean pins it. Managed global source sets `true`. |
| `maxSubagentDepth` | `2`; integer `0..16`; `0` or `1` disables nesting. Managed global source sets `2`. |
| `fallbackSubagent` | `general-purpose`; agent name, `none`, or boolean `false` for strict failure. |
| `reportUsage` | `false`; adds child usage to the parent session's totals. |
| `showCost` | `false`; shows Pi's catalog-based estimate. |
| `showModel` | `false`; shows effective model/thinking in the widget. |
| `viewerMarkdown` | `assistant`; `off`, `assistant`, or `all`. |

Authoritative implementation: `src/settings.ts`; user-facing behavior:
`README.md#persistent-settings` in the installed pi-subagents package.

## Agent frontmatter

Agent files are loaded in this precedence order: project `.pi/agents`, project
`.agents/agents`, then global `$PI_CODING_AGENT_DIR/agents`. The project `.pi`
copy wins name collisions.

| Field | Semantics |
| --- | --- |
| `name`, `display_name`, `description`, `color`, `enabled` | Type identity, cosmetic label/description/color, and registration toggle. Filename supplies `name`; `:` is reserved. |
| `tools` | Built-in allowlist plus optional `ext:<extension>[/tool]` selectors. Omitted means all built-ins. `none` means no built-ins, not necessarily no extension tools. |
| `extensions`, `exclude_extensions` | Load all/none/list and then deny named extensions. Loading and tool visibility are separate controls. |
| `disallowed_tools` | Final tool denylist. |
| `skills` | `true` exposes inherited skill catalog, `false` none, list preloads only named skill bodies. |
| `memory` | `project`, `local`, or `user`; read-only when effective tools lack edit/write. |
| `model`, `thinking` | Model pin and Pi thinking level. Frontmatter is authoritative over Agent call parameters. |
| `max_turns` | Non-negative number; omitted/`0` is unlimited. |
| `prompt_mode` | `replace` (default) or `append`; details below. |
| `inherit_context` | Prepends a rendered parent conversation to the child user prompt; independent of prompt mode. |
| `run_in_background` | Pins foreground/background instead of using the project default. |
| `allowed_subagents` | Omitted/none/false disables nesting; `all`/`*`/true or a CSV allowlist enables runtime-scoped child tools. |
| `isolated` | Hermetic specialist mode: no extensions or skills; built-in tools only. |
| `isolation` | `worktree` or `off`; filesystem isolation is a directive/copy, not a sandbox. |
| `persist_session`, `output_transcript`, `session_dir` | Independent controls for Pi session persistence, temporary JSONL transcript, and persisted-session location. |

The Agent tool itself accepts `prompt`, `description`, `name`, `subagent_type`,
`model`, `thinking`, `max_turns` (minimum 1; omit for unlimited),
`run_in_background`, `resume`, `isolated`, `inherit_context`, and conditionally
`isolation`/`schedule`. Frontmatter pins strategy fields; call parameters only
fill omissions.

Authoritative parser/schema: `src/custom-agents.ts`,
`src/invocation-config.ts`, and the Agent `Type.Object` in `src/index.ts`.

## Execution consequences

### Prompt and context

- `replace` builds a small subagent/environment header plus the file body. Pi's
  context loader is explicitly disabled, so `AGENTS.md`, `CLAUDE.md`, and
  append-system files are **not inherited**. Put essential policy in the role
  or in every task packet, and tell the child to read applicable project
  instructions from disk when the task depends on them.
- `append` starts with the parent's effective system prompt byte-for-byte, then
  adds the child bridge/header and role body. This carries parent project
  instructions and improves prompt-prefix cache reuse.
- Skills are separate: `skills: true` still lets Pi advertise discovered skill
  descriptions in either prompt mode; a list injects only those full skill
  bodies. `inherit_context` is also separate and adds conversation history to
  the user prompt.

Source: `src/prompts.ts` and `src/agent-runner.ts` (`DefaultResourceLoader` with
`noContextFiles: true`).

### Tool permissions

- Built-in allowlists, `disallowed_tools`, extension selection, and active
  extension-tool scoping are enforced in the child tool registry and again
  before tool calls. They are not only prompt wording.
- `tools:` limits built-ins; loaded extension tools remain available unless
  narrowed with `ext:` selectors or denied by name. Explore keeps extensions
  available for CodeGraph, LSP, MCP, and web search, so its read-only rule is
  behavioral for extension tools. A role with `bash` is likewise not enforced
  read-only because shell commands can mutate anything the OS account can.
- `extensions: false` prevents extension binding. `exclude_extensions` is not a
  sandbox: extension factory code executes during discovery before its handlers
  and tools are filtered. `isolated: true` removes extensions and skills.
- A child's own tools are not narrowed by its parent's tools. Therefore
  `allowed_subagents` grants the parent the union of every allowed child's
  capabilities and must be treated as a privilege boundary.

Source: `src/agent-runner.ts` (`sessionTools`, `excludeTools`, and
`beforeToolCall`) and `README.md#tool--extension-scoping`.

### Turns, nesting, and concurrency

Effective turn-limit precedence is agent frontmatter, Agent call, then project
`defaultMaxTurns`. At the limit the extension steers "wrap up"; after
`graceTurns` additional completed turns it aborts. Omitted/zero is unlimited.
The Agent call schema does not accept zero, so callers omit the field.

The managed source policy caps ordinary direct-background lanes at 50 per
campaign, with the effective project/global `maxConcurrent` pool as an additional
limit: dispatch no more than `min(50, effective maxConcurrent)`. Project settings
may lower the global 50 default. Count any explicitly scheduled or foreground
top-level work separately against the same campaign ceiling; excess ready work
stays pending, and the finite task backlog is not capped at 50.

Other execution paths have separate limits and are not counted by that direct
lane cap:

- New blocking foreground spawns use `maxConcurrentForeground`; default zero is
  unlimited. Foreground resumes bypass it. Ordinary main-session delegation is
  explicitly background, but this default does not disable foreground support
  for explicitly requested workflows/tasks.
- Nested children occupy neither runtime pool and do not consume
  `maxConcurrent`; depth is bounded at 2, but runtime width is not. Count them
  with the main root's direct lanes and every coordinator in the shared 50-lane
  campaign cap. Use only the nested budget assigned by the parent; without an
  explicit budget, allow at most one concurrent child, reduced if active root
  lanes leave less room. Any parent with nested children must collect each
  owned child's terminal result before it settles: the manager aborts a parent's
  children when that parent settles. Nested waits are allowed inside an
  authorized background parent, not at the main root. Only roles with
  `allowed_subagents` can spawn nested children; ordinary worker roles do not
  grant child tools.
- Workflow children use their own CPU-based limit and do not enter either pool.
  Run a workflow only when the user explicitly requests one.
- Scheduled fires bypass `maxConcurrent`; schedules are session-scoped. They
  remain available when explicitly authorized, but this is not validation of a
  durable unattended campaign.
- Main-root calls default to background. `defaultJoinMode: async` returns
  control to the main root after direct dispatch; completion notifications
  support short accounting turns without foreground waits or polling.

Source: `src/agent-manager.ts`, `src/nested-tools.ts`, `src/agent-runner.ts`, and
`README.md#concurrency` / `#graceful-max-turns`.

### Model resolution and accounting

Resolution is exact available `provider/modelId`, then fuzzy matching, then the
same model under another provider. An unavailable frontmatter pin inherits the
parent model; `/agents` exposes that fallback. A pinned frontmatter model is the
initial role selection, not an immutable session choice: pi-model-fallback can
switch it with `setModel` after a matching provider failure. A fallback target's
thinking level may be reapplied from the target/global default and clamped by
that model, so frontmatter `thinking: max` is not guaranteed after a switch.
Keep canonical installed IDs in frontmatter instead of relying on fuzzy
selection.

`showCost` uses rates embedded in Pi's model catalog and is explicitly an
estimate. For `openai-codex` subscription auth it is **not a measurement of
ChatGPT Pro allowance consumption**. `reportUsage` only folds child usage into
Pi's parent-session accounting. Use the Codex usage dashboard or `/status` for
plan allowance.

Source: `src/model-resolver.ts`, `src/agent-runner.ts`, Pi
`docs/models.md`, and the installed `pi-ai` provider catalog.

## Captured OpenAI routing and quota notes

The following source research is a snapshot; provider guidance and plan ranges
can change. Re-check the linked sources before using it for a new model decision.
OpenAI's Codex guidance at the time said:

- Astra is for the hardest end-to-end workflows; Sol for complex/open-ended
  work; Terra for everyday work; Luna for clear, repeatable and high-volume
  work.
- Use the lowest reasoning effort that works. Medium balances speed and depth;
  high/extra-high is for difficult multi-step work; Max is for the hardest
  problems, and most tasks need neither Max nor Ultra.
- The plan allowance depends on model, context, reasoning, tools, retrieval,
  caching, and task complexity. The published local-message ranges are
  estimates, not fixed limits, and weekly limits may also apply.
- The current Pro ranges per five-hour period are 25-225 Astra messages,
  50-500 Sol, 125-1,000 Terra, and 1,250-10,000 Luna. These estimates show
  that model choice can materially affect allowance, but do not predict a
  specific Pi task's consumption.
- Astra responds to explicit delegation guidance and can otherwise delegate less
  than desired. OpenAI also recommends auditing long skills/instruction files
  and calibrating verification so small changes do not trigger broad tests.

The community `donvito/codex-astra-luna-orchestrator` repository is a useful
pattern, not an OpenAI authority. Its Pro profile pins an Astra-medium root and
Luna-max workers; its Plus profile moves the root to Luna. Its own usage guide
warns that one sample cannot estimate another account/task and that the plan
mapping must be measured. This repository sets Luna max as the startup default
for new sessions while keeping named-role pins independent; the active main
session follows Pi's runtime model selection.

### Quota caveat

An Astra-selected main session can materially consume more Pro allowance than
a Luna-selected one. `showCost` is Pi's catalog-based estimate, not plan usage;
measure allowance pressure with Codex's own status or dashboard. Use `/model` for
an active-session choice; this policy adds no model switch based on turn count or
main-model identity.

## Community comparison

This comparison is pinned to `donvito/codex-astra-luna-orchestrator` HEAD
`575e74e` (`575e74ebcf9b199513151a8996665a71cf64ce50`). Its Pro profile uses
an Astra-medium root, Luna-max explorer/worker/tester/researcher lanes, an
Astra-low reviewer, and concurrency 4. Transferable patterns are the
root-versus-delegated routing, bounded packets, parallel independent lanes,
one writer per path or subsystem, compact evidence, explicit failed-lane
handling, and a completion gate. Pi defaults new sessions to Luna max while
keeping the main session's active model selection independent of named-role
pins; it retains its Astra-low reviewer pin, expands the background cap to 50,
and keeps tester/researcher work one-off rather than permanent roles.

Codex-only settings intentionally not copied are `approval_policy`,
`sandbox_mode`, `service_tier`, `[agents].*`, the `spawn_agent`/wait tool names,
Codex rollout accounting, and true read-only sandbox guarantees. Pi equivalents
are `settings.json`, role frontmatter, `Agent`/`TaskExecute`, the Task ledger,
and tool scoping/worktree directives; Pi worktree and read-only behavior are
directives or filesystem copies, not OS sandboxes.

## Primary links and installed sources

- OpenAI model selection: <https://developers.openai.com/codex/models>
- OpenAI Codex pricing and plan limits: <https://developers.openai.com/codex/pricing>
- OpenAI Astra behavior/prompting: <https://developers.openai.com/api/docs/guides/latest-model>
- OpenAI reasoning effort: <https://developers.openai.com/api/docs/guides/reasoning>
- OpenAI Codex prompting guide: <https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide>
- Community topology: <https://github.com/donvito/codex-astra-luna-orchestrator>
- Pi core docs: `/opt/homebrew/Cellar/pi-coding-agent/0.86.1/libexec/lib/node_modules/@earendil-works/pi-coding-agent/docs/{settings,models,skills,extensions,configuration}.md`
- pi-subagents package: `~/.pi/agent/npm/node_modules/@tintinweb/pi-subagents/{README.md,docs/workflows.md,src/settings.ts,src/custom-agents.ts,src/invocation-config.ts,src/prompts.ts,src/agent-runner.ts,src/agent-manager.ts,src/nested-tools.ts,src/model-resolver.ts}`
