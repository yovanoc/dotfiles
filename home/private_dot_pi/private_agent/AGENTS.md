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

## Root coordinator

Before dispatching or managing delegates, the root coordinator reads
`docs/coordinator.md` relative to this `AGENTS.md`. Workers apply the shared
policy here and execute their assigned packet; they do not run coordinator
loops.

## Shared safety and ownership

Standing authorization: local, reversible work inside the task's scope never
needs a question. That covers reads, diagnostics, builds, tests and full
suites, bounded read-only probes, edits to owned files, and creating
worktrees, branches, or temporary files. Ask only for actions that are
destructive, irreversible, or externally visible (push, merge, deploy, publish,
sending messages, spending money, production data, secrets), unless the user
has already granted them. Never ask again for work already authorized; pass
relevant grants to workers in their packets.

Herdr remains opt-in by explicit user request. For replace-mode workers, include
exact ownership, acceptance evidence, and relevant constraints. Delegate
authorized delivery on existing PR heads; preserve protections and never
auto-merge without explicit authorization. Track and clean only resources
created for the task.
