# Subscription-aware Pi model routing research

Research snapshot: **2026-10-07 UTC**. Public pages and embedded benchmark data
were checked on that date; the independent coding table was retrieved at
**20:33:22 UTC**. This is a research recommendation, not an applied routing
change, quota audit, or live Pi evaluation. The user's plans are GPT Pro
**$200/month** and Anthropic Team Premium **$80/month**; those fixed subscription
prices are not API budgets.

## Findings

- **Effort is not monotonically better.** Independent Codex results put Sol
  medium above high, and xhigh above max, at lower cost and latency. Anthropic's
  FrontierCode chart puts Sonnet xhigh above max and Opus medium approximately
  level with max. These are observations in particular harnesses, not proof
  that medium is best for every role. [AA], [AA-method], [Sonnet], [Opus]
- **Luna max is inexpensive, not necessarily fast or reliable.** In the
  independent coding suite it costs $0.176/attempt but averages 21.43 minutes,
  versus Sol medium's $0.705 and 10.86 minutes. Its repository-Q&A pass rate is
  44.35%, versus Sol medium's 60.75%; terminal tasks are a larger weakness.
  Narrow, checkable work is a better fit than universal implementation or
  exploration. [AA]
- **Haiku 5.5 is now registered after the catalog refresh.** The initial
  availability observation was superseded by the user's refreshed catalog and
  a root recheck: `anthropic`, `opencode`, and `opencode-go` all list
  `claude-haiku-5-5` with 1M context and 128k output. Installed provider factories
  support low/medium and adaptive thinking on all three routes. No custom
  registration is needed; no live inference was run for this recheck. Benchmark
  results remain the original research snapshot. [Haiku], [Haiku-doc]
- **Measure subscription allowance, not API dollars, when changing pins.**
  Public token/task costs are useful efficiency evidence, but no retrieved
  source supplies a complete per-model/per-effort conversion to these users'
  included Pi subscription allowance. OpenAI explicitly separates credit
  prices from included subscription consumption. [Codex-pricing]

## Pre-change baseline and availability

This snapshot records the managed defaults before role model/thinking pins
were removed. Subsequent source changes are described in
[the routing guide](pi-subagents-model-routing.md); operational choices now
live in the coordinator. OpenAI rows below record the legacy route before
migration; model IDs omit its obsolete provider prefix. Runtime files were not
changed for this research.

| Lane | Pre-change model / effort, reported by root |
| --- | --- |
| Main/default | `gpt-6.1-sol`, high |
| Explore / implementer | `gpt-6-luna`, max |
| Effect specialist | `gpt-6.1-sol`, medium |
| Plan / reviewer | `anthropic/claude-sonnet-5-5`, medium |
| UI/UX | `opencode/gemini-3.8-flash`, medium |

| Snapshot model / provider | Published controls and limits | Local availability boundary |
| --- | --- | --- |
| `gpt-6.1-sol` | API effort: low, medium (default), high, xhigh, max; no none/minimal. Public API: 1,050,000 context, 128,000 output. [Sol-doc] | Available; root reports **272k** advertised Codex context. API 1.05M is not evidence of a 1.05M Pi Codex limit. |
| `gpt-6-luna` | API effort: none, low, medium (default), high, xhigh, max. Same public API context/output limits. [Luna-doc] | Available; root reports **272k** Codex context, per-model max default. |
| `anthropic/claude-haiku-5-5` | Official API ID `claude-haiku-5-5`, released October 7; low/medium/high/xhigh/max, medium default; 1M context, 128k output. [Haiku-doc], [Claude-effort] | **Registered after refresh**, also as `opencode/claude-haiku-5-5` and `opencode-go/claude-haiku-5-5`. Root checked low/medium support and adaptive-thinking metadata; live protocol behavior remains unmeasured here. Haiku 4.5 is not a substitute benchmark row. |
| `anthropic/claude-sonnet-5-5` | low/medium/high/xhigh/max; API default high, Claude app/Code default medium; 1M context, 128k output. [Sonnet], [Claude-effort], [Haiku-doc] | Pre-change Plan/reviewer pin; the coordinator now supplies task-specific effort. Actual adapter limits/effort mapping require local qualification, not inference from vendor defaults. |
| `anthropic/claude-opus-5-5` | low/medium/high/xhigh/max; medium default, adaptive thinking always on; 1M context, 128k output. [Claude-effort], [Haiku-doc] | Existing fallback route, not evidence of extra independent Anthropic allowance. |
| `opencode/gemini-3.8-flash`, `github-copilot/gemini-3.8-flash` | Google API low/medium/high, medium default; minimal unsupported; 1M context, 64k output. [Gemini-thinking], [Gemini-card] | Root confirms both routes registered and Gemini 1M advertised. No evidence that both providers account for usage identically. |

These are the requested current names, not aliases for older GPT, Claude, or
Gemini generations. Pi thinking labels, vendor API parameters, Codex UI Power
presets, and cross-vendor “medium” are not automatically equivalent. OpenAI's
**Ultra** is a subagent mode, not single-model max effort. [Codex-models]

A Gemini conversation exceeding 272k cannot safely move unchanged to the
Codex fallback. Condense or start a bounded handoff before switching; preserving
critical instructions, code locations, and check evidence matters more than
advertising the largest context window.

## Independent measured coding cost and effort

### Artificial Analysis Coding Agent Index v1.5

Source: the [coding-agent leaderboard][AA], its [methodology][AA-method], and
public embedded row data in that same leaderboard's HTML. Values below come
from the data, not a generated search answer or pixels estimated from a chart.

**Task regime and scoring:** DeepSWE v1.1 (113 long-horizon repository changes),
Terminal-Bench 4.0 (66 terminal tasks), SWE-Atlas-QnA (124 repository questions),
three attempts/task, 303 tasks total. Each task's attempts are averaged as
pass@1; the Index equally weights the three benchmarks. DeepSWE blocks internet
except required model endpoints and verifies patches separately. Repository
Q&A must satisfy every rubric item and must not alter tracked files; it uses
Opus 4.5 as judge. Timeouts and safety-blocked tasks score zero. Terminal-Bench
reward hacking is checked and flagged successes become zero. [AA-method]

**Harnesses:** Codex **0.154.0** for Sol/Luna; Claude Code **2.1.280** for
Sonnet/Opus and **2.1.289** for Haiku. Gemini uses Antigravity SDK **0.1.16** for
DeepSWE/TB4 and **0.1.12** for Q&A (the display label says v0.1.12). These are
**agent variants**, not model-only comparisons, and none is Pi. Some vendor
safety interventions recover via other models; these rows cannot establish
pure base-model capability. Sonnet/Haiku embedded host labels include EAP
identifiers; the table uses AA's explicit display/model-release labels, not an
invented mapping to another model. [AA]

**Context and budgets:** the retrieved rows identify effort, agent versions,
and dataset references, but not a complete per-request context/output cap,
prompt, or per-task time-budget manifest. Methodology follows benchmark task
time limits. Do not infer that these runs used the maximum advertised model
context. Total trajectory input tokens can far exceed one request's context.

**Cost/latency:** average pay-per-token API cost per attempt, with cached input
and cache writes accounted for where applicable; not subscription debit and
not infrastructure/supervision cost. Missing telemetry is excluded, not
zero-filled. Time is average **agent wall time**, not output tokens/second or
TTFT. Dollar values are rounded to three decimals, percentages to two.

| Model / effort | Index % | DeepSWE % | Q&A % | TB4 % | API $/attempt | Agent minutes/attempt | Derived $/pooled success* |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sol low | 57.22 | 67.55 | 55.11 | 48.99 | 0.499 | 8.63 | 0.854 |
| Sol medium | 61.41 | 71.98 | 60.75 | 51.52 | 0.705 | 10.86 | 1.120 |
| **Sol high (current root)** | **60.15** | **70.50** | **59.95** | **50.00** | **0.889** | **13.33** | **1.441** |
| Sol xhigh | 62.91 | 73.16 | 61.02 | 54.55 | 1.040 | 15.52 | 1.621 |
| Sol max | 60.15 | 69.62 | 57.80 | 53.03 | 1.554 | 24.38 | 2.541 |
| **Luna max (Explore/implementer)** | **41.07** | **63.72** | **44.35** | **15.15** | **0.176** | **21.43** | **0.389** |
| Sonnet low | 42.06 | 61.95 | 38.98 | 25.25 | 0.483 | 6.35 | 1.084 |
| **Sonnet medium (Plan/reviewer)** | **45.88** | **65.49** | **44.89** | **27.27** | **0.619** | **8.51** | **1.270** |
| Sonnet high | 55.01 | 66.67 | 56.45 | 41.92 | 1.235 | 12.25 | 2.164 |
| Sonnet xhigh | 62.87 | 68.44 | 62.10 | 58.08 | 3.333 | 26.98 | 5.242 |
| Sonnet max | 68.36 | 71.98 | 66.94 | 66.16 | 14.191 | 87.42 | 20.672 |
| Opus max | 65.99 | 68.44 | 66.40 | 63.13 | 13.036 | 64.45 | 19.619 |
| Haiku low | 28.18 | 45.43 | 33.06 | 6.06 | 0.143 | 11.56 | 0.451 |
| Haiku medium | 33.59 | 47.49 | 41.67 | 11.62 | 0.226 | 13.96 | 0.607 |
| Haiku high | 35.06 | 46.31 | 46.24 | 12.63 | 0.365 | 18.45 | 0.936 |
| Haiku xhigh | 41.44 | 48.97 | 51.61 | 23.74 | 0.610 | 25.88 | 1.370 |
| Haiku max | 36.47 | 46.02 | 33.60 | 29.80 | 2.580 | 87.10 | 6.899 |
| Gemini Flash high | 41.86 | 65.78 | 45.16 | 14.65 | 2.467 | 11.71 | 5.340 |

\* Analyst-derived normalization, **not a published AA metric**:
`p_pool = (113*p_DeepSWE + 124*p_Q&A + 66*p_TB4) / 303`, then
`mean_cost / p_pool`. The equally weighted Index is **not** the denominator.
This is an aggregate inference-cost proxy under the benchmark task mixture,
assuming excluded cost telemetry is representative. It is not the cost of
retrying one stubborn task until success: repeated failures are correlated,
and checks, review, repair, and human intervention cost extra. No success
probability can be inferred from an Elo score.

**What this frontier actually supports:**

- Sol medium dominates high on observed score/cost/time here; xhigh dominates
  max. No reported uncertainty interval establishes that small score gaps are
  statistically significant, so use these as trial candidates, not guaranteed
  universal orderings. The pre-change Effect medium baseline has relevant support.
- Luna max remains much cheaper per pooled success than Sol medium, despite
  lower success. However, it is slower per attempt and much weaker on hard
  terminal work. Choosing it solely because its tokens are cheap misses both
  latency and reliability. Its average output is about **98k tokens**, versus
  Sol medium **22k** and high **29k** in these trajectories. [AA]
- Sonnet medium is quick, but hard repository/terminal reasoning improves at
  high/xhigh. That makes blanket medium inappropriate for deep review/planning.
  The max row buys the highest observed Index here at a very large time/cost
  premium; it is not a default-effort recommendation.
- Haiku's xhigh improves Q&A, but max drops overall accuracy while quadrupling
  cost and tripling runtime. Low/medium make sense for short, verified leaves,
  not for autonomous hard implementation. “Fastest model” does not mean fastest
  completed difficult coding task.
- **Missing independent effort sweeps:** only Luna **max**, Gemini **high**, and
  Opus **max** agent rows were recovered for those models. Their lower/higher
  effort coding frontiers cannot be filled with vendor guidance or older-model
  rows. Sol high/max and all five Sonnet/Haiku levels do have recovered evidence.

Reproduction/inspection handles in [AA]: decode `self.__next_f.push` string
payloads, then inspect variant objects with `displayLabel`, `indexScore`,
`evals[].mean.reward`, `mean.costUsd`, `mean.agentWallTimeSec`, and `versions`.
The extracted Index was checked against the arithmetic mean of its three
component pass rates. Key row IDs: Sol high
`4aee8aa2d4a0bad6068644f40edae235`; Sol medium
`93acd59f31f8e5478686d650aa650f79`; Sol xhigh
`ed8c1d0b0a2fe4560bbfa0a9f47e8941`; Luna max
`ac8276cd5d15ac2daacb9956ad44c132`; Sonnet medium
`4d6aa9e9c8df931d54dba5956d94973c`; Haiku medium
`430db5363624407d35b63d80ec863ab6`; Gemini high
`d1003684d8f29b95a3b14d2a7722221a`. The dated numbers are a snapshot, not
an assumption that a mutable leaderboard will retain the same values.

### Do not mix AA's two cost metrics

The Sol release article reports **$0.72 at max per Intelligence Index task**.
That is not its coding-agent cost: the current Codex max row above is **$1.554**.
The Intelligence Index v4.3.2 mixes ten evaluations; TB4 is just 10% of that
Index. Its TB4 harness is **mini-swe-agent**, full 66 tasks, three repeats,
500 agent steps, task-defined timeouts/resources. Coding Agent Index v1.5 uses
the named agents above and a different task mixture. [AA-Sol], [AA-intel]

Search answers initially presented $0.32/$0.72 as coding-task costs and gave
TB4 scores different from the recovered coding-agent rows. Those answers were
**not accepted as data**. Likewise, the Sonnet launch's “Haiku in coming weeks”
is superseded by the October 7 Haiku launch. [Haiku], [Sonnet]

## Vendor-reported effort frontiers

These numbers were recovered from the official launch pages' chart point
`aria-label` values, including hidden chart tabs, not estimated from axis
positions. They are distinct from the independent table. Costs can differ
between official pages even for matching scores; retain the source/date rather
than silently merging them.

### Terminal-Bench 4.0: Anthropic's chart settings

Each cell is **score % / API $ per attempt**. Haiku and Sonnet use the October 7
[Haiku launch chart][Haiku], with Sonnet's **$0.10/MTok cache-read** prices.
Opus uses its [launch chart][Opus]. Anthropic describes its TB4 comparison setup
against the public leaderboard's **Claude Code, five trials/task**; the Opus
launch reports best xhigh score 66.4% with **±2.6-point standard error** and
production safeguards enabled, including fallback models. Complete prompt,
context caps, and per-model chart-run manifests were not recovered; this is
not proof that all cross-page points share identical execution settings.

| Effort | Haiku 5.5 | Sonnet 5.5, updated cache price | Opus 5.5 |
| --- | ---: | ---: | ---: |
| low | 12.7 / $0.42 | 20.0 / $0.62 | 38.5 / $1.29 |
| medium | 20.3 / $0.68 | 28.8 / $0.68 | 57.6 / $2.94 |
| high | 24.8 / $1.04 | 43.0 / $1.46 | 64.2 / $3.88 |
| xhigh | 31.5 / $1.75 | 61.5 / $4.34 | 66.4 / $7.35 |
| max | 39.2 / $2.64 | 70.6 / $10.44 | 64.8 / $11.24 |

For binary TB4 completion, a simple analyst-derived `cost / pass_rate` gives
Haiku medium **$3.35** versus Sonnet medium **$2.36**; cheap Haiku tokens do
not win every success-adjusted task comparison. Opus high is **$6.04**, xhigh
**$11.07**, max **$17.35**. These are workload averages, not guarantees about
retrying a specific task or subscription allowance. Opus max's lower observed
score than xhigh again argues against automatically maximizing effort.

### FrontierCode 1.1 Main: mergeability, not only passing tests

Cognition's methodology revision was published **2026-07-07**. Main has the
100 hardest tasks out of Extended's 150. Maintainer-defined grading covers
correctness, test quality, scope, style, and repository conventions; internet
use for docs is allowed, solution-bearing retrieval is zeroed. Some grading
is rubric/partial-credit based, so **do not interpret these percentages as
binary retry-success probabilities**. [Frontier-method], [Frontier-board]

Anthropic's [Sonnet launch chart][Sonnet] publishes this sweep:

| Effort | Sonnet 5.5 score / $ per task | Opus 5.5 score / $ per task |
| --- | ---: | ---: |
| low | 29.3% / $0.19 | 47.3% / $0.40 |
| medium | 36.5% / $0.24 | 54.6% / $0.80 |
| high | 49.4% / $0.42 | 54.0% / $1.09 |
| xhigh | 52.1% / $1.59 | 51.4% / $2.25 |
| max | 46.2% / $20.78 | 54.4% / $6.19 |

Sonnet high gains substantially over medium; xhigh adds a smaller gain at
nearly four times the cost. Max is worse and much costlier in this regime.
Opus medium and max are approximately level, with almost eightfold cost
separation. This supports **selective Opus medium escalation**, not reserving
Opus only for max runs. It does not establish superiority over Sol **6.1**:
the Sonnet page's OpenAI comparator is GPT-6 Sol, not GPT-6.1 Sol.

The October 7 Haiku launch reports Haiku **46.4%**, Luna **42.4%**, Sonnet
**52.1% xhigh** on FrontierCode Main. Full Haiku/Luna effort and cost rows were
not recovered there. These remain vendor-reported headline results, not an
independent effort-matched rank. Cognition's public changelog confirms Sol 6.1
was added September 29, but readable extraction did not expose its numeric
leaderboard rows; no FrontierCode Sol 6.1 numbers are invented here.

### Gemini 3.8 Flash

Google's model card and launch are dated **2026-09-02**. It reports **73.7%
DeepSWE v1.1**, self-computed using **mini-swe-agent at high thinking**, and
**89.4% Terminal-Bench 2.1** in **Terminus 2**. Its **19.1% TB4** is sourced
from the public leaderboard at the highest-scoring available effort. These
are not the independent Antigravity rows above, nor interchangeable versions
of Terminal-Bench. [Gemini-card], [Gemini-evals]

Google explicitly says high effort can increase token use and iterative tool
calls; lower effort can improve efficiency. Supported low/medium/high is
verified, but **no independent medium-versus-high UI or coding cost frontier
was recovered**. There is no published max level to recommend. The 1M context
and multimodal inputs support the UI/large-input lane; neither proves superior
UI aesthetics or bug-finding performance. [Gemini-launch], [Gemini-thinking]

### Latency evidence limits

The independent table reports full agent wall time, the most relevant available
measure for delegated coding. API token generation speed and first-answer
latency are different: AA's model methodology also uses 60 diverse prompts
and synthetic response-time measures, not completed repository tasks.
Anthropic reports Sonnet/Opus output generation over 30% faster than predecessors;
Haiku's launch quotes one customer seeing over 30% lower completion latency and
up to 2.5x faster inference/turn. These are vendor/customer claims, not controlled
Pi role measurements. [AA-general], [Sonnet], [Opus], [Haiku]

## Subscription accounting: what is and is not published

[OpenAI Codex pricing][Codex-pricing] explicitly says API prices are separate
from subscription usage and warns that context, reasoning, tools, retrieval,
and caching affect included consumption. As retrieved on October 7:

- Standard **purchased-credit/credit-based** rates per million
  input/cached/output tokens: Sol 6.1 **50 / 2.5 / 250 credits**;
  Luna **2.5 / 0.25 / 12.5 credits**. This gives 20x uncached/output and 10x
  cached **credit-rate** ratios for equal token counts, **not** a fixed
  included-plan per-task multiplier. Codex credit billing has no cache-write
  charge; API accounting can have one.
- Fast mode uses **2.5x included subscription usage**, but **2x purchased
  credits** relative to Standard. This is a published speed-mode multiplier,
  not a high/max reasoning multiplier.
- Pro plans currently have **no five-hour limit**, while weekly limits may
  apply; actual account limits/reset times belong in the usage dashboard.
  The root must separately establish what Pi sees through its adapter. Do not
  extrapolate Plus/Business message estimates into a $200 Pro task allowance.

Anthropic says higher effort consumes more tokens and reaches usage limits
faster, but the fetched effort/launch pages do not publish an exact
Haiku/Sonnet/Opus **Team included-usage multiplier by effort**. The Opus launch
announces increased five-hour limits, without a numeric conversion for this
account. Sonnet and Opus are not independent quota pools. [Claude-help], [Opus]

A new, separately claimable **API credit** was announced October 7: Team
Premium seats receive **$100/seat/month**, pooled with Standard seats at
$20/seat, **capped at $500/team/month**. Rollout takes several days, eligibility
includes seven days on an eligible plan, and a team owner links one Console
organization. It is **not** $100 of automatically usable Pi subscription
allowance and does **not** cover interactive Claude Code or extra subscription
usage. No credit was claimed, billing changed, or account data read here.
If it becomes available, the API route and team-wide spending controls are a
separate decision. [Team-credit]

Haiku API input/output rates are $0.10/$0.50 per MTok up to **100k prompt
tokens**, $0.50/$2.50 above 100k; cached reads $0.01/$0.05. Sonnet cache reads
fell from $0.20 to **$0.10/MTok** on October 7. These thresholds and cache
prices explain why one headline token-price ratio is not a task-cost ratio.
Neither price change alone establishes changed included Team allowance.
[Haiku]

## Historical task/model/effort candidates

Confidence describes transfer to **Pi tasks**, not certainty that the model
exists. All recommendations retain checks/review appropriate to the task.
These were research candidates before implementation. The [routing guide](pi-subagents-model-routing.md) describes subsequent managed-source changes; no adapter or runtime configuration was changed for this research.

| Task regime | Historical model / effort candidate | Tradeoff versus baseline roles | Confidence / evidence |
| --- | --- | --- | --- |
| Coordination with significant ambiguity or correctness risk | Keep `gpt-6.1-sol` high initially; trial medium on routine coordination, xhigh on genuinely difficult reasoning | Current high is defensible; observed medium efficiency argues for a scoped comparison, not a blanket downgrade | Medium: Sol sweep is empirical but Codex coding is not Pi coordination. [AA], [Sol-doc] |
| Hard implementation, deep repository tracing, complex Effect work | `gpt-6.1-sol` medium for bounded work; xhigh for difficult end-to-end work | Move hard Explore/implementer packets off Luna max; preserve existing Effect medium. Avoid automatic Sol max | Medium-high for coding; medium for transfer to exploration. [AA], [AA-method] |
| Narrow extraction, mechanical edits, concise factual lookup with explicit verification | `gpt-6-luna` max can remain a low-API-cost lane; trial high only as a **vendor-guided**, unmeasured coding-effort candidate | Do not give Luna all implementation/exploration. OpenAI recommends starting Luna high, but recovered coding evidence covers max only | Medium for narrow-task model fit, low for an optimum Luna effort. [Codex-models], [AA] |
| Ordinary planning/review of well-specified bounded changes | Keep `anthropic/claude-sonnet-5-5` medium | Preserves model diversity and quick iteration; no direct review false-negative benchmark in this independent suite | Medium. [AA], [Claude-effort] |
| Deep review, architecture ambiguity, subtle failures, long multi-step plans | `anthropic/claude-sonnet-5-5` high or xhigh; consider `anthropic/claude-opus-5-5` medium when judgment dominates | Explicit escalation above current reviewer/Plan medium; Opus medium need not mean max expense. Both spend the Anthropic pool | Medium: Sonnet sweep and vendor Opus/FrontierCode evidence; no independent Opus-medium row recovered. [AA], [Sonnet], [Opus] |
| UI screenshots, multimodal inspection, large input exceeding Codex capacity | Keep `opencode/gemini-3.8-flash` medium; use registered Copilot Gemini backup. Trial high only when task demands it | Preserves current UI lane and 1M context; no empirical evidence that medium is optimal for UI | Medium for input/context fit, low for effort frontier. [Gemini-card], [Gemini-thinking], [AA] |
| Summaries, classification, compaction, short checkable subagent leaves | `anthropic/claude-haiku-5-5` low for very short extraction or medium for multi-step leaves; high for strict adherence if justified | Adds a small-model lane, not a substitute for every Sonnet role. Explicitly require real checks; low/medium can omit them | Medium for fit; **registered locally after refresh**. [Haiku-doc], [Haiku-prompt], [AA] |

Do not force all reviewers to Opus max, all explorers to Haiku low, or all
models to medium. Small models should receive small packets with explicit
completion/verification criteria; high effort is an escalation tool, not a
substitute for narrowing context or defining success.

## Remaining gaps and bounded next checks

1. **No Pi effort sweep or live subscription debit measurement.** Before
   changing global pins, compare a small set of representative existing tasks
   by accepted completion, checks, review repairs, wall time, input/cache/
   reasoning/output tokens, and allowance change within the same reset window.
   Live prompts require separate authorization; none were run here.
2. **Adapter semantics:** confirm requested Pi thinking is actually transmitted
   for each provider/model, and qualify Haiku's adaptive thinking, preserved
   thinking/account boundaries, tool calls, 128k output, refusal handling, and
   unsupported sampling controls in live use. Catalog presence and static
   low/medium adaptive-thinking support are now checked; no custom registration
   is needed. A catalog check is not a live inference test. [Haiku-doc], [Haiku-prompt], [Claude-effort]
3. **Sparse independent frontiers:** Luna non-max, Gemini low/medium, Opus
   non-max, and role-specific UI/review evidence remain absent from the recovered
   coding-agent data. Vendor sweeps are labeled as such. Exact experiment
   context caps and some time-budget details remain unrecovered.
4. **System-card extraction ceiling:** official Haiku/Sonnet/Opus system cards
   were fetched, but the extraction tool retained only the first 100 pages;
   later capability-methodology sections were not available in that extraction.
   The note consequently uses verified launch chart labels and separately
   recovered AA/Cognition/Google methodology, rather than claiming an unread
   complete system-card manifest. [Haiku-card], [Sonnet-card], [Opus-card]

## Sources

All URLs below were fetched or inspected on **2026-10-07**. Official launch
chart data and the independent embedded rows were additionally inspected as
public HTML without authentication. OpenAI's Sol/Luna introduction page returned
HTTP 403; no search-only claim from it is treated as verified evidence.

[AA]: https://artificialanalysis.ai/agents/coding-agents/
[AA-method]: https://artificialanalysis.ai/methodology/coding-agents-benchmarking/
[AA-Sol]: https://artificialanalysis.ai/articles/gpt-6-1-sol-replaces-gpt-6-sol-after-just-7-days-with-near-astra-intelligence
[AA-intel]: https://artificialanalysis.ai/methodology/intelligence-benchmarking
[AA-general]: https://artificialanalysis.ai/methodology
[Sol-doc]: https://developers.openai.com/api/docs/models/gpt-6.1-sol
[Luna-doc]: https://developers.openai.com/api/docs/models/gpt-6-luna
[Codex-models]: https://developers.openai.com/codex/models
[Codex-pricing]: https://developers.openai.com/codex/pricing/
[Haiku]: https://www.anthropic.com/claude-haiku-5-5
[Haiku-doc]: https://platform.claude.com/docs/en/models/haiku-5-5/overview
[Haiku-prompt]: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5
[Sonnet]: https://www.anthropic.com/claude-sonnet-5-5
[Opus]: https://www.anthropic.com/claude-opus-5-5
[Claude-effort]: https://platform.claude.com/docs/en/build-with-claude/effort
[Claude-help]: https://support.claude.com/en/articles/8664678-change-the-model-effort-and-thinking-settings
[Team-credit]: https://support.claude.com/en/articles/17154008
[Frontier-method]: https://cognition.com/blog/frontier-code-1.1
[Frontier-board]: https://cognition.com/frontiercode
[Gemini-launch]: https://blog.google/innovation-and-ai/models-and-research/gemini-models/3-8-flash-and-3-8-flash-cyber/
[Gemini-card]: https://deepmind.google/models/model-cards/gemini-3-8-flash/
[Gemini-evals]: https://deepmind.google/models/evals-methodology/gemini-3-8-flash/
[Gemini-thinking]: https://ai.google.dev/gemini-api/docs/thinking.md
[Haiku-card]: https://www.anthropic.com/claude-haiku-5-5-system-card
[Sonnet-card]: https://www.anthropic.com/claude-sonnet-5-5-system-card
[Opus-card]: https://www.anthropic.com/claude-opus-5-5-system-card


## 2026-10-08 UTC — Native OpenAI versus legacy Codex routing

**Historical assessment before migration was authorized; current source uses
native `openai` and does not retain a legacy login dependency.**
The user's correction is right: **first-party Pi itself calls the Codex route
legacy**, not merely Narumitw. Pi 0.99.0's September 29 changelog says native
Sign in with ChatGPT “supersedes it.” The current provider is still registered,
with OAuth, Sol/Luna catalog entries and a working adapter implementation:
legacy means superseded here, not removed. No removal deadline or declaration
of unsupported operation was found in the inspected first-party changelog and
provider sources. Calling it “deprecated and unusable” would overstate the
evidence. [Native-Pi-change], [Native-Pi-providers], [Native-Pi-codex]

### Evidence boundary and installed version

Checked public Pi `main` at commit
`1cedd32724abfcb0915f76cc61b6827e2c16dbad` and installed package code on
**2026-10-08, approximately 07:24 UTC**. The Homebrew directory is named
`1.0.4`, but both the coding-agent manifest and its nested `pi-ai` manifest
report **1.1.0**; this is a static manifest observation, not proof of the running
session's bundle/version. Both installed provider factories already implement
the native ChatGPT subscription route and label Codex legacy. Older research
above is preserved, not silently rewritten. Local evidence below means the
installed package or managed source, never credentials, authenticated model
lists, quota queries, or inference. [Native-local-sdk], [Native-Pi-openai]

### Models, reasoning and authentication

| Question | Verified static result / qualification boundary |
| --- | --- |
| Sol and Luna IDs | `openai/gpt-6.1-sol` and `openai/gpt-6-luna` are native **chat** entries; Codex keeps the same model IDs under its provider. No model-generation alias or custom registration is required. Installed Pi advertises **272,000 context / 128,000 output on both routes**, not an automatic native 1M upgrade. [Native-Pi-generator], [Native-local-sdk] |
| Reasoning levels | Installed native Sol supports low/medium/high/xhigh/max; off and minimal map to unsupported (`null`). Native Luna also supports off → `none`, but minimal is unsupported. Codex minimal maps to **low** for both. The actual intended pins (Sol medium/high/xhigh and Luna max) have identity mappings on both routes. Static support does not establish identical live effort, quota debit or completion quality. [Native-local-sdk], [Native-Pi-generator], [Native-Pi-response], [Native-Pi-codex-response] |
| Account availability | A bundled Pi catalog is not account entitlement. OpenAI instructs clients to retrieve the signed-in account's `/v1/models`, use visible slugs and refresh on account switch; its official example uses `gpt-6.1-sol`. No authenticated catalog request was made here, so native Luna availability for this user's exact account/workspace remains unverified. [Native-OAI-models] |
| Native subscription auth | `/login openai` → **Sign in with ChatGPT** uses OAuth with `resource.invoke` and `chatgpt.tokens.use.direct`, an issued client ID, and stable installation/device ID; the access token targets `api.openai.com/v1`. It is a new grant, not a copied Codex token. Pi validates the direct-token scope. [Native-Pi-oauth], [Native-OAI-overview] |
| API-key auth | The same `openai` provider also accepts an API key / `OPENAI_API_KEY`; this is a different billing path, not conversion of $200 Pro into API credit. Pi's shared resolver prefers a stored credential over ambient environment credentials and does not silently fall back to environment auth after OAuth-refresh failure; explicit runtime overrides still take precedence. Confirm the selected auth method during qualification without exporting secrets. [Native-Pi-openai], [Native-Pi-auth], [Native-OAI-errors] |
| Other operations | Native OAuth is not blanket OpenAI API entitlement: Pi filters classifier models for OAuth because Decisions rejects it. OpenAI also excludes hosted image generation and other capabilities below. Do not confuse Luna's classifier entry with its chat entry. [Native-Pi-openai], [Native-OAI-preview] |

### Subscription pools: what changes and what does not

Native OAuth explicitly consumes the user's **ChatGPT plan**, and OpenAI calls
its application limit a limit on plan usage, not a new reservation. Its issued
client ID is bound to user/workspace and usage settings; multiple hosts can
share that registration and limits. OpenAI's usage UI guidance distinguishes
**plan versus app-specific limits**: `subscription_sharing_usage_limit_exceeded`
(429) can mean either, and does **not** prove the whole plan is exhausted or
supply a reset time. Moving provider IDs is therefore **not extra independent
Pro allowance**, nor a reason to fail over from native to Codex as if they were
separate subscription pools. [Native-OAI-overview], [Native-OAI-ui],
[Native-OAI-errors]

The official Help Center search result describes weekly app caps as a
percentage of the overall plan and optional credit use as off by default, but
that page returned 403 to direct retrieval. These details are **search-only
corroboration**, not grounds to change app caps, permit spending or claim this
account's settings. The fully retrieved developer documentation independently
establishes plan-backed usage and app-specific limits. No retrieved source
establishes a complete native-versus-Codex per-model/per-effort debit multiplier,
this user's exact native app cap, or native reset-window correspondence to the
legacy Codex windows. **Equal API-equivalent token prices are not proof of equal
subscription debit.** Keep the existing Sol/Luna effort research as task-fit
hypotheses; native savings require measured accepted-task results and actual
allowance observations after separate authorization. The working Anthropic
Team Premium lane is unchanged; this research does not reopen its billing.
[Native-OAI-help], [Native-OAI-overview], [Native-OAI-errors], [Native-local-sdk]

### Request, tool, image and cache differences

- **Endpoint/transport:** native Pi uses the OpenAI SDK's streaming HTTP
  Responses call at `api.openai.com/v1`; Codex uses ChatGPT backend requests,
  tries WebSocket in auto mode, and can fall back to SSE. Both send
  `store: false` and streaming requests. Native is the documented plan-sharing
  endpoint; OpenAI explicitly says not to point its native token at backend-api.
  No measured latency advantage follows from this source comparison.
  [Native-Pi-response], [Native-Pi-codex-response], [Native-OAI-models]
- **Tools:** Pi shares Responses message/tool conversion and the catalogs
  advertise grammar/custom tools, additional tools and mid-conversation system
  updates. Native Sol/Luna have strict-mode capability enabled; the Codex builder
  emits `strict: null`, top-level instructions, low text verbosity by default,
  and `parallel_tool_calls: true`. Native uses developer messages for reasoning
  models. Different request defaults mean provider renaming is not wire-level
  equivalence. OpenAI's native preview allows namespace function/custom tools
  and `additional_tools`, but forbids hosted MCP, Code Interpreter, file search,
  native computer use, image generation and Responses `tool_search`. **Local
  Pi shell/MCP/delegation tools are not those hosted tools.** Qualify the actual
  Agent/codemode/deferred-tool loadout; generic catalog `supportsToolSearch`
  alone does not prove the OAuth route accepts every representation. Pi prefers
  `additional_tools` for added tools where supported. [Native-Pi-shared],
  [Native-Pi-response], [Native-Pi-codex-response], [Native-OAI-preview]
- **Images:** both installed chat entries accept text and images; shared code
  transmits user/tool images as data URLs. Their resize metadata is the same
  (2000×2000, 4.5 MiB, JPEG quality 80); native additionally advertises request
  and image-count caps. The managed `images.autoResize: false` is not changed
  by switching providers. No screenshot quality or large-image live behavior
  was tested. Image **input** is supported; hosted image **generation** is not
  supported by this native OAuth flow. [Native-local-sdk], [Native-Pi-shared],
  [Native-managed-settings], [Native-OAI-preview]
- **Output/cache controls:** native OAuth deliberately omits `max_output_tokens`,
  `temperature`, `prompt_cache_retention` and `prompt_cache_options`; the
  first-party mocked-payload tests assert this. API-key requests can keep those
  controls. A catalog's 128k output is not an enforced per-request budget for
  native OAuth. Both adapters can send a session-based `prompt_cache_key`,
  omitted for cache retention `none`; native OAuth does not offer the API-key
  route's explicit TTL/cache policy controls. No cache-hit or allowance benefit
  from migrating is established. [Native-Pi-response], [Native-Pi-tests],
  [Native-Pi-codex-response], [Native-OAI-preview]
- **History/errors:** provider/API identity changes cause Pi's transform to
  drop incompatible opaque reasoning and convert visible thinking to text;
  native migration does not preserve a Codex WebSocket continuation or promise
  warm-cache equivalence. Prefer a bounded fresh handoff for qualification.
  Native usage-limit errors can also arrive after streaming starts; Pi appends
  the ChatGPT usage link and treats the specific exhausted-limit error as
  non-retryable, unlike temporary availability errors. Existing status-only
  fallback rules need qualification against both HTTP and streamed errors.
  [Native-Pi-transform], [Native-Pi-response], [Native-Pi-retry],
  [Native-OAI-models], [Native-OAI-errors]

### Quota reporting limitation

Installed **`@narumitw/pi-usage` 0.64.1** is third-party tooling, not authority
for Pi's deprecation policy. Its native report obtains numeric plan usage only
through an automatically queried legacy login. The backend endpoints are
experimental and undocumented; a client-ID match is not independent proof of
shared identity or live quota agreement. Without that login it reports auth
status and a dashboard link. It never forwards the native token to those
ChatGPT backend routes. [Native-usage]

After clarification, the user retains that login for quota reporting only.
The managed bridge invokes the native adapter with explicit experimental
provenance and separate plan/app scope; inference remains native. The checked
package and official docs do not establish a native-only numerical API.
App allowance caps are not remaining quota, and an app-limit failure does not
prove whole-plan exhaustion. [Native-managed-quota], [Native-OAI-errors]

### Migration reach and qualification boundary

Managed settings, fresh-call coordinator routes and fallback source/destination
provider fields now use native `openai`, preserving model IDs, intended effort,
permissions, rule order and `autoRetry: false`. Legacy authentication is
retained for telemetry, not inference. [Native-managed-settings],
[Native-managed-coordinator], [Native-managed-fallback], [Native-managed-quota]

The user performs native-provider testing and retains the companion login. Source preview/application,
root/child runtime models, live tools/images, cache behavior, subscription debit
and streamed-error fallback remain separate qualification steps; no live
allowance, performance or effort equivalence is claimed. No quota is burned to
provoke a 429, and no app cap or spending option is changed here.
[Native-OAI-models], [Native-OAI-preview], [Native-Pi-retry]

**Checks/limits:** appended research only; prior benchmarks preserved. No auth
files read, credentials resolved, inference/quota calls, installation, runtime
apply, login, commits or pushes. Public developer pages and relevant Pi source
were read; the Help Center page was blocked, and account-specific availability,
subscription-debit equivalence, companion/native quota mapping, headless
failover and real tool/image/cache behavior remain unverified.

### Sources for this dated section

Pi source URLs are pinned to the inspected commit, rather than mutable `main`.
Local SDK observations came from
`/opt/homebrew/Cellar/pi-coding-agent/1.0.4/libexec/lib/node_modules/@earendil-works/pi-coding-agent/`
and its `node_modules/@earendil-works/pi-ai/`: package manifests,
the native/legacy provider modules and generated catalog JSON, and native
adapter code.

[Native-Pi-change]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/coding-agent/CHANGELOG.md#0990---2026-09-29
[Native-Pi-providers]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/providers/all.ts
[Native-Pi-openai]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/providers/openai.ts
[Native-Pi-codex]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/providers/openai-codex.ts
[Native-Pi-generator]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/scripts/generate-models.ts
[Native-Pi-oauth]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/auth/oauth/openai-chatgpt.ts
[Native-Pi-auth]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/auth/resolve.ts
[Native-Pi-response]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/api/openai-responses.ts
[Native-Pi-codex-response]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/api/openai-codex-responses.ts
[Native-Pi-shared]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/api/openai-responses-shared.ts
[Native-Pi-transform]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/api/transform-messages.ts
[Native-Pi-tests]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/test/openai-responses-chatgpt-sign-in.test.ts
[Native-Pi-retry]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/ai/src/utils/retry.ts
[Native-Pi-docs]: https://github.com/earendil-works/pi/blob/1cedd32724abfcb0915f76cc61b6827e2c16dbad/packages/coding-agent/docs/providers.md
[Native-OAI-overview]: https://developers.openai.com/siwc/token-sharing-open-source
[Native-OAI-models]: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
[Native-OAI-preview]: https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
[Native-OAI-errors]: https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery
[Native-OAI-ui]: https://developers.openai.com/siwc/ui-ux-guidelines
[Native-OAI-help]: https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites
[Native-usage]: https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage#chatgpt-companion-usage
[Native-local-sdk]: file:///opt/homebrew/Cellar/pi-coding-agent/1.0.4/libexec/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/providers/data/
[Native-managed-settings]: ../home/private_dot_pi/private_agent/settings.json
[Native-managed-coordinator]: ../home/private_dot_pi/private_agent/private_docs/coordinator.md
[Native-managed-fallback]: ../home/private_dot_pi/private_agent/private_model-fallback/config.json
[Native-managed-quota]: ../home/private_dot_pi/private_agent/private_extensions/quota-status/quota.ts
[Native-managed-fallback-guide]: model-fallback.md
[Native-managed-routing-guide]: pi-subagents-model-routing.md

### Managed-source follow-through

The user confirmed native OpenAI login and, after understanding the package
contract, retains the legacy credential for telemetry. Managed defaults, fresh
calls and fallback provider fields use `openai`; quota reporting uses its
native adapter with a validated companion credential.
Mocked SDK/Jiti and static checks do not qualify live native performance,
app headroom or numerical quota. No runtime source was applied.

### Native-only numeric usage verification — follow-up

**Numerical telemetry is unsupported with the checked package and sources.**
No verified collector using only Pi's native `openai` OAuth login was found.
After legacy logout, Narumitw displays auth status and the usage dashboard link,
not percentages. The user chose to retain that login for reporting; this does
not restore legacy inference routes.

- Installed and checked npm-latest Narumitw are both **0.64.1**. Its native auth
  resolver calls `resolveOpenAICompanionAuth` and requires a unique legacy OAuth
  credential/account ID for numeric usage. The bridge now uses that validated
  path. Without it, there are no numeric windows. [Native-usage]
- `src/providers/openai-chatgpt.ts` distinguishes native `api.openai.com`
  authorization from the undocumented ChatGPT usage contract. No native token
  was sent there, and no evidence that doing so is supported was found.
- Official [overview][Native-OAI-overview], [inference][Native-OAI-models],
  [limits][Native-OAI-preview] and [errors][Native-OAI-errors] cover native
  inference. `subscription_sharing_usage_limit_exceeded` is a non-numeric limit
  signal, not a percentage or reset time. The pages are JS-heavy; this bounded
  reading is not proof that no native-only endpoint exists.
- Use https://chatgpt.com/settings/usage for human-visible native plan/app usage.
  A numerical model tool needs a verified native API before adding a collector.
  No credentials were read, provider endpoints called, runtime changed or
  packages installed during this verification.

## 2026-10-08 UTC — Effort audit of every coordinator route, including Opus review

Scope: every task row in the current source
`home/private_dot_pi/private_agent/private_docs/coordinator.md` (unstaged
working copy), using the requested model IDs literally. Evidence comes in
three kinds: **[I]** independent benchmark, **[V]** vendor benchmark, default or
guidance, **[P]** our subjective task-fit policy. No review-specific benchmark
compares any of these models or effort levels. No Pi sweep exists.
Availability and adapter checks belong to a separate lane.

**Rechecked today.** The AA leaderboard still has only **max** rows for Opus
5.5 and Luna, and only **high** for Gemini 3.8 Flash. Spot rows are unchanged
(Sol medium 61.41, Luna max 41.07), so the 2026-10-07 tables still stand.
[AA] Vendor effort guidance:
- **Anthropic:** Opus 5.5 and Haiku 5.5 default to medium. xhigh is for
  agentic work running over 30 minutes. Sonnet 5.5 should start at medium
  for well-specified agentic work, high for harder or longer work, and
  xhigh/max "only where your evals show a quality gain". At low, Haiku may
  skip checks in long prompts. [Claude-effort]
- **Opus 5.5 guide:** code review is its strongest area; early testers report
  "more bugs caught… fewer false alarms". It says to reserve xhigh/max for
  measured gains. [Opus-prompt]
- **Sonnet 5.5 guide:** "for the hardest long-horizon work, an Opus model is
  the better choice". At xhigh and above, Sonnet starts its own review rounds.
  [Sonnet-prompt]
- **Opus launch page:** a customer anecdote, not a benchmark, says Opus 5.5
  at low caught 72% of known review bugs, versus 56% for Opus 5 at high. Most
  cybersecurity tasks are transparently re-routed to Opus 4.8. [Opus]
- **OpenAI:** Luna low for simple extraction, Luna xhigh for constrained
  problems, Sol medium for complex technical work, Sol xhigh for "decisions
  built from conflicting evidence". It says to start Luna at High, and "most
  tasks do not need Max". [OAI-model-selection], [Codex-models]
- **Google:** Gemini defaults to medium and supports low/medium/high, with no
  published frontier. [Gemini-thinking]

### Route classification: default, then escalation

| Task row | Default | Escalate when | Change from current source |
| --- | --- | --- | --- |
| Narrow, checkable | Luna `high` | Luna `xhigh` for multi-step constrained work; `max` only after a diagnosed reasoning gap | Luna `max` → `high`. [V] guidance only; the only [I] row is max (21 min, about 98k output tokens per hard task). Low–medium confidence. |
| Substantive implementation | Sol `medium` | Sonnet `high`, then Opus `medium` | None. [I] Sol medium ≥ high; Sonnet high > medium. |
| Difficult implementation | Sol `xhigh` | Opus `high`, then Sonnet `xhigh` | Opus `medium` → `high` (TB4 [V] +6.6; FrontierCode flat). Sonnet `high` → `xhigh` ([I] Index 62.87 vs 55.01, about 2.7x cost; DeepSWE only 68.44 vs 66.67, so not a guaranteed implementation gain). |
| Research / hard tracing | Sol `medium` | Sonnet `high` | Sonnet `medium` → `high` ([I] repository Q&A 44.89 → 56.45). |
| Bounded planning/review | Sonnet `medium` | Sol `medium`, Opus `medium` | None. Fits vendor advice; no review benchmark. |
| Deep/cross-layer review | Sonnet `high` | Sol `xhigh`, Opus `medium` | Sol `high` → `xhigh`: [I] observed Q&A: 59.95 < medium 60.75 < xhigh 61.02; no significance or review-optimum claim. |
| Architecture/judgment | Opus `medium` | Sonnet `high`, Sol `xhigh` | Sol `high` → `xhigh`, same reason as above. Opus medium rests on [V] evidence only. |
| Visual/UI | Gemini `medium` | Gemini `high` only for harder visual work | Default unchanged; Copilot alternative removed after SDK check below. Low confidence; no frontier published. |
| Short extraction | Haiku `low` (single-step) / `medium` (multi-step) | Luna `low` / `high` | Luna `max` → `low`/`high`. [V] OpenAI recommends Luna low for extraction. |

The cross-provider order is [P] fit, not effort equivalence.

### Proposed exceptional review tier

**Task boundary [P].** This tier is for review packets where a missed defect
is costly or a prior review was not trusted:
- the change touches auth, permissions, secrets handling, money, data
  loss/migration, or concurrency/state invariants;
- the change is irreversible or externally visible;
- a small diff has a large blast radius;
- the user asks for adversarial "try to break it" review;
- reviews disagree, or one missed a defect.

Ordinary deep review stays on the deep-review row.

**Default route [P]:** Opus `high` → Sol `xhigh` → Copilot Sol `xhigh` →
Sonnet `xhigh`. Opus `xhigh` is a separate task-local quality escalation, not
a quota/failure fallback; same-pool changes do not replenish allowance.
- **Opus `high` (default for this tier):** on [V] FrontierCode, a
  mergeability/judgment benchmark, high ≈ medium (54.0 vs 54.6), so this sample suggests roughly level judgment scores, not a guaranteed
  lack of regression in review. On [V] TB4, high exceeds medium by 6.6 points at about 1.3x cost; this is a candidate
  benefit for terminal reproduction, not a significance-tested review gain.
- **Opus `xhigh` (escalation):** a candidate for long adversarial audits running
  reproductions. Anthropic describes long-horizon work as over 30 minutes,
  but that is not our dispatch cutoff: task-local gains or user choice decide. On TB4 it gains
  +2.2 over high, smaller than the reported ±2.6 error-bar magnitude (not a
  significance test for the difference), at about 1.9x the cost. On FrontierCode it is lower (51.4).
- **Opus `max`:** no routine review default is justified by the recovered data;
  explicit user choice or task-local measured quality gains may justify it.
- **Alternatives:** Sol offers an independent-provider perspective. Sonnet
  remains a compatible last option for a model-specific issue, but shares the
  Anthropic pool and cannot relieve shared quota pressure.

Confidence is low to medium. This is vendor coding data transferred to
review; no review comparison exists.

**Security caveat [V]:** provider safety handling may change the actual model
or refuse high-risk requests. Record observed refusals/fallbacks and preserve
safeguards; do not disguise a request to bypass them. Defensive source-code
vulnerability review is allowed according to the prompting guide. [Opus-prompt]

**Historical audit-batch quota snapshot (2026-10-08).** The observed Claude
weekly reading of 92% put the
Anthropic pool in **conserve**, not exhausted. It is not current headroom.
Under the coordinator's
quota-state rules:
- Opus exceptional review and this audit qualify as work where the pool's
  task advantage matters.
- Routine Anthropic-first rows (bounded review, Sonnet fallbacks) should
  move to independent Sol routes.
- Avoid repeated Opus runs or ensembles.

No per-effort allowance debit is published or inferred here.

### Root startup convention: Sol `high`

This is kept separate from the worker routes. The root follows the
**active Pi selection**; managed startup is Sol `high`. No settings edit is
recommended or authorized here.

AA's coding-agent result that Sol medium ≥ high comes from Codex
repository and terminal tasks. It does **not** establish the best effort for
coordination: routing, packet writing and judging evidence across workers.
Keep `high` until a Pi comparison of coordination quality exists. A user's
active choice overrides the startup setting.

### Unsupported or open

- No independent data exists for Opus at medium, high or xhigh; for Luna
  below max; or for Gemini at medium.
- No review false-negative or false-positive benchmark exists, and no Pi
  sweep has been run.
- Confirming these changes needs a small set of representative packets,
  measuring accepted completion, defects found later, wall time and observed
  allowance. That needs separate authorization. No inference or quota calls
  were made here.

[Opus-prompt]: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
[Sonnet-prompt]: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5
[OAI-model-selection]: https://developers.openai.com/api/docs/guides/model-selection

### Installed SDK effort verification (root follow-up)

Public SDK 1.1.0 static catalogs register all 11 source provider/model routes
from the pre-audit table. `getSupportedThinkingLevels` in `pi-ai/dist/models.js`
filters null mappings; xhigh/max need explicit mappings. Positive Sol/Luna and
Claude 5.5 selections map to their same-named effort. Go Haiku low/medium use
the adaptive adapter's default mapping (not an unsupported missing map).

One material exception: Copilot Gemini 3.8 Flash uses `openai-completions`
with `compat.supportsReasoningEffort: false`; the request builder omits
`reasoning_effort`. Exact `detectCompat`/`getCompat` also resolve the format
to OpenAI, with no thinking budget or chat-template alternative. Generic UI
level exposure is not wire-level control.
The operational table therefore drops that effort-qualified alternative; the
model remains registered and explicit user selection must disclose the limit.
OpenCode Gemini uses `google-generative-ai` with low/medium/high identity maps;
xhigh/max are null and must not be requested as controlled levels.

Evidence: installed `pi-ai/dist/providers/data/{anthropic,openai,opencode-go,
opencode,github-copilot}.json`; `dist/models.js:678–708`;
`dist/api/anthropic-messages.js:697–738`;
`dist/api/openai-completions.js:714–721,1310–1318`. Static request mapping is
not account entitlement, live endpoint agreement or cross-provider equivalence.
The attempted Go Luna worker failed before tools/inference with the same stale
SDK chunk as native OpenAI; it supplies no model-quality or quota evidence.
No repair or live inference test was performed.
