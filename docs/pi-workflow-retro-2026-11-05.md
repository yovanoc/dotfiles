# Pi control-plane retrospective — 2026-11-05

## Evidence and scope

The current audit starts at the 2026-11-04T20:40:54.521288Z disk-apply boundary; its unbounded, non-atomic scan ran 2026-11-05T15:20:21Z–15:20:57Z. The [ledger](pi-workflow-changes.md) preserves the aggregate and prior measured blocks. Its prior closing snapshot has a different start and population; no prior-period audit was rerun and no controlled comparison or throughput improvement is proven. Existing sessions were not reloaded. Four policy receipts (two startup, two reload) record hashes, not executed bytes or policy consumption; loaded-version activation remains unproven. Workload, model selection, user choices, overlapping work and scan timing confound comparisons. New-tool causation is unproven.

Worker estimated cost/request was $0.017025 (6,842 requests, $116.48525823); coordinator estimated cost/request was $0.042564 (2,667 requests, $113.5186148). These are Pi-local estimates, not billing or debit.

Private aggregate `/tmp/pi-audit-BepG2B/aggregate.json`, arithmetic review `/tmp/pi-retro-verified.md`, and synthesis `/tmp/pi-retro-synthesis.md` are temporary, not durable archives. Only aggregate counts are reproduced here; raw session text remains private.

## Findings

- Two separately examined roots, B and A, use the window since 2026-11-03T15:21:06Z; they are not additive. Notification-to-next-Agent-call p50/p90: B 214/847s (n=367), A 311/949s (n=123). These intervals include periods without ready work and are not measured waste. Retrieval-to-next-Agent-call is a different population and metric: B 172/535s (n=152), A 328/941s (n=107). Ready-work statements were observed, but the full ready backlog is not reconstructible.
- Resume returned “Agent not found” for 26/941 Agent results in B and 11/151 in A. Installed subagent source uses an in-memory resume lookup and removes completed records on a timer after ten minutes; observed ages strongly support cleanup as a contributor, but expiry, restart and wrong IDs cannot be distinguished for every miss. `get_subagent_result` has a saved-record fallback. The aggregate has 194 direct retrieval results including 2 misses; 201 nested typed calls are a separate scope.
- Aggregate nested bookkeeping calls include 1,458 TaskGet, 1,215 TaskUpdate and 227 TaskCreate; recorded call durations do not measure all coordinator thinking time. In B, 56/1,316 coordinator messages exceeded 300s; root-level observations do not establish a system-wide rate. Neither root called fast_task_ready/dispatch in the examined window; absence does not prove tool availability or cause delay.
- Audit labels 230 raw notifications versus 229 normalized; deduplication is a possible explanation, not established data loss. Checkpoint attempts, successful writes and temporally linked continuations have different denominators; the ledger records each. The `+00:59` audit label is a formatting artifact; filtering used epoch time.

## Approved next treatment

The [ledger](pi-workflow-changes.md) records **APPLIED 2026-11-05 — control-plane-dispatch-recovery**: dispatch-oriented coordinator turns, fresh handoffs when live resumes are unavailable, and distinct audit metrics for notification latency, retrieval latency, resume misses and reasoning share. Reconciliation belongs in a worker packet. This is a disk-only apply; existing sessions were not reloaded, and activation or improvement is not established. Next measurement should retain notification/task and checkpoint denominators, capture versioned activation evidence, and assess accepted/reworked outcomes as reported claims rather than runtime proof.

## Quota and official references

The available snapshot is older than this audit (2026-11-04T18:35Z), not a current budget or authorization: Anthropic weekly 99%; OpenAI experimental companion plan/app 25% each, not additive; Copilot 1,429 used / 70 remaining / 1,500 limit (one-count mismatch); Go monthly 72%. Console total $788.03, grant remaining $788.02; account agreement with Pi unverified. CodexBar credits are counts, not dollars; Zen balance unknown. Source: `/tmp/pi-retro-quota-20261104.txt`. No quota was queried for this report.

Official guidance: [OpenAI model selection](https://developers.openai.com/api/docs/guides/model-selection), [Anthropic model selection](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model), and [Anthropic effort](https://platform.claude.com/docs/en/build-with-claude/effort). These are general guidance, not proof of local route availability or permission to spend.
