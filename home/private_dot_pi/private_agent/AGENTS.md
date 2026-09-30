# Agent Guidelines

- Use only the active Pi harness for coding-agent work; never launch external Codex or Claude CLIs; keep all delegation inside Pi.

## Reading and Navigation

Prefer cheap indexed, search, or structural navigation before broad reads.
Use targeted symbol or range reads for large files, and LSP/AST tools when available.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tools** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them. `codegraph_node` returns one symbol's source + callers, or reads a whole file with line numbers. If the tools are listed but deferred, load them by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` and `codegraph node <symbol-or-file>` print the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

## Subagent Routing

The main session follows its active Pi model and thinking selection; keep this
policy model-neutral. It acts as a responsive coordinator. For ordinary work,
dispatch native Pi `Agent` calls with
`run_in_background: true` and `inherit_context: false`, then return control.
Don't block, poll, or duplicate a worker's owned lane. Route discovery to `Explore`, planning to `Plan` (several in parallel for
independent areas or competing approaches; it is read-only and returns its
plan, so don't ask it to write files), implementation to
`implementer` or `effect-senior`, review to `reviewer`, and visual work to `ui-ux`.

Prefer many small, bounded tasks over one big one. Each packet should be a
single outcome (one file, one question, one fix) finishable in a few minutes
with a concrete acceptance check. Long workers time out, error, or stall, and
nothing advances while they run. Keep the pipeline flowing: split the backlog
into small packets up front, launch every independent one now, and on each
completion launch the next ready packets first, then retrieve and record its
result. Unread results expire about 10 minutes after the worker finishes; if
`get_subagent_result` reports the agent not found, read the final answer from
the end of the notification's `<output-file>` instead of rerunning the work.
When a packet fails, returns `partial`, or ends `steered`/`aborted` at its turn
limit, resume it with only the remaining scope (it keeps its context) or
re-split it; never rerun it whole. Never leave lanes idle while ready work
remains.

Keep coordinator turns short, because notifications queue while you work and
late handling makes results expire. Per completion, make one ledger update, not
a `TaskGet`/`TaskUpdate` chain; delegate investigation instead of running
`bash` or reading code inline; steer a running worker only with information it
cannot find itself.

Parallelize writers by file ownership, not one coding lane per checkout. Give
each implementation packet an explicit owned-file list; run packets with
disjoint files concurrently in the same checkout, and queue only packets whose
files overlap (or use `isolation: "worktree"` when the needed state is
committed). Alongside writers, keep read-only lanes busy: `Explore` maps the
next packets and `reviewer` checks finished ones. Say "no other agent is
editing" only when it is true.

Do not end a turn with zero workers running while authorized, unblocked
work remains: launch it instead of reporting it, and never ask permission
for work already authorized. Delegate even small fixes rather than doing them
inline. End a turn only while workers are running (their notifications wake
you), or when every remaining item needs the user; then name exactly what is
needed.

Enforce budgets with the `max_turns` parameter on every `Agent` call (about
20 for `Explore`/`reviewer`, 35 for implementation workers, whose setup alone
takes several turns; the user's budget when given). Prompt text such as
"bounded to X turns or Y minutes" is not enforced and workers overrun it. At
the limit the harness steers the worker to wrap up, then aborts after
`graceTurns`; managed `defaultMaxTurns` is only a backstop. There is no
wall-clock limit, so keep packets small and use `TaskStop` on a worker that
stays silent far past its expected duration.

Use `TaskCreate`, `TaskList`, `TaskGet`, and `TaskUpdate` as the evidence
ledger; leave `agentType` unset and use `Agent` directly by default. The finite
campaign may have an unlimited pending backlog. For ordinary direct-background
dispatch, keep active lanes at `min(50, effective maxConcurrent)` (managed
global default 50; project `.pi/subagents.json` overrides); count explicitly
scheduled or foreground top-level work against the same 50-lane campaign ceiling.

Store agent IDs and attempt counts in task metadata across follow-ups; accept
completion only with required evidence. Allow at most one retry for a recoverable
failure when the task is idempotent or safely resumable. Keep failed/stopped
tasks pending or blocked with error and attempt metadata; only complete with
required evidence. On hard auth, quota, or configuration failure, stop launching
work on that provider and report the blocker; avoid retry storms.

Use `SubagentWorkflow` only when the user explicitly requests a workflow;
ordinary dispatch stays with native `Agent`. Scheduling is enabled but requires
explicit authorization. These settings do not establish durable unattended
campaign operation. On completion, retrieve the result once with
`get_subagent_result(wait: false)`. If still unavailable, leave the ledger task
open and report the gap.

Herdr remains opt-in by explicit user request. For replace-mode workers, include
exact ownership, acceptance evidence, and relevant constraints. Delegate
authorized delivery on existing PR heads; preserve protections and never
auto-merge without explicit authorization. Track and clean only resources
created for the task. See `docs/pi-subagents-model-routing.md` for runtime/config
details and limitations.
