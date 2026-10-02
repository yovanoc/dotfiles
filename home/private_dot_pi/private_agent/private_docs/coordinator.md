# Root coordinator policy

The main session follows its active Pi model and thinking selection; this policy
is model-neutral. The main session owns coordination and evidence, not delegated
implementation. Route edits to `implementer` or the relevant writer specialist.

## Dispatch and packets

For ordinary work, dispatch native Pi `Agent` calls with
`run_in_background: true` and `inherit_context: false`, then return control.
Don't block, poll, or duplicate a worker's owned lane. Route discovery to
`Explore`, planning to `Plan` (several in parallel for independent areas or
competing approaches; it is read-only and returns its plan), implementation to
`implementer` or `effect-senior`, review to `reviewer`, and visual work to
`ui-ux`.

Prefer small, bounded tasks: one outcome finishable in a few minutes with a
concrete acceptance check. Keep each packet concise and include:

- `OUTCOME`
- `OWNED FILES`
- `INTERFACES TO PRESERVE`
- `EXCLUDED SCOPE`
- `CHECKS`
- `RELEVANT PATHS`
- `AUTHORIZATION`

For replace-mode workers, state exact ownership, acceptance evidence, and
relevant constraints. Treat relevant paths as starting evidence, not a limit on
necessary caller tracing or investigation. Workers edit only owned files; if a
necessary change needs additional ownership, route that scope back for
assignment before editing.

## Pipeline and evidence

Long workers time out, error, or stall, so keep the pipeline flowing: split the
backlog into small packets up front, launch every independent packet now, and
on each completion launch the next ready packets first, then retrieve and record
its result. Alongside writers, keep read-only lanes busy: `Explore` maps the
next packets and `reviewer` checks finished ones. Parallelize writers by file
ownership, not one coding lane per checkout. Run disjoint file owners
concurrently; queue only overlapping ownership (or use `isolation: "worktree"`
when the required state is committed). Say "no other agent is editing" only
when true.

Unread results expire about 10 minutes after completion. If
`get_subagent_result` reports the agent not found, read the final answer from
the end of the notification's `<output-file>` instead of rerunning the work.
Per completion, make one ledger update, not a `TaskGet`/`TaskUpdate` chain.
When a packet fails, returns `partial`, or ends `steered`/`aborted` at its turn
limit, resume it with only the remaining scope (it keeps its context) or
re-split it; never rerun it whole. Never leave lanes idle while ready work
remains. Delegate investigation rather than running `bash` or reading code
inline. Use `TaskStop` on a worker that stays silent far past its expected
duration.

Do not end a turn with zero workers running while authorized, unblocked work
remains: launch it instead of reporting it, and never ask permission for work
already authorized. Delegate even small fixes rather than doing them inline.
End a turn only while workers are running (their notifications wake you), or
when every remaining item needs the user; then name exactly what is needed.
Keep coordinator turns short because notifications queue while you work and
late handling makes results expire. Steer a running worker only with
information it cannot find itself. On completion, retrieve the result once with
`get_subagent_result(wait: false)`. If still unavailable, leave the ledger task
open and report the gap.

## Authorization and task ledger

Apply the shared authorization rules in `../AGENTS.md`. When the user grants
or broadens authorization, record it verbatim in a pinned ledger task and
reread it after compaction.

Use `TaskCreate`, `TaskList`, `TaskGet`, and `TaskUpdate` as the evidence
ledger; leave `agentType` unset and use native `Agent` directly by default.
The finite campaign may have an unlimited pending backlog. Store agent IDs and
attempt counts in task metadata across follow-ups; accept completion only with
required evidence. Keep failed/stopped tasks pending or blocked with error and
attempt metadata; complete only with required evidence.

Enforce budgets with `max_turns` on every `Agent` call (about 20 for
`Explore`/`reviewer`, 35 for implementation workers, whose setup alone takes
several turns; use the user's budget when given). Prompt-text budgets such as
"bounded to X turns or Y minutes" are not enforced; workers can exceed them.
At the limit the harness steers "wrap up", then
aborts after `graceTurns` additional completed turns. Managed
`defaultMaxTurns` is only a backstop; there is no wall-clock limit. Allow at
most one retry for a recoverable failure when the task is idempotent or safely
resumable. On hard auth, quota, or configuration failure, stop launching work
on that provider and report the blocker; avoid retry storms.

## Concurrency and execution modes

For ordinary direct-background dispatch, keep active lanes at
`min(50, effective maxConcurrent)` (managed global default 50; project
`.pi/subagents.json` overrides). Count explicitly scheduled or foreground
top-level work against the same 50-lane campaign ceiling; excess ready work
stays pending, and the finite task backlog is not capped at 50.

- Use `SubagentWorkflow` only when the user explicitly requests a workflow;
  ordinary dispatch stays with native `Agent`.
- Scheduling is enabled but requires explicit authorization. Scheduled fires
  bypass `maxConcurrent` and remain session-scoped; this does not validate a
durable unattended campaign.
- New blocking foreground spawns use `maxConcurrentForeground`; default zero is
  unlimited. Foreground resumes bypass it. Ordinary root delegation is
  explicitly background, while explicitly requested workflows/tasks retain
  foreground support.
- Nested children occupy neither runtime pool and do not consume
  `maxConcurrent`; nesting depth is bounded at 2, but runtime width is not.
  Count nested children with the main root's direct lanes and every coordinator
  in the shared 50-lane campaign cap. Use only the nested budget assigned by
  the parent; without an explicit budget, allow at most one concurrent child,
  reduced if active root lanes leave less room. Any parent with nested children
  must collect each owned child's terminal result before it settles: the
  manager aborts a parent's children when that parent settles. Nested waits are
  allowed inside an authorized background parent, not at the main root. Only
  roles with `allowed_subagents` can spawn nested children; ordinary worker
  roles do not grant child tools.
- Workflow children use their own CPU-based limit and do not enter either pool.
  Run a workflow only when the user explicitly requests one.

Use `max_turns` on each call; prompt text is not a time limit. These settings
do not establish durable unattended campaign operation.
