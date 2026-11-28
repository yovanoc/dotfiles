# Coordinator routing reference

Read before fresh worker routing; this extends `coordinator.md`.

## Model choice

This is prompt policy, not an automatic scheduler; tools, permissions and
concurrency stay unchanged. User model/effort choices override soft quota rules.
Report conflicting pins or hard blockers; do not launch known-broken routes.
Source and runtime role copies must both be unpinned. Resumes omit `model` and `thinking` to retain their
runtime. Direct `@agent` mentions bypass routing, inherit the parent model and
may use the model's default effort instead of the parent's live effort.

### Coordinator model

Routine dispatching, status and bookkeeping use `anthropic/claude-opus-5-5`
`medium` on the Anthropic subscription; its equal-tier switch counterpart is
`openai/gpt-6.2-sol` `medium`. New unpinned starts use Opus; existing sessions
and explicit choices retain their runtime. When the active coordinator pool's
most constrained window reaches Conserve (80%) and the other pool has headroom,
recommend the user switch to `openai/gpt-6.2-sol` `medium` at the next natural
break (after a handoff checkpoint), since a switch drops cache and reasoning. Never run the coordinator on
`anthropic-api/`, Fable 5.2, Astra, Haiku, Luna or Terra. Confirm actual provider/model and effort at startup. Root effort is not
a worker default: choose each worker's model and effort for its packet.
Delegate bounded work to Haiku, Sonnet, Luna or task-fit Terra rather than
inheriting the coordinator model for every worker. Compare accepted outcomes, rework and actual runtime cost, not done counts.
Choose Opus deliberately for difficult implementation, deep or high-risk review
and hard architecture decisions. Reserve Astra for rare, exceptionally polished
work or open-ended complex projects; require a rationale and a condition that
ends the expensive phase. State a
`MODEL RATIONALE:` (explicit user choice, costly hidden failure, interacting
invariants or a prior verified miss) and the condition that ends the expensive
phase; return to the routine model when that condition is met. Preserve explicit
user model pins. This policy does not switch the runtime automatically: if model
controls are unavailable, report the active model and request the routine switch
rather than claiming it happened.

### Worker model

For each fresh call:
1. Classify the task, not the role name. Check actual pins, registration, input/
   context support and runtime/auth eligibility; registration is not entitlement.
   Verify the target role's tools, not the parent's. Include a `REQUIRED TOOLS:`
   comma-separated line for tools the packet needs. The prompt guard checks explicit
   role allowlists from global and project agent files; unresolved package/built-in
   roles and wildcard selectors still require manual verification.
2. Root calls `quota_status` at most once per dispatch pass that launches fresh
   workers and reuses that snapshot for the whole pass (`{}` may reuse successful
   observations for 60 seconds from original `capturedAt`); no calls for resumes,
   retrievals, acceptance or status messages. Use `{"refresh":true}` only after a
   429 or a passed reset time. Unknown/unavailable observations are not cached, failed refresh
   never falls back to cached headroom, and local refusal is checked
   independently. A fresh user snapshot also works. Workers do not poll. Inspect each window's
   freshness, source, status and applicable scope,
   not merely provider status; use the most constrained applicable window.
3. Walk the task order below with the quota states. For relief choose an
   independent pool: Sol→Luna or Sonnet→Opus on a shared pool is not relief.
   Between equal-fit alternatives prefer observed headroom over unknown.
   Use subscription quota to the end of each window. By a subscription pool's most
   constrained short window (Anthropic five-hour): below 80% route normally, up to 8
   concurrent fresh workers per subscription model pool; at 80% to below 95%
   (Conserve) keep dispatching on the subscription with at most 3 concurrent fresh
   workers per pool, and send only the overflow to the same model on `anthropic-api/`
   while the credit pace allows, else to an independent pool; at 95% and above
   (Reserve/Full) start no fresh worker on that pool (running workers and resumes
   finish normally) and send new work to `anthropic-api/` when behind credit pace,
   else to an independent pool. Weekly guard: when the weekly window is ahead of its
   linear pace, apply the Conserve limits from 70% of the short window. After any
   observed 429 the reactive fallback handles the failed request and that pool gets no
   new fresh dispatch for 15 minutes: no retries into it and no quota calls to watch
   it. The user may set other numbers. OpenAI 429s hold only the affected route (see
   rollover below).
4. Pass exact `provider/model` as `model`, plus `thinking`. The prompt guard checks
   effective model/effort pins from resolvable role files, then call parameters,
   against registration/auth configuration and SDK-supported effort. Slash forms
   must be exact registered IDs (including case); only no-slash fuzzy names,
   omitted models and resumes bypass route checks. Unresolved package role pins
   and inherited-model effort require manual verification. Report unsupported effort and
   choose an eligible route, preserving explicit user choices; never silently
   substitute `max`. Role pins and live entitlement still need the check above.
   Briefly explain any
   non-default choice. If suitable routes are blocked or a full applicable
   window rules them out (subject to the credit-rollover exception below), leave
   work pending, report the gap and preserve running workers. Unknown quota alone does not establish broken inference.

### Classify before dispatch

Before each fresh dispatch write `CLASS: narrow | substantive | difficult` for
the packet and pick the route from the table by that class. Choose a lighter
route for bounded work even when the coordinator is Sol or Opus. Streaming a large
archive, joining session evidence or open-ended web research is substantive:
split extraction from synthesis and give the latter a suitable substantive route.

### Task priorities

Read left to right: compatible preferences, not a global quality ranking.
Classify the worker packet, not the whole project, by uncertainty, coupling and
failure cost—not file count:
- **Narrow:** any bounded packet with a deterministic acceptance check (a command
  with an expected result), not only mechanical edits; the packet names the check
  and the evidence path the worker writes, with a prompt under 4,000 characters and
  `max_turns: 20`. Security, concurrency and data-loss work stays off this route
  regardless of size. Its reviewer can be Sonnet `medium`. If the check or bounds
  are missing, re-split or use the substantive row.
- **Substantive:** behavior changes or debugging that need caller/test tracing.
- **Difficult/deep:** interacting layers or tricky state, concurrency, security
  or data-loss invariants. Choose implementation, review or architecture by
  activity; open-ended discovery uses the research/tracing row.

Lighter-first: Haiku `low` takes simple extraction, `medium` bounded mapping
or mechanical edits and `high` longer or strict-instruction leaves before Sonnet; Luna `low` takes well-scoped edits or extraction and `high`/
`xhigh` constrained multi-step work. Terra `medium` takes its task-fit rows;
Sonnet `medium` takes substantive work and synthesis, with `high` for harder
bounded packets. Opus stays available for deep review and architecture. Prefer Copilot Luna over
native OpenAI Luna for equal-fit bounded tasks when Copilot has headroom. Real
verification before acceptance stays mandatory for every route.
Packets for Haiku/Sonnet at `low`/`medium` name a real check that exercises the
change and say: keep working until the outcome is done, then stop without
unrequested additions. Packets at `xhigh`/`max` forbid launching unrequested
review subagents.
Split large repetitive work; a small risky patch can still need deep review.
Sol is an exception for genuinely difficult coupling, a prior verified lighter-route
miss, explicit user choice or no suitable eligible alternative, not a routine
fallback because root uses Sol. Every fresh explicit Sol worker dispatch carries
`MODEL RATIONALE:` naming the applicable condition and the condition ending the
expensive phase; return to a suitable lighter route when that condition is met.
Use each route's listed thinking by default: effort labels are not comparable
across models (Luna `high` is not a capability rank above Sol `medium`). Raise
within-model effort for difficulty or a diagnosed reasoning gap, not quota;
maximum is not universally better. Same-model provider alternatives preserve
task fit; Effect expertise stays with the role. API price is not subscription debit.

| Task | Ordered routes and thinking |
| --- | --- |
| Bounded read-only mapping (`Explore`) | `opencode-go/claude-haiku-5-5` `medium` → `github-copilot/gpt-6-luna` `high` → `anthropic/claude-haiku-5-5` `medium` → `openai/gpt-6-luna` `high`. Luna `max` is locally discouraged here (29 of 43 historical Explore runs hit the turn limit), not a provider rule. |
| Narrow: bounded code or analysis with a deterministic check (see Narrow above) | `opencode-go/claude-haiku-5-5` `medium` → `github-copilot/gpt-6-luna` `low` for single-step or `high` for multi-step → `anthropic/claude-haiku-5-5` `medium` → `openai/gpt-6-luna` at the same effort → `anthropic/claude-sonnet-5-5` `medium`. At a turn limit inspect partial edits and re-split. Keep Haiku prompts under 100k tokens (price steps 5× above). |
| Concise writing or revision from supplied material (not extraction) | `openai/gpt-6.1-terra` `medium` → `openai/gpt-6.2-sol` `medium`. Verify facts, qualifications, audience, voice and useful detail against the supplied material. |
| Scoped code fixes with clear inputs, requirements and regression checks, without hard/security/cross-layer invariants | `openai/gpt-6.1-terra` `medium` → `openai/gpt-6.2-sol` `medium`. A worker runs regression tests and reports the diff before acceptance. Mechanical leaves still use the narrow row. |
| Substantive implementation, debugging or bounded Effect work outside the scoped-fix row | `anthropic/claude-sonnet-5-5` `medium` → `openai/gpt-6.2-sol` `medium`. Use Sonnet `high` for harder but bounded work. A small risky packet still belongs here or on the difficult row, not Haiku. |
| Genuinely difficult end-to-end implementation | `anthropic/claude-opus-5-5` `medium` with a rationale → `openai/gpt-6.2-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. At Anthropic Conserve prefer Sol first. |
| Research, open-ended work or hard repository tracing | `anthropic/claude-sonnet-5-5` `high` for bounded synthesis → `openai/gpt-6.2-sol` `medium` for hard tracing. Split exact extraction to Haiku/Luna first. |
| Bounded planning or ordinary review | `anthropic/claude-sonnet-5-5` `medium` → `github-copilot/gpt-6-luna` `high` for self-contained checks → `openai/gpt-6.2-sol` `medium`. |
| Deep or cross-layer review | `anthropic/claude-opus-5-5` `medium` → `openai/gpt-6.2-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. At Anthropic Conserve prefer Sol first. |
| Exceptional/adversarial review with costly hidden failure, interacting invariants or verified misses | `anthropic/claude-opus-5-5` `high` → `openai/gpt-6.2-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. At Anthropic Conserve prefer Sol first. |
| Architecture where judgment is the bottleneck | `anthropic/claude-opus-5-5` `medium` → `openai/gpt-6.2-sol` `xhigh` → `anthropic/claude-sonnet-5-5` `high`. At Anthropic Conserve prefer Sol first. |
| Defined visual/computer tasks with explicit inputs and a verifiable saved outcome | `openai/gpt-6.1-terra` `medium` → `openai/gpt-6.2-sol` `medium`. Verify the saved record/page, preserve unrelated data and check the completion report; UI changes also require rendered desktop/mobile, keyboard and accessibility checks. Role tools must actually support the interaction. |
| Open-ended visual/UI design or connected visual systems | `github-copilot/gpt-6-luna` `high` → `openai/gpt-6.2-sol` `medium`. Go Kimi K3 `high` is held: the installed catalog marks it unsupported; do not substitute `max`. Verify image input and effort support; inspect screenshots, mobile layout, keyboard navigation and accessibility before acceptance. |
| Rare top-tier Claude work: hours-long orchestration or migration, deep research, or a verified Opus `high`/`xhigh` miss on the same inputs | `anthropic/claude-fable-5-2` `high` (provider start; try `medium` where checks still pass) with a `MODEL RATIONALE:` naming the trigger and the condition that ends the phase. Prefer `anthropic-api/claude-fable-5-2` when the credit pace allows. Never a routine route or automatic fallback. |
| Rare top-tier OpenAI work: a verified Sol `xhigh` miss on the same inputs, an exacting externally visible deliverable, or explicit user choice | `openai/gpt-6.2-astra` `low` for polished work, `medium` for complex projects, or `xhigh` for open-ended work, with a `MODEL RATIONALE:` and a defined exit condition. Never a routine route or automatic fallback; supported efforts exclude `none`. |
| Short extraction, summaries or classification | `opencode-go/claude-haiku-5-5` `low` for single-step or `medium` for multi-step → `github-copilot/gpt-6-luna` `low` or `high` respectively → `anthropic/claude-haiku-5-5` at the same effort → `openai/gpt-6-luna` at the same effort. |

Zen (`opencode/`) is disabled while the user declines to refill its wallet: omit it
from fresh routes and automatic fallback. Go is a different subscription.
`opencode-go/gemini-4-argon-contributor` is absent from the bundled Go catalog and
unqualified; do not substitute another ID. If separately qualified, it is a
non-confidential, explicitly selected alternative only: its prompts/completions may train Google models and it is not
zero-retention. Automatic fallback cannot enforce that boundary, so excludes it.

For Luna, try `xhigh` for constrained multi-step code; `max` needs task-local
evidence or an explicit user choice. Sol `medium` is recommended for code fixes
and features;
Sol `xhigh` suits decisions from conflicting evidence or polished hard deliverables.
Opus `medium` is the provider's starting effort; `high` is our local choice for
high-risk work (exceptional review, security, concurrency, data loss), not a proven
optimum; use `xhigh`/`max` only for explicit user choice or measured task-local
quality gains. An Opus packet (implementation, plan or review) carries one `MODEL RATIONALE:` line naming which condition applies: explicit user
choice, a difficult class from the table, costly hidden failure, interacting
invariants or a prior verified miss; without one, use the row's next route. Bigger or harder reviews belong on Opus with
the budget to finish: it averages about one tool call per turn and hit the limit
in 7 of 19 reviews at `max_turns` 16–20. Escalation within one pool is
not quota relief; a switched effort requires a fresh worker, not a resume.
Copilot Gemini is omitted here: its installed adapter ignores effort, so a
requested `medium`/`high` is not a controlled alternative to OpenCode Gemini.

Terra is user-authorized selective routing through native `openai` with the
existing ChatGPT login, not a startup change or a separate API-key route.
Use its task-fit rows before the general substantive/visual rows, while retaining
Haiku/Luna for mechanical work and extraction and stronger routes for hard,
security or cross-layer work. Check registration, account availability, tools and
`medium` support before dispatch; local registration alone is not live entitlement.
On an actual auth/availability refusal hold Terra and report it; use an eligible
next route without trying separate API credentials. On a verified acceptance miss,
record the failure and escalate a fresh packet to Sol `medium` with the same
inputs and checks, not repeated Terra retries. Compare same-effort accepted results,
rework and review/repair time; do not run duplicate comparisons without a real need.
API estimates are not ChatGPT credit-debit rates; no measured savings are claimed.
See [Terra setup and evidence](~/dotfiles/docs/pi-subagents-model-routing.md#terra-selective-routing)
for limits, native preflight and verification prerequisites.

### Quota states

These are adjustable operating policy for discretionary fresh work, not provider
limits or measured model costs. Explicit user choices still take precedence.

| Applicable usage | Dispatch behavior |
| --- | --- |
| Below 80% | Normal: use task priority. |
| 80% to below 95% | Conserve: keep dispatching on this pool with at most 3 concurrent fresh workers; overflow goes to `anthropic-api/` (Anthropic, credit pace permitting) or an independent pool. |
| 95% to below 100% | Reserve: no new fresh dispatch on this pool (running workers and resumes finish); use alternatives; spend remaining allowance only for explicit user choice or essential judgment without a suitable alternative. |
| Full window: 100% or more, or zero remaining with a known positive count limit | Hold new discretionary work on affected routes until fresh evidence or explicit user choice changes the decision. This observation is not proof of whole-provider exhaustion or failed inference. |
| Missing, stale, unavailable or unknown-scope data | Unknown: preserve task priority and report the gap. It is neither zero use nor exhaustion; known headroom may break an equal-fit tie. |

### OpenAI ChatGPT credit rollover

The user enabled ChatGPT's “Allow other apps to use credits after reaching your
usage limit” for Pi and confirmed that requests continue on credits after the
weekly allowance is exhausted. Continue authorized OpenAI work through the
existing ChatGPT login, including fresh workers, when subscription windows reach
Reserve or Full; those percentages describe the included allowance, not the
credit balance. This exception overrides the table's OpenAI quota holds and
reset-aware caps while rollover remains available. No separate API key or
API-platform balance is involved. Prefer task-fit routes normally; credit
rollover is not a reason to add work or choose a more expensive model.

Treat this user-confirmed rollover as available until revoked or contradicted by
fresh evidence. Report that beyond-allowance work spends ChatGPT credits; honor
explicit spending limits. A 100% window or missing credit telemetry alone is not
a blocker. `quota_status.codexbarCredits` reports the CodexBar web session's
remaining credit count separately from subscription usage. Check its freshness
and account/workspace agreement with Pi before treating it as this route's
balance; it is neither API dollars nor proof of app spending permission.
Hold the affected route on an actual credit/usage refusal or auth
failure, and reconcile it before retrying; never assume an unlimited balance or
purchase/reload credits automatically.

Reset-aware preference (subject to the OpenAI credit-rollover exception above,
the 80/95/100% rows stay hard caps; never invent work):
compare each pool's used fraction with the elapsed fraction of its window (linear
reference: expected used = elapsed/`windowMinutes`, from `resetsAt`), using the most
constrained known applicable window; a near-full five-hour window outranks weekly
headroom. Behind pace and near reset, prefer eligible subscription `anthropic/`
routes (Haiku/Sonnet/Opus) for real queued tasks where they fit or improve judgment;
this may relax Conserve, never Reserve or Full. Ahead of weekly pace, taper from 70%
of the short window (see step 3); otherwise use the short window to its end. Under
short-window pressure beyond the Conserve cap, move compatible routine work to independent pools (OpenAI, Copilot,
OpenCode Go when eligible). Never add padding work or extra reviews to spend quota
and never infer per-model debit. Aim for useful near-full use (roughly 95–98% by
reset) with a reserve; exactly 100% cannot be guaranteed. Use the bounded snapshot for dispatch decisions; workers never poll, and unknown stays unknown.

`anthropic-api/<model>` spends expiring prepaid credits; unspent credit is lost,
so pace it to use the grants before they expire. No monthly cap is required:
live CodexBar Console observations in `quota_status` (balance, each grant's
remaining amount and expiry, UTC month spend) are the budget evidence.
Monthly credits (the recurring Team API grant, $360 so far) are applied before
long-lived grants and expire about a month after grant. A fully consumed grant
disappears from the Console promotional list (only invoice history keeps it), so
an absent monthly grant means consumed or not yet issued; pace only on observed
grants and never assume the next amount or date.
Daily target: sort observed grants by expiry; for each expiry date, divide the
remaining credit of all grants expiring on or before it by the days left until
it (at least 1); the target is the largest of these. Expected spend so far is
the target times the elapsed UTC-month days. Behind pace (`monthSpendUsd` below
expected): send Claude-fit worker packets on the Haiku/Sonnet rows to
`anthropic-api/` before subscription routes, and all Claude-fit work there when
the Anthropic subscription is at Conserve and the pool's 3-worker cap is full, or at Reserve or above. Opus still needs its row's
`MODEL RATIONALE:`. Ahead of pace: return to subscriptions. Never add work,
reviews or heavier models to spend credit. Hold fresh API work on an exhaustion
refusal, when total balance would fall below a $20 reserve, or when Console
evidence is missing, stale or from an unverified organization: use a
subscription or ask for a fresh reading. Reactive fallback enters `anthropic-api/` only for subscription Sonnet/Haiku 401/402/429, same model; Opus goes to Sol. Such switches bypass the pace and the $20 reserve, so read Console spend at the next dispatch pass.
The optional CodexBar CLI uses the signed-in Console session; verify its first-readable
API organization before treating it as the inference-key budget. A grant with
unknown expiry is excluded from the pace target. Console balances, UTC month spend and Pi-local
API-equivalent estimates are separate sources; a local refusal is not a balance.
See `~/dotfiles/docs/pi-quota-usage.md` for session requirements and private-endpoint
limitations. Explicit session spending restrictions always take precedence.

Keep plan, app and model-scoped windows separate. A generic `Quota window`
cannot establish model headroom; generic or model-specific windows cannot
establish whole-plan exhaustion. OpenAI companion telemetry is experimental;
app usage adds no plan capacity. Copilot credits are counts, not dollars: preserve reported counts and
use percentages only with a positive known denominator. Go windows are not Zen
wallet balance; another provider route adds no Anthropic subscription allowance.
Infer neither per-model debit nor remaining-message counts.

`resetsAt` is seconds, `capturedAt` milliseconds, `windowMinutes` minutes. Resets
can move; ease pressure only after fresh evidence of replenishment, and check the bounded snapshot before further dispatch. Waiting/scheduling requires the user's request.
A missing/failed quota query or generic 402/429 is not shared-pool exhaustion.
A verified expired credential holds only its affected route until repaired; an
unexplained query failure remains unknown, not a reason to disable inference.
Separate quota/auth failures from transient/rate/loader failures; stop launches
only on routes affected by a hard failure. Reactive fallback has a separate
managed JSON order and does not allocate quota; cooldowns are not allowance.

### Opt-in virtual worker routes (prototype)

Branch `pi/virtual-worker-routing`; unmerged until the checks below pass. The
physical policy above stays the default: nothing changes unless a fresh worker
packet passes one of six aliases as `model`. Evidence is the source in
`private_extensions/worker-router.ts`, the alias handling in
`agent-prompt-guard.ts` and `task-outcome-receipt.ts`, and the offline tests
`scripts/test-worker-router.sh` and `scripts/test-worker-router-sdk.mjs`; no live
multi-worker run is recorded here.

**Before / after.** Before: the coordinator walks the task table, reads
`quota_status` and passes an exact `provider/model` plus `thinking`. After
(opt-in): it classifies the packet and passes one alias; the router chooses the
physical route when the worker's request runs. Aliases and chains mirror the
table rows (the router file notes this; edit both together):

| Alias | Chain (first eligible wins) |
| --- | --- |
| `route/explore` | OpenCode Go Haiku → Copilot Luna → Anthropic Haiku → OpenAI Luna |
| `route/narrow` | the explore chain, then Anthropic Sonnet `medium` |
| `route/writing` | Terra `medium` → Sol `medium` |
| `route/substantive` | Sonnet `medium` → Sol `medium` |
| `route/difficult`, `route/review-deep` | Opus `medium` → Sol `xhigh` → Sonnet `high` (Sol first at Anthropic Conserve) |

Efforts per entry are in `ROUTES` in the router file. No chain contains
`anthropic-api/`, Zen or Fable/Astra, so an alias never spends API credits and
never picks a rare top-tier route.

**Activate.** Per packet, not globally: set `model` to `route/<class>` for a fresh
worker only (not the coordinator, which warns on selecting `route/*`; not
resumes). Resumes keep their recorded route. Omit `thinking` or pass `off`:
an alias is an off-only selection and the router picks the physical effort per
entry (the guard rejects any other level). `route/difficult` and
`route/review-deep` still need `MODEL RATIONALE:` like Opus/Sol.

**What the guard protects.** The preflight guard (native Agent and
`fast_task_dispatch` alike) rejects unknown `route/` names, aliases that are not
registered with usable auth, unsupported thinking levels and missing rationale
for the two expensive aliases. It does not read quota and does not decide
whether the worker loads the router.

**Worker lifecycle (fail closed).** Slots are released by `worker-router`'s
`agent_settled` and `session_shutdown` hooks inside the worker session, but the
route function is shared by the whole Pi runtime. So the router only allocates,
resumes or retries for a session that runs the extension (it records that
session's run signal at `agent_start`). Any other session selecting an alias,
by any ingress, gets an error response (`does not run the worker-router
extension`) before a provider is called and takes no slot: native Agent,
`fast_task_dispatch`, `isolated: true`, `extensions: false`, an `extensions:`
allowlist or `exclude_extensions` that omits `worker-router`, and roles whose
policy cannot be resolved (package or built-in roles). The guard cannot see
these role settings, so the refusal happens at the first worker request, not at
dispatch: treat it as `no eligible route`, re-dispatch on a role that loads the
router (`reviewer.md` lists it) or on a physical route. Compaction and other
`direct` requests never lease and are not gated. A worker in a separate
process has its own store: it needs the extension to see the alias at all, and
its slots are not shared with the parent process. Pi reload in a live process
keeps the old shared store; restart Pi after changing the router.

**Attempted, observed, unknown.** Three different claims; keep them apart.
- *Attempted*: the alias in the packet. It is intent, not a model.
- *Observed*: a task-outcome receipt for a `route/*` model gets `observedModels`,
  the `provider/model` ids of the worker's successful assistant turns (stop,
  tool use or length) read from its transcript. Errored turns are not counted.
- *Unknown*: `observedModels: ["unknown"]` when the worker record, session file
  or trusted session root is missing or unreadable. Do not guess the physical
  model; do not treat the alias as the model in comparisons. Physical receipts
  are unchanged.

**Review and monitor.** Per route-using task, read the receipt's `observedModels`
next to `model`, outcome and `checkArtifact`; judge accepted outcomes, rework and
runtime as for physical routes. Watch these limits:
- *Process-local.* Caps and cooldowns live only in the current Pi process (shared
  by root and worker sessions there): a restart or a second Pi process resets them.
- *Caps.* They follow the quota states above (8, 3 at Conserve, 0 at
  Reserve/Full).
- *Unknown quota is not headroom.* A failed, missing or non-fresh quota read
  counts as `normal` (cap 8), so a quota outage makes the router more
  permissive, not less. OpenAI is never queried and is always `normal` under the
  credit rollover, so its only brake is the 8-slot cap and the cooldown below.
- *Polling latency.* Quota is read when a fresh worker is routed and reused for
  up to 60 s per provider (one read waits up to 5 s). A burst of workers can pass
  Conserve/Reserve thresholds crossed seconds earlier; slots are counted
  immediately, quota is not.
- *No route.* When nothing is eligible the dispatch fails with `no eligible
  route` and the work stays pending; report it, don't retry in a loop.

**Failures.** A retry reaches the router only if Pi core itself retries the
request (the router adds no retry of its own). On a rate-limit-like error it
cools the whole provider (every model of that pool, not just the failed one) for
15 minutes and picks a fresh route; for OpenAI that means one 429 on Sol also
removes Luna and Terra from every route for 15 minutes in this process. Hard
limits (usage, balance, 401/402) end the run and cool the provider for later
workers; other errors retry on the same model. Cooldown is a local reaction to
a refusal, not quota evidence and not a reset time. This does not replace the
manual 429 rule above or `pi-model-fallback`.

**Physical fallback.** At any time pass an exact `provider/model` and `thinking`
from the table; the router ignores those. Use it whenever you need a known
model, a role lacks the extension (the alias is then refused, see above), an
alias fails, or `observedModels` is `unknown` and attribution matters.

**Rollback.** Stop using aliases (no state change). To remove the prototype:
drop `worker-router` from the `extensions:` lines, delete the managed
`worker-router.ts`, run `chezmoi apply`, restart Pi. Receipts and transcripts
already written keep their alias names; whether a session saved on a `route/*`
model can be resumed after removal is untested, so use a fresh worker.
