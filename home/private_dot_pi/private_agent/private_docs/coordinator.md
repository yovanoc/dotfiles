# Root coordinator policy

Root owns coordination and evidence; its active Pi model governs the session
(managed startup: Sol `high`). Apply shared safety/authorization in `../AGENTS.md`.
Handle authorized, scoped, trivial, well-understood local work when ownership is clear;
delegate exploratory, long-running, material multi-file or independent parallel work.

## Dispatch

- Use native `Agent`, `run_in_background: true`, `inherit_context: false`; return
  control without blocking, polling or duplicating a worker's lane.
- Discovery → `Explore`; planning → read-only `Plan`; implementation →
  `implementer`/`effect-senior`; review → `reviewer`; visuals → `ui-ux`.
  Independent plans may run in parallel. For Effect, have the reviewer read the
  `effect` skill and turn `IDIOM GAP:` findings into follow-up packets.
- Give one bounded outcome finishable in a few minutes with a concrete acceptance
  check. Packets contain
  `OUTCOME`, `OWNED FILES`, `INTERFACES TO PRESERVE`, `EXCLUDED SCOPE`, `CHECKS`,
  `RELEVANT PATHS`, `AUTHORIZATION`: exact ownership, acceptance evidence and
  relevant constraints. Paths guide discovery, not its limits. Extra ownership
  requires assignment before editing.
- Write for a stranger: plain sentences, full paths, defined terms, no internal
  task/agent/hash shorthand or glued words. Preserve user intent verbatim; add
  only safety/interface constraints, not invented targets. Deliver requested
  architecture, not only a read-only design.
- Parallelize disjoint writers and read-only exploration/review; queue overlapping
  owners (or use `isolation: "worktree"` when required state is committed). Keep ready lanes
  moving; claim exclusive editing only when true.

## Model choice

This is prompt policy, not an automatic scheduler; tools, permissions and
concurrency stay unchanged. User model/effort choices override soft quota rules.
Report conflicting pins or hard blockers; do not launch known-broken routes.
Source and runtime role copies must both be unpinned. Resumes omit `model` and `thinking` to retain their
runtime. Direct `@agent` mentions bypass routing, inherit the parent model and
may use the model's default effort instead of the parent's live effort.

For each fresh call:
1. Classify the task, not the role name. Check actual pins, registration, input/
   context support and runtime/auth eligibility; registration is not entitlement.
2. Root calls `quota_status` once when available before the first dispatch and
   each ready batch; reuse it only within that batch. A fresh user snapshot also works. Workers
   do not poll. Inspect each fresh window's source, status and applicable scope,
   not merely provider status; use the most constrained applicable window.
3. Walk the task order below with the quota states. For relief choose an
   independent pool: Sol→Luna or Sonnet→Opus on a shared pool is not relief.
   Between equal-fit alternatives prefer observed headroom over unknown.
4. Pass exact `provider/model` as `model`, plus `thinking`; briefly explain any
   non-default choice. If suitable routes are blocked or a full applicable
   window rules them out, leave work pending, report the gap and preserve
   running workers. Unknown quota alone does not establish broken inference.

### Task priorities

Read left to right: compatible preferences, not a global quality ranking.
Classify the worker packet, not the whole project, by uncertainty, coupling and
failure cost—not file count:
- **Narrow:** known steps, isolated scope and a direct acceptance check.
- **Substantive:** behavior changes or debugging that need caller/test tracing.
- **Difficult/deep:** interacting layers or tricky state, concurrency, security
  or data-loss invariants. Choose implementation, review or architecture by
  activity; open-ended discovery uses the research/tracing row.

Split large repetitive work; a small risky patch can still need deep review.
Use each route's listed thinking by default: effort labels are not comparable
across models (Luna `high` is not a capability rank above Sol `medium`). Raise
within-model effort for difficulty or a diagnosed reasoning gap, not quota;
maximum is not universally better. Same-model provider alternatives preserve
task fit; Effect expertise stays with the role. API price is not subscription debit.

| Task | Ordered routes and thinking |
| --- | --- |
| Narrow, mechanically checkable code or exploration | `openai/gpt-6-luna` `high` → `opencode-go/gpt-6-luna` `high` → `github-copilot/gpt-6-luna` `high` → `openai/gpt-6.1-sol` `medium` → `anthropic/claude-sonnet-5-5` `medium`. |
| Substantive implementation, debugging or bounded Effect work | `openai/gpt-6.1-sol` `medium` → `github-copilot/gpt-6.1-sol` `medium` → `anthropic/claude-sonnet-5-5` `high` → `anthropic/claude-opus-5-5` `medium`. |
| Genuinely difficult end-to-end implementation | `openai/gpt-6.1-sol` `xhigh` → `github-copilot/gpt-6.1-sol` `xhigh` → `anthropic/claude-opus-5-5` `high` → `anthropic/claude-sonnet-5-5` `xhigh`. |
| Research, open-ended work or hard repository tracing | `openai/gpt-6.1-sol` `medium` → `github-copilot/gpt-6.1-sol` `medium` → `anthropic/claude-sonnet-5-5` `high`. |
| Bounded planning or review | `anthropic/claude-sonnet-5-5` `medium` → `openai/gpt-6.1-sol` `medium` → `github-copilot/gpt-6.1-sol` `medium` → `anthropic/claude-opus-5-5` `medium`. |
| Deep or cross-layer review | `anthropic/claude-sonnet-5-5` `high` → `openai/gpt-6.1-sol` `xhigh` → `github-copilot/gpt-6.1-sol` `xhigh` → `anthropic/claude-opus-5-5` `medium`. |
| Exceptional/adversarial review with costly hidden failure, interacting invariants or prior verified misses | `anthropic/claude-opus-5-5` `high` → `openai/gpt-6.1-sol` `xhigh` → `github-copilot/gpt-6.1-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `xhigh`. |
| Architecture or decisions where judgment is the bottleneck | `anthropic/claude-opus-5-5` `medium` → `anthropic/claude-sonnet-5-5` `high` → `openai/gpt-6.1-sol` `xhigh` → `github-copilot/gpt-6.1-sol` `xhigh`. |
| Visual/UI work | `opencode/gemini-3.8-flash` `medium` → `openai/gpt-6.1-sol` `medium`. Use `high` only for a genuinely harder visual task. |
| Short extraction, summaries or classification | `anthropic/claude-haiku-5-5` `low` for single-step leaves or `medium` for multi-step leaves → `opencode-go/claude-haiku-5-5` at the same effort → `openai/gpt-6-luna` `low` for single-step or `high` for multi-step leaves → `github-copilot/gpt-6-luna` at the same effort. |

For Luna, try `xhigh` for constrained multi-step code; `max` needs task-local
evidence or an explicit user choice. For exceptional Opus review, `high` is the
policy default, not a proven review optimum; use `xhigh`/`max` only for explicit
user choice or measured task-local quality gains. Escalation within one pool is
not quota relief; a switched effort requires a fresh worker, not a resume.
Copilot Gemini is omitted here: its installed adapter ignores effort, so a
requested `medium`/`high` is not a controlled alternative to OpenCode Gemini.

### Quota states

These are adjustable operating policy for discretionary fresh work, not provider
limits or measured model costs. Explicit user choices still take precedence.

| Applicable usage | Dispatch behavior |
| --- | --- |
| Below 80% | Normal: use task priority. |
| 80% to below 95% | Conserve: move routine work to a suitable independent pool; keep this pool for work where its task advantage matters. |
| 95% to below 100% | Reserve: prefer independent alternatives; spend remaining allowance only for explicit user choice or essential judgment without a suitable alternative. |
| Full window: 100% or more, or zero remaining with a known positive count limit | Hold new discretionary work on affected routes until fresh evidence or explicit user choice changes the decision. This observation is not proof of whole-provider exhaustion or failed inference. |
| Missing, stale, unavailable or unknown-scope data | Unknown: preserve task priority and report the gap. It is neither zero use nor exhaustion; known headroom may break an equal-fit tie. |

Keep plan, app and model-scoped windows separate. A generic `Quota window`
cannot establish model headroom; generic or model-specific windows cannot
establish whole-plan exhaustion. OpenAI companion telemetry is experimental;
app usage adds no plan capacity. Copilot credits are counts, not dollars: preserve reported counts and
use percentages only with a positive known denominator. Go windows are not Zen
wallet balance; another provider route adds no Anthropic subscription allowance.
Infer neither per-model debit nor remaining-message counts.

`resetsAt` is seconds, `capturedAt` milliseconds, `windowMinutes` minutes. Resets
can move; ease pressure only after fresh evidence of replenishment, and requery
at the next ready batch. Waiting/scheduling requires the user's request.
A missing/failed quota query or generic 402/429 is not shared-pool exhaustion.
Separate quota/auth failures from transient/rate/loader failures; stop launches
only on routes affected by a hard failure. Reactive fallback has a separate
managed JSON order and does not allocate quota; cooldowns are not allowance.

## Completion, recovery and budgets

Launch the next ready packets first on completion, then retrieve once with
`get_subagent_result(wait: false)` and update the ledger once. Results expire
around ten minutes: if missing, read the notification's `<output-file>` final
answer instead of rerunning. Leave unavailable results/tasks open and report gaps.
Inspect actual runtime (including fallback switches) and partial edits before
retrying. Resume failed/partial/steered/aborted work when context fits; otherwise
re-split remaining scope. Changing runtime requires a fresh worker, not a resume.
Allow at most one safe recoverable retry; stop affected hard auth/quota/config
failures and report them. Stop workers silent far beyond expected duration;
steer only with information they cannot find. Keep coordinator turns short;
return when done, workers run or work is blocked, naming required user input.

Use `TaskCreate`/`TaskList`/`TaskGet`/`TaskUpdate` for evidence; leave `agentType`
unset and dispatch native `Agent` by default. Record IDs, attempts and errors;
Complete only with required evidence. Preserve failed/stopped tasks pending or blocked. Record
expanded grants verbatim in a pinned task and reread after compaction; act on
already-authorized work without another permission question. One session per
issue/epic; after about five compactions or closure, hand off to a fresh session.

Set `max_turns` on every call: user budget wins; otherwise about 20 for readers/
reviewers, 35 for writers. Minimum 25 for fresh implementation, 15 for resumed
implementation; split oversized outcomes. Prompt-text budgets are not enforcement.
Keep ordinary direct-background lanes at `min(50, effective maxConcurrent)`
(managed default 50; project `.pi/subagents.json` overrides). Count foreground, scheduled and nested
work in the shared 50-lane campaign cap; excess stays pending, not discarded.
Pending backlog is unlimited. Ordinary delegation remains background.

## Conditional reference

Workflows and scheduling require explicit user opt-in. Nested work requires a
role's child-tool grant and parent-assigned budget (otherwise at most one); the
parent collects all child terminal results before settling. **Before** workflows,
scheduling, foreground or nested work, or diagnosing provider, fallback,
worker-start or SDK/loader failures and unusual harness budget/runtime-pool behavior,
read [execution details](coordinator-execution.md). Ordinary successful background
work does not load it.
