# Pi model fallback

This documents the managed configuration and installed `pi-model-fallback`
**0.5.2** behavior. The ordered routes live in the [managed config](../home/private_dot_pi/private_agent/private_model-fallback/config.json), not a duplicate table here. For role pins and task routing, see [Pi subagents and model routing](pi-subagents-model-routing.md).

## Source and state

- Managed source: `home/private_dot_pi/private_agent/private_model-fallback/config.json`.
- Runtime config: `~/.pi/agent/model-fallback/config.json`.
- Runtime cooldown state: `~/.pi/agent/model-fallback/state.json`.
- The managed source is enabled, has `autoRetry: false`, and contains 14 ordered rules. This does not claim the runtime copy has been applied.

The extension records cooldowns by failing source `provider/model`, not by
account or subscription pool. `/model-fallback:status` and
`model_fallback_config` `read`/`status` expose fallback configuration and
cooldowns only, not quota. The separate managed `quota_status` tool and its
provider/source limitations are documented in [quota access](pi-quota-usage.md).

## Matching and switching

- Rules are evaluated in order. In 0.5.2, `findFallback` selects the first rule matching the source model/provider and status.
- Go failures route to Copilot Luna, Copilot to native OpenAI Luna, and native OpenAI to subscription Sonnet. Exact native Luna rules precede the broad OpenAI rules. Subscription Haiku routes to Copilot Luna; other Anthropic models route to native Sol.
- Zen and Contributor endpoints are absent: the user is not funding Zen, and a reactive switch cannot check Contributor training consent. Go Kimi shares the Go provider failure route rather than retrying another model on an exhausted pool.
- No automatic rule enters `anthropic-api`: a reactive status switch cannot enforce grant reserves or the monthly spending cap. The coordinator may explicitly select it only with sufficient budget evidence. Existing API sessions fail over to Sol on configured statuses. Its out-of-credit 400 is deliberately not a blanket 400 rule; use the exhaustion observation and inspect the refusal.
- Evidence and caveats: see [routing research](model-routing-research.md). These are model-recovery routes, not quota optimization. Fallback config selects a model; it neither configures per-fallback reasoning effort nor guarantees its preservation.
- Fallbacks can chain when a selected fallback model later fails and matches another rule. The loop guard tracks visited `provider/model` pairs for the current agent run and resets at `agent_start`; it does not track shared subscription pools. A path through Copilot, native Luna and Sonnet can still revisit an exhausted provider under a different model. The loop guard prevents repeated model pairs, not every shared-pool revisit.
- Matching non-2xx responses in `after_provider_response` and parsed assistant errors at `turn_end` can switch models. There is no automatic return to the primary model during the session; `/model-fallback:reset` clears persistent state and returns to the remembered original model when possible.
- OpenAI's `subscription_sharing_usage_limit_exceeded` can mean an app-specific cap or a whole-plan limit; the status rule cannot distinguish them, and an app cap does not prove whole-plan exhaustion. Native usage-limit errors may arrive after streaming starts without a matching HTTP status, so the configured status rules are not guaranteed to catch them. No live streamed-error behavior is qualified.
- Headless/subagent failover is not established: the child must load the extension, and no live child 429 trace has validated the behavior.

## Retry and cooldowns

`autoRetry: false` prevents failed-prompt replay but leaves reactive model
switching enabled. When `turn_end` handles a parsed error and a fallback switch
succeeds, auto-retry queues the latest user message's text blocks as a follow-up;
non-text blocks such as images are dropped. Replaying could duplicate edits or
other side effects completed before a failed response, so automatic replay is
disabled.

Configured quota/auth cooldowns are 18,000,000 ms (five hours), and
transient-error cooldowns are 600,000 ms (ten minutes); exact status scopes are
in the managed config. Rules also match 401 for credential failures; this does
not make an invalid token evidence of exhausted credits. Five hours is a
configured fallback window, not an authoritative subscription reset.
`Retry-After` and recognized provider reset headers override the configured
duration and can shorten it.

## Updating the managed setup

Edit the managed source, then preview and apply only the runtime config:

```sh
chezmoi diff ~/.pi/agent/model-fallback/config.json
chezmoi apply --exclude scripts ~/.pi/agent/model-fallback/config.json
```

Do not put credentials or runtime state in this repository.

## Verification limits

The offline routing check is `python3 scripts/test-pi-routing.py`. It verifies
subscription-only fallback targets, no Zen/Contributor automatic routes and the
Go → Copilot → native Luna chain. It cannot establish live auth, entitlement,
effort preservation, model quality or headless/streamed failover. Startup settings
and fallback source edits do not change an already-running coordinator.
