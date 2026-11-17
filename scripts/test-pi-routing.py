#!/usr/bin/env python3
"""Offline invariants for managed routing; never calls a model."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
agent = root / "home/private_dot_pi/private_agent"
settings = json.loads((agent / "settings.json").read_text())
config = json.loads((agent / "private_model-fallback/config.json").read_text())
assert (settings["defaultProvider"], settings["defaultModel"], settings["defaultThinkingLevel"]) == (
    "anthropic", "claude-opus-5-5", "medium"
)
assert config["version"] == 1 and config["enabled"] and config["autoRetry"] is False
rules = config["rules"]
assert len({r["name"] for r in rules}) == len(rules)
API_FALLBACK_MODELS = ("claude-sonnet-5-5", "claude-haiku-5-5")
API_FALLBACK_RULES = ("anthropic-sonnet-quota-or-auth", "anthropic-haiku-quota-or-auth")
names = [r["name"] for r in rules]
assert all(name in names and names.index(name) < names.index("anthropic-quota-or-auth") for name in API_FALLBACK_RULES)
for rule in rules:
    assert rule["statuses"] and rule["cooldownMs"] > 0
    fallback = rule["fallback"]
    if fallback["provider"] == "anthropic-api":
        # Only same-model quota/auth fallback from the matching Anthropic model is approved.
        assert rule["name"] in API_FALLBACK_RULES and fallback["model"] in API_FALLBACK_MODELS
        assert rule.get("matchModels") == [{"provider": "anthropic", "model": fallback["model"]}]
        assert set(rule["statuses"]) <= {401, 402, 429}
    else:
        assert fallback["provider"] != "opencode"
    assert "contributor" not in rule["fallback"]["model"]
    assert 400 not in rule["statuses"]  # unrelated bad requests must not cause spending elsewhere

def target(provider, model, status):
    for rule in rules:
        if status not in rule["statuses"]:
            continue
        if provider in rule.get("matchProviders", []) or {"provider": provider, "model": model} in rule.get("matchModels", []):
            return rule["fallback"]
    return None

for status in (401, 402, 429, 500, 502, 503, 504, 529):
    for model in ("kimi-k3", "claude-haiku-5-5", "gpt-6-luna"):
        assert target("opencode-go", model, status) == {"provider": "github-copilot", "model": "gpt-6-luna"}
    assert target("github-copilot", "gpt-6-luna", status) == {"provider": "openai", "model": "gpt-6-luna"}
    assert target("openai", "gpt-6-luna", status) == {"provider": "anthropic", "model": "claude-sonnet-5-5"}
    for model in ("claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"):
        result = target("anthropic", model, status)
        assert result is not None
        if status in (401, 402, 429) and model in API_FALLBACK_MODELS:
            assert result == {"provider": "anthropic-api", "model": model}
        else:
            assert result["provider"] != "anthropic-api"
assert target("anthropic-api", "claude-sonnet-5-5", 400) is None
terra_id = "openai/gpt-6.1-terra"
assert terra_id in settings["enabledModels"]
assert "openai/gpt-6.2-sol" in settings["enabledModels"]
assert "openai/gpt-6.2-astra" in settings["enabledModels"]
assert "openai/gpt-6.1-sol" not in settings["enabledModels"]
assert "openai/gpt-6-astra" not in settings["enabledModels"]
assert all(
    r["fallback"] == {"provider": "openai", "model": "gpt-6.2-sol"}
    for r in rules
    if r["name"].startswith(("anthropic-quota-or-auth", "anthropic-transient", "anthropic-api-"))
)
models = json.loads((agent / "private_models.json").read_text())
# Native OpenAI metadata and authentication belong to Pi, not managed overrides.
assert "openai" not in models["providers"]
policy = (agent / "private_docs/coordinator.md").read_text()
routing = (agent / "private_docs/coordinator-routing.md").read_text()
root_policy = policy.split("## Dispatch", 1)[0]
assert "Workers prepare packets" in root_policy
assert "delegates" in root_policy and "substantive verification" in root_policy
assert "independent verification" in root_policy and "bounded parallel packets" in root_policy
assert "coordinator-routing.md" in policy
dispatch = " ".join(policy.split("## Dispatch", 1)[1].split("## Routing reference", 1)[0].split())
assert all(term in dispatch for term in ("task graph ledger", "dependency IDs", "exact ownership", "`ready`", "`running`", "`blocked`", "`done`", "worker ID", "concrete blocker"))
assert "each worker completion" in dispatch and "completion suffices to refill one eligible slot" in dispatch
assert "four completions accumulate" in dispatch and "up to four eligible slots" in dispatch and "never wait for four" in dispatch
assert "required evidence is accepted" in dispatch and "not ready-task coverage" in dispatch
assert all(x in dispatch for x in ("fast_task_ready({task_ids})", "fast_task_dispatch({task_ids, capacity: {source: \"coordinator-ledger\", active}})", "metadata.fastTask", "schemaVersion: 1", "ownedPaths", "dependencies", "grants", "prewritten packet", "loaded and approved", "not measured native occupancy"))
assert "shared caps" in dispatch and "pins and ownership" in dispatch
completion = " ".join(policy.split("## Completion, recovery and budgets", 1)[1].split("## Conditional reference", 1)[0].split())
assert "recompute readiness and refill again after acceptance" in completion
assert "name its actual blockers instead of declaring it done" in completion
sol_policy = routing.split("Sol is an exception", 1)[1].split("Use each route's", 1)[0]
assert "fresh explicit Sol worker dispatch" in sol_policy and "MODEL RATIONALE:" in sol_policy
assert "prior verified lighter-route" in sol_policy and "no suitable eligible alternative" in sol_policy
assert "qualification-only" not in routing
for task in ("Concise writing or revision from supplied material", "Scoped code fixes with clear inputs", "Defined visual/computer tasks"):
    row = next(line for line in routing.splitlines() if line.startswith("| " + task))
    assert "`openai/gpt-6.1-terra` `medium` → `openai/gpt-6.2-sol` `medium`" in row
assert "verified acceptance miss" in routing
assert "API estimates are not ChatGPT credit-debit rates" in routing
assert "Reserve" in routing and "Full" in routing
assert '"refresh":true' in routing and "60 seconds" in routing and "original `capturedAt`" in routing
assert "failed refresh" in routing and "each ready batch; reuse it only within that batch" not in routing
assert "absent from the bundled Go catalog" in routing
print("Pi routing invariants passed")
