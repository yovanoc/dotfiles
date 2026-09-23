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
Don't block, poll, or duplicate a worker's owned lane. Omit per-call `max_turns`
unless the user sets a budget. Route discovery to `Explore`, implementation to
`implementer` or `effect-senior`, review to `reviewer`, and visual work to `ui-ux`.

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
