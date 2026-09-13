# Pi subagents and model routing

This note records the behavior verified for **Pi 0.85.1** and
**`@tintinweb/pi-subagents` 0.19.0**. Re-check the installed sources after an
upgrade; extension behavior is not a Pi core contract.

## Selected defaults

| Concern | Choice | Reason |
| --- | --- | --- |
| Root session | `openai-codex/gpt-6-astra`, medium; the Astra root coordinates directly | Astra owns architecture, decomposition, integration, and final verification without an Astra→Astra hop. |
| Routing gate | Delegate only when a bounded lane’s benefit outweighs its startup and context cost; explicit `orchestrator` only for a non-Astra root | Put coordination where it pays for itself instead of routing an Astra root through another Astra role. |
| Orchestrator | `openai-codex/gpt-6-astra`, medium | This explicit role is the coordination entrypoint for a non-Astra root when cross-lane coordination warrants it. |
| Implementer | `openai-codex/gpt-5.6-luna`, max | Bounded implementation stays on the default Luna execution lane. |
| Explore | `openai-codex/gpt-5.6-luna`, max | The custom `Explore` override replaces the built-in role for bounded repository mapping. |
| Effect specialist | `openai-codex/gpt-5.6-luna`, max | `effect-senior` remains the Luna-max lane for challenging, well-scoped Effect work. |
| Reviewer | `anthropic/claude-opus-5`, medium | Independent provider/model; a local role preference, not an OpenAI recommendation. |
| UI/UX | `opencode/gemini-3.8-flash`, no role-level thinking pin | A local role preference for visually central UI/UX work; it inherits Pi’s configured default thinking level, then Pi clamps that level to the model. |
| Background concurrency | 16 | `maxConcurrent` caps top-level background work; excess concrete lanes queue. |
| Foreground concurrency | omitted (`0`, unlimited) | `maxConcurrentForeground` keeps its installed unlimited default. |
| Turn limits | no default cap (`defaultMaxTurns` omitted); named roles omit `max_turns` | Avoids a global interruption ceiling; packets may add a task-specific limit. |
| Nesting | depth 2 | `maxSubagentDepth` bounds nested delegation while the root retains coordination. |
| Workflows | enabled; execution requires explicit user opt-in | `workflowsEnabled: true` registers `SubagentWorkflow`; agent policy permits a run only when the user explicitly requests a workflow in the current task. No additional project opt-in is required. |
| Dispatch | strict fallback (`none`) | A misspelled or disabled type fails instead of silently running `general-purpose`. |
| Agent mentions | `direct` | Avoids an extra root-model turn when starting a mentioned agent. |
| Tool description | compact | Reduces always-loaded tool-schema context. |

The model names above are **installed Pi registry IDs/aliases**, confirmed with
`pi --list-models`. OpenAI's public IDs include `gpt-6-astra`,
`gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna`. `opencode/...` and
Anthropic IDs are provider registry entries, not OpenAI model IDs.

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

The default Astra root owns architecture, delegation, integration, and final
verification directly; it is distinct from the explicit `orchestrator` role.
The explicit orchestrator coordinates, delegates, verifies, and communicates,
while edits go to `implementer` or the relevant writer specialist. If a writer
is denied permission, hand off to another authorized writer rather than retrying
the orchestrator. This explicit-role rule does not blanket-ban edits by the
default root when it owns the task.

## `subagents.json` settings

Global settings live at `$PI_CODING_AGENT_DIR/subagents.json` (normally
`~/.pi/agent/subagents.json`); project settings live at
`<cwd>/.pi/subagents.json`. Project keys shallowly override global keys.
Invalid or out-of-range fields are dropped individually.

| Field | Installed default and accepted values |
| --- | --- |
| `maxConcurrent` | `10`; integer `1..1024`. Top-level background pool. |
| `maxConcurrentForeground` | `0` (unlimited); integer `0..1024`. Blocking foreground spawn pool. |
| `defaultMaxTurns` | omitted/`0` (unlimited); integer `0..10000`. |
| `graceTurns` | `5`; integer `1..1000`. |
| `defaultJoinMode` | `smart`; `smart`, `async`, or `group`. Background only. |
| `backgroundByDefault` | `true`; explicit call/frontmatter wins. |
| `schedulingEnabled` | `true`; false removes scheduling from the next session's Agent schema. |
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
| `workflowsEnabled` | unset means auto-on unless another workflow tool exists; explicit boolean pins it. |
| `maxSubagentDepth` | `2`; integer `0..16`; `0` or `1` disables nesting. |
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

There are two independent pools:

- Top-level background spawns use `maxConcurrent`; excess work queues.
- New blocking foreground spawns use `maxConcurrentForeground`; default zero is
  unlimited. Foreground resumes bypass it.
- Pi dispatches sibling tool calls from one assistant message concurrently after
  sequential preflight, so multiple foreground Agent calls can start together.
- Nested children occupy neither pool to avoid parent/child deadlock. Depth is
  bounded, but width is not; each child spawn merely costs the parent one turn.
  This configuration therefore caps orchestrator waves in prompt policy.
- Workflow children use their own CPU-based limit and do not enter either pool.
  Scheduled fires bypass `maxConcurrent`. These are reasons not to treat 16 as a
  process-wide ceiling.
- Nested children default foreground, are ownership-scoped, and are stopped when
  their parent settles. Top-level calls default background here; `smart` joins
  siblings spawned in one turn into a consolidated notification.

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

## OpenAI routing and quota evidence

OpenAI's current Codex guidance says:

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
  50-500 Sol, 125-1,000 Terra, and 1,250-10,000 Luna. These ranges reinforce
  delegating routine execution to Luna and keeping Astra focused on coordination
  where its allowance cost is justified, but they do not predict a specific Pi
  task's consumption.
- Astra responds to explicit delegation guidance and can otherwise delegate less
  than desired. OpenAI also recommends auditing long skills/instruction files
  and calibrating verification so small changes do not trigger broad tests.

The community `donvito/codex-astra-luna-orchestrator` repository is a useful
pattern, not an OpenAI authority. Its Pro profile pins an Astra-medium root and
Luna-max workers; its Plus profile moves the root to Luna. Its own usage guide
warns that one sample cannot estimate another account/task and that the plan
mapping must be measured. This configuration makes Luna max the default for
bounded execution and repository exploration while retaining Astra-medium root
coordination.

### Quota caveat

The Astra root stays in the coordination loop and can materially consume more
Pro allowance than a Luna root. `showCost` is Pi's catalog-based estimate, not
plan usage; measure allowance pressure with Codex's own status or dashboard. If
measured allowance pressure outweighs coordination quality, switch the root back
to Luna max while retaining the role topology.

## Community comparison

This comparison is pinned to `donvito/codex-astra-luna-orchestrator` HEAD
`575e74e` (`575e74ebcf9b199513151a8996665a71cf64ce50`). Its Pro profile uses
an Astra-medium root, Luna-max explorer/worker/tester/researcher lanes, an
Astra-low reviewer, and concurrency 4. Transferable patterns are the
root-versus-delegated routing, bounded packets, parallel independent lanes,
one writer per path or subsystem, compact evidence, explicit failed-lane
handling, and a completion gate. Pi keeps the root and bounded Luna-max
execution shape, uses its local Opus 5 reviewer preference, expands the
background cap to 16, and keeps tester/researcher work one-off rather than
permanent roles.

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
- Pi core docs: `/opt/homebrew/Cellar/pi-coding-agent/0.85.1/libexec/lib/node_modules/@earendil-works/pi-coding-agent/docs/{settings,models,skills,extensions}.md`
- pi-subagents package: `~/.pi/agent/npm/node_modules/@tintinweb/pi-subagents/{README.md,docs/workflows.md,src/settings.ts,src/custom-agents.ts,src/invocation-config.ts,src/prompts.ts,src/agent-runner.ts,src/agent-manager.ts,src/nested-tools.ts,src/model-resolver.ts}`
