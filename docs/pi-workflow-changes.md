# Pi workflow change ledger

Timed treatments and their measured baselines for `/workflow-retro`. Git cannot
replace this file: commits record source edits, not when a change reached `~/.pi`
(often days apart, sometimes uncommitted). Unbounded audit runs cannot reconstruct
a previous period, so each period's numbers must be stored here when measured. Commits that
change workflow end with a `Pi-Workflow: <slug>` trailer matching an entry, which
links the two (`git log --grep '^Pi-Workflow:'`).

Entry format: `## <applied ISO timestamp with offset> — <slug>` (the exact
`--since` value for the next audit), then what changed, why (evidence path), the
metric expected to move, the commit hash once committed, and a `Measured:` block
appended by each retro covering the period that ends at the next entry.

## 2026-10-12T16:39:08+02:00 — sonnet-startup-unattended

- Applied: coordinator startup Sonnet `medium`, `/unattended` checkpoint-and-continue,
  five-condition narrow-edit gate. Scoped apply of settings, coordinator.md and
  compaction-handoff.ts (timestamp = last target file mtime of that apply).
- Why: audit of 2026-10-11/12; coordinator share of cost was 64% and overnight work stalled at the handoff.
- Measure: coordinator cost per request, unattended continuations, accepted outcomes.
- Measured (fixed window 2026-10-12T13:35Z–2026-10-14T19:33Z):
  coordinator cost/request −45.6%, worker −16.5%; workers still 68% Sol,
  0.2% Haiku, 0 Luna. Quality parity not measured.
- Measured (`pi-session-audit.sh --since 2026-10-12T16:39:08+02:00 --until
  2026-10-14T22:37:37+02:00`, 603 files): terminal notifications done 404,
  turn_limit 75 (15.6%), error 1. Worker requests 11,306: Sol 69.5%, Sonnet 29.6%
  (of which 655 on separately billed `anthropic-api`), Opus 0.8%, Haiku 0.2%.
  Worker cost $229.72, coordinator $200.33 (Pi-local usage cost, not billing).

## 2026-10-14T22:37:37+02:00 — lighter-first-isolated-handoffs

Applied to `~/.pi` (timestamp = last target written); active only in Pi processes started or `/reload`ed after it.

- Routing: Haiku/Luna first for mapping, extraction and narrow leaves; Sonnet `medium`
  first for everyday implementation; Opus first for difficult implementation and deep
  review. Reset-aware quota pacing added. `anthropic-api` routes are opt-in only.
- Handoffs: per-session immutable files under the session directory replace the shared
  `tasks/handoff.md`.
- quota-status: helper qualified and pinned to `@narumitw/pi-usage` 0.66.0 in both
  the loader and the `settings.json` install spec.
- Why: `/tmp/pi-usage-compare/report.md`, `/tmp/pi-routing-next/*.md`.
- Measure: worker mix (Haiku+Luna share up, Sol share down), turn-limit/rework rate
  for light routes, Anthropic weekly use at reset (aim 95–98%), handoff collisions = 0.
- Measured (baseline 2026-10-14T22:37:37+02:00 → 22:42:28, about 5 minutes):
  0 agent dispatches, 0 worker sessions, 6 coordinator bash calls (all with
  timeouts), 1 turn_limit notification. Not enough data; no comparison.
  Quota at 20:42Z: Anthropic weekly 69% (linear pace ≈79%), OpenAI 25% (on pace),
  Copilot 407/1500 credits (window length unknown), OpenCode Go 2%.
- Amended 2026-10-14T22:50:24+02:00 (`retro-metrics-copilot-sol`; not a new
  measurement period, keep `--since 2026-10-14T22:37:37+02:00`): removed the
  unregistered `github-copilot/gpt-6.1-sol` fallback step from 7 coordinator routes;
  `pi-session-audit.sh` gained `--until` and per-model request/token/cost metrics
  split by worker and coordinator. Why: retro of 2026-10-14
  (`/tmp/retro-models.txt`, `/tmp/retro-current.json`). Next retro: after a few
  days of normal use, close this period with `--until`.

## 2026-10-14T23:04:57+02:00 — anthropic-api-credit-pacing

Applied to `~/.pi` (coordinator.md and model-fallback/config.json); active after `/reload` or restart.

- Routing: expiring prepaid `anthropic-api` credits ($360 by 2026-10-21, $1,000 by
  2027-04-08; console $129.04 spent on 2026-10-14) are no longer opt-in. They take
  Anthropic relief at 80%+ subscription windows and routine Anthropic packets while
  the Pi-local count is behind 57.56 + $35/day (to 2026-10-21), then + $6/day.
- Fallback: subscription Opus/Sonnet/Haiku 402/429 switch to the same model on
  `anthropic-api`; `anthropic-api` 402/429 falls back to Sol.
- Why: the user asked not to lose credits (console screenshot, 2026-10-14).
- Measure: console spend ≥ $360 by 2026-10-21; Pi-local `Prepaid credits` on pace;
  no unexpected exhaustion; worker share on `anthropic-api` (audit per-model metrics).

- Measured (`pi-session-audit.sh --since 2026-10-14T23:04:57+02:00`, run
  2026-10-20 about 10:15+02:00, no end bound; 2,845 files): 134 coordinator,
  2,701 worker sessions; terminal notifications 2,281: done 1,948 (85.4%),
  turn_limit 309 (13.5%), error 24 (1.1%). Worker assistant requests 49,003,
  Pi-local cost $1,697.51 ($0.03464/request); coordinator 29,822,
  $1,369.47 ($0.04592/request). Worker mix: Opus 32.7%, Sonnet 32.3%,
  Sol 26.8%, Haiku 4.0%, Luna 3.1%, Gemini 1.0%; anthropic-api 14,151
  requests, $619.61. Coordinator Sol 27,144/29,822 (91.0%): user deliberately
  selected Sol to use frequent subscription resets, not an unexplained routing
  failure. Fresh/resumed dispatches 2,571/887 of 3,458.
  Not measured: accepted outcomes, rework, quality or per-model turn-limit rates.
  Previous entry stores only a five-minute baseline, so no comparable prior
  period; the 10-12→10-14 baseline is a historical reference, not a control.
  Earlier Console screenshot transcription is superseded: its grant dates were
  misread. The user confirmed the monthly $360 was consumed; the later live
  Console read reported only the remaining long-lived grant. No historical
  grant constants are used for routing or balance calculations.
  This does not prove which previous grants paid the monthly spend. Pi-local
  cumulative ledger $509.97 starts Oct 10 and is not a comparable billing window
  or balance. Its discrepancy with session estimates needs reconciliation;
  neither identifies real account charges or exact missing-request percentage.
  Quota snapshot 10:18+02:00: Anthropic weekly 92%, five-hour 15%; OpenAI 5%;
  Copilot 650/1500; Go monthly 12%; Zen inference 402 (no wallet top-up planned).
  Supplemental whole-file event counts from this retro are withdrawn as period
  metrics: they filtered file mtime but included events before --since. In
  particular, 551 compactions/297 checkpoints and the apparent handoff violations
  are not evidence for this period. Use the enhanced time-filtered audit next.
  Evidence: `/tmp/pi-retro-2026-10-20/current.json`, session-retro transcript and
  user-provided Console screenshot; temporary files are not durable archives.

- Measured (`pi-session-audit.sh --since 2026-10-14T23:04:57+02:00 --json`;
  scan 2026-10-27T06:24:47Z–06:28:44Z, no explicit end bound):
  6,615 candidates; 6,466 session files; 139 non-session files;
  10 candidates unexplained by these categories; 54 malformed/skipped
  lines; 0 unreadable files. Sessions with activity: 402 coordinators,
  6,064 workers.
  Terminal notifications 4,269: done 3,546 (83.1%), turn_limit 679
  (15.9%), error 44 (1.0%). These are notifications, not accepted outcomes.
  Worker assistant requests 115,578, Pi-local estimated cost $3,245.40
  ($0.02808/request); coordinator requests 65,503, $2,337.67
  ($0.03569/request). Not billing or subscription debit.
  Worker request mix: Sol 49,652 (42.96%), Sonnet 32,777 (28.36%),
  Opus 20,986 (18.16%), Haiku 5,113 (4.42%), Luna 6,502 (5.63%);
  Haiku+Luna 11,615 (10.05%). Coordinator Sol 61,836/65,503 (94.40%);
  deliberate user choices cannot be classified as routing failures.
  Direct Agent dispatches 6,262: fresh 4,683, resumed 1,579.
  Assistant stop-error events 569: 566 unclassified, 3 api_key_expired.
  These differ from terminal error notifications.
  Time-filtered compactions 691. Coordinator checkpoint attempts 283
  across 64 files: continue 209, blocked 62, done 12. Worker checkpoint
  attempts 3 across 3 files. Handoff entries: unattended custom 3,319;
  compaction custom 276, custom_message 277. Attempts and notices do not
  prove successful continuation or saved checkpoints.
  Retrieval misses 29/2,849 results, all unique.
  Accepted outcomes, rework, per-model turn-limit rates and handoff
  continuity are unavailable. Previous stored baseline covers only
  about five minutes and is not a useful control. October 20 values
  are an overlapping interim observation, not a previous period.
  Treatment timing remains ambiguous: credit-anchor-provider-health
  is PENDING despite commit b150ed1 and matching current coordinator
  source/runtime files; application time is not established. The user
  confirmed keeping this entry's timestamp as the audit start.
  Original evidence: `/tmp/pi-retro-20261027.Gppe91/current.json`.
  Temporary evidence is not a durable archive; the verified aggregate
  baseline is preserved here. Different workloads, model releases,
  user choices and fallbacks confound causal comparisons.

## PENDING — credit-anchor-provider-health

Application time unverified as of the October 27 retrospective. Commit `b150ed1`
(2026-10-21) carries the trailer, and current coordinator source/runtime files
match, but neither proves the full treatment's apply time. Keep PENDING until
the user supplies that time or a new scoped apply establishes a known boundary;
source edits and commits are not application.

- Coordinator: Sol medium, respecting user subscription choices. Workers:
  Go Haiku and Copilot Luna for bounded leaves, Sonnet for substantive work;
  Sol before Opus for difficult implementation and under Anthropic pressure.
- UI/UX: Go Kimi K3 trial first, then Copilot Luna/native Sol. Zen is unfunded
  and excluded. Contributor routes require explicit non-confidential selection,
  never automatic fallback. No automatic fallback into budgeted anthropic-api.
- API credits: remove the daily burn formula; monthly grants recur. Read official
  balances, grants, expiry and UTC month spend through the optional CodexBar
  Console-session route, with no Admin key or static balance anchor. Keep
  Pi-local refusal evidence separate; verify the Console organization. Hold API relief on
  uncertain budget evidence, at 90% of the monthly cap or below the reserve line.
- Handoff and audit: enforce interactive handoff thresholds while preserving
  authorized unattended checkpointing; add time-filtered event metadata and
  provider health categories, with offline privacy/regression fixtures.
- Why: retro of 2026-10-20 and user corrections to grant recurrence and deliberate
  Sol selection. Earlier whole-file event-count inferences were withdrawn above.
- Measure: accepted results/rework where explicit evidence exists; lighter-worker
  mix and Copilot share; worker cost/request; auth-lost launches; time-filtered
  compaction/checkpoint counts; no monthly-cap lockout; cost/source reconciliation.
- Commit: `b150ed1` (`Pi-Workflow: credit-anchor-provider-health`).

## 2026-10-27T09:24:57+01:00 — outcome-evidence-route-preflight

Applied to `~/.pi` with explicit user approval (timestamp = last target written):
`docs/coordinator.md`, `extensions/agent-prompt-guard.ts` and
`extensions/task-outcome-receipt.ts`; all three targets verified against source.
Active only in Pi processes started or `/reload`ed after this write. No reload,
model change or Terra trial was performed; unrelated runtime drift was preserved.
Audit scripts remain repository-only and run from this task branch until merged.

- Record coordinator-reported model/effort, verification-artifact paths and
  accepted/reworked/rejected receipts (latest verdict per task, rework history).
  Join terminal tasks to requested routes and unique single-model worker sessions
  separately; actual runtime effort remains unknown, not receipt-proven.
- Extend privacy-safe error classification and reconcile scan coverage.
- Preflight explicit registered/auth-configured routes and SDK-supported effort.
  Check REQUIRED TOOLS against resolvable explicit target-role allowlists, with
  manual verification for unresolved package/built-in roles and wildcard selectors; hold the
  unsupported Kimi K3 high route rather than silently selecting max.
- Distinguish checkpoint attempts, successful receipts and useful continuations.
- Gate a future GPT-6.1 Terra medium trial on catalog/account availability and
  verified task results; preserve coordinator defaults and spending restrictions.
- Why: the October 27 baseline above records 679/4,269 turn-limit notifications,
  unavailable acceptance/rework metrics, 566/569 unclassified stop errors,
  and tool/effort qualification gaps.
- Measure: receipt coverage; acceptance/rework and cost per accepted task;
  classified-error coverage; zero unexplained scan candidates; unsupported
  dispatches; verified continuation rate; Terra trial results if separately run.
- Commit: this entry is committed with `Pi-Workflow: outcome-evidence-route-preflight`.
