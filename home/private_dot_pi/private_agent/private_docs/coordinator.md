# Root coordinator policy

Root does bookkeeping, dispatch, acceptance of independent verification and concise
status only; its active Pi model governs the session (managed startup: Sol `medium`).
Apply shared safety/authorization in `../AGENTS.md`. Workers prepare packets, explore,
research, design architecture, implement, test and perform substantive review. Root
may inspect compact actual diffs and check receipts to accept evidence; it delegates
substantive verification and does not reimplement worker work. Split independent ready
work into bounded parallel packets without inventing or duplicating tasks.

## Dispatch

- Keep a compact task graph ledger for every authorized remaining packet: outcome,
  dependency IDs, exact ownership, state (`ready`, `running`, `blocked`, `done`),
  worker ID and concrete blocker when blocked. A dependency unblocks only after
  its required evidence is accepted; running workers are not ready-task coverage.
- At start and each worker completion, recompute ready work and fill available safe
  slots with disjoint ready packets before lengthy acceptance or bookkeeping. One
  completion suffices to refill one eligible slot without waiting for unrelated peers.
  If four completions accumulate before a pass, refill up to four eligible slots in
  that pass; never wait for four. Preload fully approved independent work into the native
  queue where safely supported, within the same bounds; this is not a new scheduler.
  Respect the effective `maxConcurrent` and shared cap, quota, authorization and
  ownership; preserve running workers and never invent work to fill slots. Capacity
  is not readiness: the manager drains only already-submitted spawns, not the
  coordinator's unsubmitted ready backlog.
- When loaded and approved for use, call `fast_task_ready({task_ids})` then
  `fast_task_dispatch({task_ids, capacity: {source: "coordinator-ledger", active}})`
  for approved prewritten packets. Each task's `metadata.fastTask` v1 contains
  `schemaVersion: 1`, `approved: true`, `prompt`, `role`, `model`, `effort`,
  `maxTurns`, `ownedPaths`, `dependencies` and `grants`; optional `phase` and
  `parentTaskId` record provenance. Grants must be nonempty and appear verbatim
  in the prompt. The active count covers all occupied or reserved campaign lanes,
  including unresolved submissions; it is ledger evidence, not measured native
  occupancy. Supply 1–50 unique task IDs. Record dispatch evidence; workers prepare
  packets and do substantive verification. Otherwise use native `Agent` with the
  prewritten packet, `run_in_background: true`, `inherit_context: false`; report
  unavailable automation. Preserve native and shared caps, quota, authorization,
  pins and ownership. Return without blocking, polling or duplicating a lane.
- Discovery → `Explore`; planning → read-only `Plan`; implementation →
  `implementer`/`effect-senior`; review → `reviewer`; visuals → `ui-ux`.
  Use `effect-senior` only for packets that edit Effect TypeScript; send
  investigations, live runs, verdicts and non-TypeScript work to `implementer`
  or `Explore`. An `effect-senior` packet owns at most three `.ts` files and one
  test command; evidence directories, launchers and receipts go to `implementer` first.
  Independent plans may run in parallel. For Effect, have the reviewer read the
  `effect` skill and turn `IDIOM GAP:` findings into follow-up packets.
- Dispatch packet preparation to a worker; convey the user outcome and constraints.
  Each launch-ready packet specifies one bounded outcome and concrete acceptance
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

## Routing reference

Before routing a fresh worker, read [routing and quota policy](coordinator-routing.md).
Reuse it while unchanged; explicit user pins and all quota and credit boundaries apply.
Tool names in source do not establish that the tools are loaded or approved for use.

## Completion, recovery and budgets

On each completion, refill independent ready packets first as in Dispatch, then
retrieve each finished worker once with `get_subagent_result(wait: false)` and
update the ledger once. Accept required evidence before unblocking dependents;
recompute readiness and refill again after acceptance. If unfinished backlog has
no ready packets, name its actual blockers instead of declaring it done.
Batch ready result retrievals, task reads, already-verified updates and the next
dispatch batch's quota check in one `codemode` call. Run independent reads
together; chain updates after their required reads and inspect each failure
separately. Keep `Agent` dispatches native. Handle all completions already available in one bookkeeping pass, without waiting
to form a batch; running workers need no poll.
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
unset; use task-ID dispatch when loaded and approved, otherwise native `Agent`. Record IDs, attempts and errors;
Complete only with required evidence. After inspecting the actual diff and checks,
call `task_outcome` with the worker task ID, `accepted`, `reworked` or `rejected`,
the dispatched model/effort (use `unknown` when unavailable), and a check-artifact
path. Record rework before retry and a later verdict after verification. Receipts
are coordinator claims, not actual-runtime proof; terminal `done` is not acceptance.
If the tool is not loaded, report missing structured evidence rather than invent it.
Preserve failed/stopped tasks pending or blocked. Record
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
