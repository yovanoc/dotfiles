---
description: Periodic retrospective of the Pi agent workflow (routing, models, quota, handoffs) against the dated change ledger
argument-hint: "[since ISO date, default: last ledger entry]"
---
Run a workflow retrospective of how Pi agents worked across sessions, then propose improvements. Read-only analysis until I approve changes.

Sources, in this order:
1. `~/dotfiles/docs/pi-workflow-changes.md`: the timed ledger of workflow changes. The current period starts at ${1:-the newest applied entry's timestamp} and runs to now. The previous period is the one that ended at that timestamp; its numbers are the `Measured:` block stored in the preceding entry. If an entry is still `PENDING`, say so and ask me for its apply time.
2. `git -C ~/dotfiles log --grep '^Pi-Workflow:' --format='%h %ad %s%n%b' --date=iso` for committed changes carrying the ledger trailer.
3. Metrics: `~/dotfiles/scripts/pi-session-audit.sh --since <current period start> --json`, reading the help first. It summarizes session metadata, never prompts or arguments, and has no end bound, so never run it for the previous period: use that period's stored `Measured:` block, and mark metrics missing there as not comparable. Say what the script cannot measure; do not dump raw session logs into context.
4. Current policy: `~/.pi/agent/docs/coordinator.md` and `~/dotfiles/docs/pi-subagents-model-routing.md`.
5. Provider model guidance: re-read the official pages linked in the routing doc (Anthropic model selection and per-model prompting/effort guides; OpenAI model-selection guide and model pages). Check that every routed model ID and effort still exists and note anything new or changed. Cite pages; enable web tools if needed.
6. `~/.agents/skills/retro/SKILL.md`: apply its improvement categories (navigation, automated checks, coding standards, AGENTS.md size, tool economy, no-ops, information access) to sessions that went badly in this period.
7. One fresh `quota_status` call. Compare usage with time to reset per window. It is a snapshot, not debit per model.
8. Release watch: `@tintinweb/pi-subagents` 0.26.1 (installed and latest published) lacks `subagents:rpc:get/list` and nested/workflow lifecycle events; upstream master lists them as Unreleased (`get`, `list`, `owned-lifecycle`, `notification-pending` in the `subagents:rpc:ping` `features` list; `parentAgentId`/`workflowId` on events). Each retro: compare installed and tagged versions/changelogs, and once a release ships them, test presence via `ping.features.includes(...)` and the get/list/event shapes. Report present/absent; no upgrade, integration or automation without my approval.
   - Candidates, only if verified: `get`/`list` as a startup/late-load snapshot, and events as reactive transitions, could replace the `Symbol.for("pi-subagents:manager")` `getRecord` reads in `agent-prompt-guard.ts` (resume preflight) and `task-graph-check.ts` (liveness), the `subagents:record` transcript scraping behind `nativeEvidence` and recovery in `fast-task-dispatch.ts`, and the manual status bookkeeping in `coordinator.md`/`coordinator-execution.md`. Check that `status` covers `queued`/`running`/`settling` and `notificationPending`, and that 10-minute record retention and nested events suit each reader.
   - Not replaced: the live-only resume safeguard (`live_state_unavailable` stays when no live state is readable; saved results never prove resumability), the fast-dispatch attempt ledger and Task graph, acceptance (a native `completed` or `structuredJson` is not an accepted result), quota gates, approvals and ownership locks. A native queue is not shared capacity, and nothing here permits auto-spawn or polling; running workers still need no poll.

Method:
- Delegate the metric run and each heavy reading to bounded workers on light routes (Haiku/Luna for extraction, Sonnet medium for synthesis), following coordinator.md. Verify their numbers yourself before using them.
- Compare periods on accepted outcomes, rework, turn-limit and error rates, worker model mix versus policy, cost per coordinator and worker request, handoff/unattended behaviour, and quota pace. Report denominators. Correlation across periods is not causation; name confounders such as different workloads, model releases or fallbacks.
- Keep separate: subscription quota, Pi-local API-equivalent cost estimates, and real account billing. Never claim a billing figure the data cannot prove.
- No config edits, chezmoi apply, commits, model switches, API spending or unattended mode unless I authorize them.

Output:
1. Period comparison table with numbers and denominators.
2. Ranked findings (most severe first), each with evidence path or citation.
3. Proposed changes, each with expected effect and the metric that will judge it next time.
4. A `Measured:` block for the current period (to store under the newest entry) and a draft ledger entry for `~/dotfiles/docs/pi-workflow-changes.md` and a commit message whose last line is a `Pi-Workflow: <slug>` trailer, both for me to approve.
