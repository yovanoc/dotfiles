# Coordinator execution details

Read before non-default execution modes or provider, fallback, worker-start,
SDK/loader, budget or runtime-pool diagnostics. It extends `coordinator.md`;
the 50-lane campaign cap, turn budgets and explicit-opt-in rules still apply.

- Use `SubagentWorkflow` only when the user explicitly requests a workflow;
  ordinary dispatch stays with native `Agent`. Workflow children use their own
  CPU-based limit and enter neither runtime pool.
- Scheduling is enabled but requires explicit authorization. Scheduled fires
  bypass `maxConcurrent` and remain session-scoped; this does not validate a
  durable unattended campaign.
- New blocking foreground spawns use `maxConcurrentForeground`; default zero is
  unlimited. Foreground resumes bypass it. Ordinary root delegation is
  explicitly background, while explicitly requested workflows/tasks retain
  foreground support.
- Nested children occupy neither runtime pool and do not consume
  `maxConcurrent`; depth is bounded at 2, but runtime width is not. Count them
  with the main root's direct lanes and every coordinator in the shared 50-lane
  cap. Use only the nested budget assigned by the parent; without one, allow at
  most one concurrent child, fewer if active root lanes leave less room.
- A parent with nested children must collect each owned child's terminal result
  before it settles: the manager aborts a parent's children when it settles.
  Nested waits are allowed inside an authorized background parent, not at the
  main root. Only roles with `allowed_subagents` can spawn nested children;
  ordinary worker roles do not grant child tools.
- Use `max_turns` on each call; these settings do not establish durable
  unattended campaign operation.

## Failure and budget details

Native OpenAI usage-limit errors can arrive mid-stream without a matching HTTP
status. `subscription_sharing_usage_limit_exceeded` can concern an app cap or
plan limit, so status-based fallback is not guaranteed. Live quota responses
do not establish dashboard/account/app agreement, per-model debit, streamed
failover or effort equivalence. For installed matcher/cooldown mechanics and
quota provenance, consult `docs/model-fallback.md` and `docs/pi-quota-usage.md`
in the dotfiles checkout. A stale SDK chunk needs a full Pi process restart,
not repeated `/reload` or quota retries.

At a turn cap the harness steers "wrap up", then aborts after `graceTurns`
additional completed turns. `defaultMaxTurns` is a backstop, not a wall-clock
limit; prompt-text budgets are not enforced. Split outcomes that do not fit
rather than squeezing setup/implementation budgets.
