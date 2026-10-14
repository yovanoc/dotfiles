# Pi workflow change ledger

Timed treatments and their measured baselines for `/workflow-retro`. Git cannot
replace this file: commits record source edits, not when a change reached `~/.pi`
(often days apart, sometimes uncommitted), and `pi-session-audit.sh` has no end
bound, so each period's numbers must be stored here when measured. Commits that
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
