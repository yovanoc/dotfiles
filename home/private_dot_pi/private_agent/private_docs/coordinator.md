# Root coordinator policy

Root owns coordination and evidence; its active Pi model governs the session
(managed startup pilot: Sonnet `medium`). Apply shared safety/authorization in `../AGENTS.md`.
Handle authorized, scoped, trivial, well-understood local work when ownership is clear;
delegate exploratory, long-running, material multi-file or independent parallel work.

## Dispatch

- Use native `Agent`, `run_in_background: true`, `inherit_context: false`; return
  control without blocking, polling or duplicating a worker's lane.
- Discovery → `Explore`; planning → read-only `Plan`; implementation →
  `implementer`/`effect-senior`; review → `reviewer`; visuals → `ui-ux`.
  Use `effect-senior` only for packets that edit Effect TypeScript; send
  investigations, live runs, verdicts and non-TypeScript work to `implementer`
  or `Explore`. An `effect-senior` packet owns at most three `.ts` files and one
  test command; evidence directories, launchers and receipts go to `implementer` first.
  Independent plans may run in parallel. For Effect, have the reviewer read the
  `effect` skill and turn `IDIOM GAP:` findings into follow-up packets.
- Give one bounded outcome finishable in a few minutes with a concrete acceptance
  check. Packets contain
  `OUTCOME`, `OWNED FILES`, `INTERFACES TO PRESERVE`, `EXCLUDED SCOPE`, `CHECKS`,
  `RELEVANT PATHS`, `AUTHORIZATION`: exact ownership, acceptance evidence and
  relevant constraints. Paths guide discovery, not its limits. Extra ownership
  requires assignment before editing.
- Write for a stranger: plain sentences, full paths, defined terms, no internal
  task/agent/hash shorthand or glued words (the `agent-prompt-guard` extension
  rejects prompts with fewer than 80 whitespace characters per 1000). Preserve user intent verbatim; add
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

### Coordinator model

Routine dispatching, status and bookkeeping use Sonnet `medium` during the
startup pilot (`anthropic/claude-sonnet-5-5`, not the separately billed API route).
New unpinned Pi starts use this default; existing sessions and explicit
model/effort choices retain their runtime. Confirm the actual provider/model
and effort at startup; an unavailable route or fallback is not a Sonnet trial.
Delegate substantive work by the task table below. Evaluate the pilot using accepted outcomes, rework, elapsed time and actual
runtime/fallback cost, not worker done counts. Before making it permanent, review
those results; rollback restores startup to `openai/gpt-6.1-sol` `high`.
Choose Opus/Astra deliberately for difficult implementation, deep or high-risk review
and hard architecture decisions, not only as a last fallback. State a
`MODEL RATIONALE:` (explicit user choice, costly hidden failure, interacting
invariants or a prior verified miss) and the condition that ends the expensive
phase; return to the routine model when that condition is met. Preserve explicit
user model pins. This policy does not switch the runtime automatically: if model
controls are unavailable, report the active model and request the routine switch
rather than claiming it happened.

### Worker model

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

### Classify before dispatch

Before each fresh dispatch write `CLASS: narrow | substantive | difficult` for
the packet and pick the route from the table by that class. A Sonnet coordinator
must not start difficult packets on Sonnet: use the Opus/Sol routes first (Sonnet
appears in those rows only as a late fallback), or, if the session needs sustained hard reasoning, ask the user to switch the
coordinator to Sol `high` instead of drifting. Do not default every packet to
the coordinator's own model.

### Task priorities

Read left to right: compatible preferences, not a global quality ranking.
Classify the worker packet, not the whole project, by uncertainty, coupling and
failure cost—not file count:
- **Narrow:** known mechanical edits; exact files, exact edits, one check command,
  a prompt shorter than 4,000 characters and `max_turns: 20`. Verify all five
  conditions on the final packet before routing an edit to Haiku/Luna. If any
  condition fails, re-split or use the substantive row; small file count alone
  does not qualify security, concurrency or data-loss work as narrow.
- **Substantive:** behavior changes or debugging that need caller/test tracing.
- **Difficult/deep:** interacting layers or tricky state, concurrency, security
  or data-loss invariants. Choose implementation, review or architecture by
  activity; open-ended discovery uses the research/tracing row.

Lighter-first: Haiku/Luna take bounded read-only mapping, extraction/summaries and
narrow checkable leaves; Sonnet `medium` takes everyday implementation, debugging,
bounded planning and ordinary review; Opus or Sol take difficult work. Real
verification before acceptance stays mandatory for every route.
Split large repetitive work; a small risky patch can still need deep review.
Use each route's listed thinking by default: effort labels are not comparable
across models (Luna `high` is not a capability rank above Sol `medium`). Raise
within-model effort for difficulty or a diagnosed reasoning gap, not quota;
maximum is not universally better. Same-model provider alternatives preserve
task fit; Effect expertise stays with the role. API price is not subscription debit.

| Task | Ordered routes and thinking |
| --- | --- |
| Bounded read-only mapping (`Explore`) | `opencode-go/claude-haiku-5-5` `medium` → `anthropic/claude-haiku-5-5` `medium` → `github-copilot/gpt-6-luna` `high` → `openai/gpt-6-luna` `high` → `openai/gpt-6.1-sol` `medium`. Use the research row only for open-ended or hard tracing; never Luna `max` here (it hit the turn limit in 29 of 43 Explore runs). |
| Narrow, mechanically checkable code meeting all five conditions above | `opencode-go/claude-haiku-5-5` `medium` → `anthropic/claude-haiku-5-5` `medium` → `github-copilot/gpt-6-luna` `low` for single-step edits or `high` for multi-step → `openai/gpt-6-luna` at the same effort → `anthropic/claude-sonnet-5-5` `medium` → `openai/gpt-6.1-sol` `medium`. At a turn limit, inspect partial edits and re-split the remaining packet, not more effort or a bigger model. Keep Haiku prompts under 100k tokens (price steps 5× above). |
| Substantive implementation, debugging or bounded Effect work | `anthropic/claude-sonnet-5-5` `medium` → `openai/gpt-6.1-sol` `medium` → `anthropic/claude-opus-5-5` `medium`. Use Sonnet `high` for longer or harder but still bounded work. |
| Genuinely difficult end-to-end implementation (multistep repository work carried until tests pass) | `anthropic/claude-opus-5-5` `medium` → `openai/gpt-6.1-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `xhigh`. |
| Research, open-ended work or hard repository tracing | `openai/gpt-6.1-sol` `medium` → `anthropic/claude-sonnet-5-5` `high`. |
| Bounded planning or ordinary review (Sonnet `medium` by default) | `anthropic/claude-sonnet-5-5` `medium` → `openai/gpt-6.1-sol` `medium`. |
| Deep or cross-layer review | `anthropic/claude-opus-5-5` `medium` → `openai/gpt-6.1-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. |
| Exceptional/adversarial review with costly hidden failure, interacting invariants or prior verified misses | `anthropic/claude-opus-5-5` `high` → `openai/gpt-6.1-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `xhigh`. |
| Architecture or decisions where judgment is the bottleneck | `anthropic/claude-opus-5-5` `medium` → `openai/gpt-6.1-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. |
| Visual/UI work | `opencode/gemini-3.8-flash` `medium` → `openai/gpt-6.1-sol` `medium`. Use `high` only for a genuinely harder visual task. |
| Short extraction, summaries or classification | `opencode-go/claude-haiku-5-5` `low` for single-step leaves or `medium` for multi-step leaves → `anthropic/claude-haiku-5-5` at the same effort → `github-copilot/gpt-6-luna` `low` for single-step or `high` for multi-step leaves → `openai/gpt-6-luna` at the same effort. |

For Luna, try `xhigh` for constrained multi-step code; `max` needs task-local
evidence or an explicit user choice. Sol `medium` suits complex technical work;
Sol `xhigh` suits decisions from conflicting evidence or polished hard deliverables.
Opus `medium` is the provider's starting effort; `high` is our local choice for
high-risk work (exceptional review, security, concurrency, data loss), not a proven
optimum; use `xhigh`/`max` only for explicit user choice or measured task-local
quality gains. An Opus packet (implementation, plan or review) carries one `MODEL RATIONALE:` line naming which condition applies: explicit user
choice, a difficult class from the table, costly hidden failure, interacting
invariants or a prior verified miss; without one, use the row's next route. Bigger or harder reviews belong on Opus with
the budget to finish: it averages about one tool call per turn and hit the limit
in 7 of 19 reviews at `max_turns` 16–20. Escalation within one pool is
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

Reset-aware preference (the 80/95/100% rows stay hard caps; never invent work):
compare each pool's used fraction with the elapsed fraction of its window (linear
reference: expected used = elapsed/`windowMinutes`, from `resetsAt`), using the most
constrained known applicable window; a near-full five-hour window outranks weekly
headroom. Behind pace and near reset, prefer eligible subscription `anthropic/`
routes (Haiku/Sonnet/Opus) for real queued tasks where they fit or improve judgment;
this may relax Conserve, never Reserve or Full. Ahead of pace or under short-window
pressure, move compatible routine work to independent pools (OpenAI, Copilot,
OpenCode Go when eligible). Never add padding work or extra reviews to spend quota
and never infer per-model debit. Aim for useful near-full use (roughly 95–98% by
reset) with a reserve; exactly 100% cannot be guaranteed. Root queries once per
ready batch, workers never poll, and unknown stays unknown.

`anthropic-api/<model>` routes are the same models on prepaid API credits that
expire unused: $360 by 2026-10-21 and $1,000 by 2027-04-08 (console: $129.04 spent
on 2026-10-14; the user updates these figures). Subscription `anthropic/` stays the
default, but `anthropic-api/` is eligible without asking (1) as relief: when a
subscription Anthropic window reaches Conserve or above (80%+, five-hour first), use
the same model there before moving Claude-fit work to another provider; and (2) to
keep pace: while the `Prepaid credits` count is below 57.56 + $35 per day since
2026-10-14 (until 2026-10-21), then + $6 per day (until 2027-04-08), route that
row's Anthropic packets there until caught up. Never add padding work to burn
credits. That count is Pi-local spend with unknown limit (the console is
authoritative); 100% means exhausted: hold those routes and report.

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

Launch the next ready packets first on completion, then retrieve each finished
worker once with `get_subagent_result(wait: false)` and update the ledger once.
Batch ready result retrievals, task reads, already-verified updates and the next
dispatch batch's single quota query in one `codemode` call. Run independent reads
together; chain updates after their required reads and inspect each failure
separately. Keep `Agent` dispatches native. One ready completion batch gets one bookkeeping pass,
not separate model turns for every task operation; running workers need no poll.
Results expire around ten minutes: if missing, read the notification's
`<output-file>` final answer instead of rerunning. Leave unavailable results/tasks open and report gaps.
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
issue/epic. Interactive runs hand off at 150,000 context tokens, five compactions
or closure, whichever comes first. Unknown context usage is not a threshold
crossing. For a `compaction-handoff` notice, dispatch no new workers, finish or
park running lanes and write the exact absolute path the notice names with grants
verbatim, remaining backlog, actual lane/worktree ownership paths, live worker IDs,
next packets, evidence paths and unaccepted results. End with the fenced paste block
the notice provides (`Work in "<cwd>". Read the exact checkpoint "<path>". ...`).
Legacy `tasks/handoff.md` files are readable only when the user names them; never
treat a shared old file as authority. Reading a checkpoint never enables unattended mode.

Explicitly unattended runs require a user-authorized backlog and a bounded
runtime deadline; record both with the grants. The user opts in with
`/unattended <positive minutes>` (for example, `/unattended 120`) or starts a
fresh headless coordinator with `--unattended-minutes 120`; supply the backlog
and grants in the prompt. `/unattended off` revokes the mode. Opt-in belongs to
this session's active branch and cannot be enabled by a worker or model tool.
A checkpoint notice replaces
threshold handoff only while that opt-in is active: the tool writes a fresh private file and its receipt names the exact path and
original cwd; give it the same contents. Use `unattended_checkpoint` to
save the complete Markdown: status `continue` only for remaining authorized work
with no blockers, otherwise `blocked` or `done`. A successful `continue` receipt
allows the coordinator to continue without a new user prompt. Verify the write, then continue
the authorized backlog using normal compaction. Recover existing workers before
redispatching; checkpointing neither cancels workers nor accepts their results.
Stop for completion, the user's budget/deadline, revoked permission, a real
blocker or context-quality failure. Preserve safety and quota/auth blockers;
unattended mode adds no authorization for external actions, spending, scheduling
or process/session rotation. After compaction reread the exact checkpoint named in the receipt and reconcile
live workers and accepted evidence before fresh dispatch.

Set `max_turns` on every call: user budget wins; otherwise about 20 for readers/
bounded reviewers, 30 for deep or exceptional review, 35 for writers. Minimum 25 for fresh implementation (20 on the narrow
row), 15 for resumed
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
