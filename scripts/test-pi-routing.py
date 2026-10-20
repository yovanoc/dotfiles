#!/usr/bin/env python3
"""Offline invariants for managed routing; never calls a model."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
agent = root / "home/private_dot_pi/private_agent"
settings = json.loads((agent / "settings.json").read_text())
config = json.loads((agent / "private_model-fallback/config.json").read_text())
assert (settings["defaultProvider"], settings["defaultModel"], settings["defaultThinkingLevel"]) == (
    "openai", "gpt-6.1-sol", "medium"
)
assert config["version"] == 1 and config["enabled"] and config["autoRetry"] is False
rules = config["rules"]
assert len({r["name"] for r in rules}) == len(rules)
for rule in rules:
    assert rule["statuses"] and rule["cooldownMs"] > 0
    assert rule["fallback"]["provider"] not in ("anthropic-api", "opencode")
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
        assert result is not None and result["provider"] != "anthropic-api"
assert target("anthropic-api", "claude-sonnet-5-5", 400) is None
print("Pi routing invariants passed")
