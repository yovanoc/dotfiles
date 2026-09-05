# Agent Guidelines

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

For every substantive coding task—investigation that may lead to edits, implementation, bug fixing, refactoring, migration, validation, review, or delivery—invoke the `orchestrator` agent before using task tools.
Give it a self-contained goal, repository and branch context, constraints, relevant paths, acceptance evidence, and delivery expectations.
Treat its lane as owned: inspect its evidence when it returns, but do not duplicate its work.

Handle only pure conversation directly. Use `Explore` for a bounded file, symbol, or call-site lookup. Honor an explicit user request for `implementer`, `effect-senior`, or `reviewer`; otherwise let `orchestrator` choose the worker and review route.

Route UI/UX design, visual review, and visual implementation to `ui-ux` when visual judgment is central; use the existing routes for non-visual frontend work.

Keep delegation inside Pi through `Agent` or `TaskExecute`. Visible Herdr panes are desirable for following agents and may be started by agents or the orchestrator when `HERDR_ENV=1` or visibility is useful; use only Pi agents in Herdr (`--kind pi`), never external `codex` or `claude` CLIs.
Bound fan-out by configured concurrency when set, otherwise use a small default of 4–8; avoid starting dozens or 50 agents at once.
Reuse the current Herdr workspace/session and checkout when possible; create new workspaces or worktrees only when needed for topology or isolation.

For every created pane, workspace, worktree, and any retained tab, immediately record its owner and tracked ID/path.
Use finally-style cleanup on normal completion, failure, cancellation, and max-turn shutdown; stop, close, or remove only owned resources, verify their absence via Herdr or `git worktree list`, and report intentional survivors with their owner and reason.
Propagate this policy explicitly in every orchestrator packet and downstream replace-mode task packet because replace-mode agents do not inherit `AGENTS.md`.
