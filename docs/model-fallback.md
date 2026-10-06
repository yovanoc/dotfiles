# Pi model fallback

This documents the applied global setup for `pi-model-fallback` 0.5.1.

## Source and installed state

- Managed source: `home/private_dot_pi/private_agent/private_model-fallback/config.json`.
- Runtime config: `~/.pi/agent/model-fallback/config.json`.
- Runtime cooldown state: `~/.pi/agent/model-fallback/state.json`.
- The source was already scoped-applied and verified. Current status: enabled,
  `autoRetry: true`, 12 rules, no warnings.
- Cooldowns are stored per source model, not in a provider-wide pool.

## Configured routes

The UI pin is `opencode/gemini-3.8-flash`. The matching routes form these paths:

- UI: `opencode/gemini-3.8-flash` → `github-copilot/gemini-3.8-flash` →
  `openai-codex/gpt-6.1-sol` → `anthropic/claude-opus-5-5` →
  `github-copilot/gpt-6-luna` → `opencode-go/gpt-6-luna`.
- Codex primaries `openai-codex/gpt-6-luna` and `openai-codex/gpt-6.1-sol` →
  `anthropic/claude-opus-5-5` → the same Copilot and OpenCode Go backups.
- Anthropic Sonnet `anthropic/claude-sonnet-5-5` →
  `openai-codex/gpt-6.1-sol` → Opus → the same backups.

These are separate model/provider rules, not an ordered fallback array. The
first rule matching the model or provider and status applies. The exact Opus
rule precedes broad Anthropic rules, and the Gemini-specific Copilot rule
precedes broad Copilot rules; this avoids routing cycles.

Fallback does not change agent pins: UI/UX uses
`opencode/gemini-3.8-flash`; Plan and reviewer use
`anthropic/claude-sonnet-5-5`; Explore and implementer use
`openai-codex/gpt-6-luna`; effect-senior and the default use
`openai-codex/gpt-6.1-sol`.

## Triggers and cooldowns

- Quota/credits: HTTP 402 or 429 uses an 18,000,000 ms (5 hour) cooldown.
- The exact `opencode/gemini-3.8-flash` route also matches HTTP 401. The
  installed parser cannot distinguish a credits error from a bad token in
  `JSON.type=CreditsError`; no other provider has a 401 rule.
- Transient errors 500, 502, 503, 504, and 529 use 600,000 ms (10 minutes).
- Provider reset and `Retry-After` headers override configured cooldowns.

There is no automatic return to the primary model during the same session.
Use `/model-fallback:status` to inspect status and `/model-fallback:reset` to
clear fallback state.

## Updating the managed setup

Edit the managed source, then preview and apply only the runtime config:

```sh
chezmoi diff ~/.pi/agent/model-fallback/config.json
chezmoi apply --exclude scripts ~/.pi/agent/model-fallback/config.json
```

Do not put credentials or runtime state in this repository.

## Verification limits

Static, schema, and model-route checks passed; models were registered, auth
was available, and image input was supported. Live quota balances were not
tested. A reviewer startup 429 was observed without failover or a state record;
the cause is unproven. A child-launch/extension/event trace is needed before
claiming automatic headless subagent failover. This does not establish that
the extension is disabled.

Long Gemini 1m conversations may exceed the Codex fallback's 272k context.
Sonnet and Opus share Anthropic quota: their distinct-model routing avoids
cycles but does not create another quota pool.
