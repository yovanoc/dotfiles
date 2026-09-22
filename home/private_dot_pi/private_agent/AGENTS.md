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

The default root session is `openai-codex/gpt-6-astra` at medium. It owns the goal, architecture, decomposition, integration, and final verification directly. Keep work at the root when delegation would not repay its startup and context cost.

Delegate through Pi `Agent` when a bounded lane’s benefit outweighs its startup and context cost—for example, independent workstreams, specialized implementation, or fresh review. Use `TaskExecute` only for an existing compatible task with `agentType`; otherwise use `Agent` directly. A delegation decision is complete only after the required lane is actually spawned. Spawn it before doing equivalent investigation or edits yourself, assign disjoint path or subsystem ownership, use a bounded handoff, and record failures rather than silently duplicating or dropping the lane.

Do not route the default Astra root through the Astra-backed `orchestrator`; avoid redundant Astra hops. Use the explicit `orchestrator` agent only as the full-coordination entry point for a non-Astra root or session. Route ordinary implementation to `implementer`, Effect work to `effect-senior`, bounded read-only repository mapping to `Explore`, fresh independent review to `reviewer`, and visually central UI/UX work to `ui-ux`; use `implementer` for non-visual frontend work.

The explicit `orchestrator` coordinates, delegates, verifies, and communicates; route edits to `implementer` or the relevant writer specialist. If the orchestrator is denied a write, delegate to an authorized writer; if a writer is denied, report the permission blocker rather than retrying through another tool or role. This does not impose a blanket no-edit rule on the default Astra root, which may edit when it owns the task.

Keep delegation inside Pi. `SubagentWorkflow` is available, but run it only when the user explicitly requests a workflow in the current task; no additional project opt-in is required. Visible Herdr panes are desirable for following agents and may be started by agents or the orchestrator when `HERDR_ENV=1` or visibility is useful; use only Pi agents in Herdr (`--kind pi`), never external `codex` or `claude` CLIs.
Bound every delegated packet with the repository and branch context, owned paths or read-only scope, constraints, interfaces, acceptance evidence, resource policy, and delivery expectations. Treat its lane as owned: inspect its evidence when it returns, but do not duplicate active work. Honor an explicit user role request unless it conflicts with required safety or capability.

For the default Astra root, spawn independent lanes together before waiting, request compact evidence handoffs, collect every required child before final synthesis, record failed lanes and any direct fallback, resolve findings, and verify the final diff and checks. Report `partial` if required work remains unresolved or a required child remains running.

For every created pane, workspace, worktree, and any retained tab, immediately record its owner and tracked ID/path.
Use finally-style cleanup on normal completion, failure, cancellation, and max-turn shutdown; stop, close, or remove only owned resources, verify their absence via Herdr or `git worktree list`, and report intentional survivors with their owner and reason.
Propagate this policy explicitly in every orchestrator packet and downstream replace-mode task packet because replace-mode agents do not inherit `AGENTS.md`.
