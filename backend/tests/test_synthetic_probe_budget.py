"""A larger operator-approved evaluation budget stays inside isolated tests."""
from dataclasses import replace

from schulpilot import providers


def test_evaluation_budget_is_bounded_and_cannot_expand_production(monkeypatch):
    base = providers.settings
    cases = [
        ("test", "sqlite:////tmp/synthetic.sqlite", 500_000, 500_000),
        ("production", "sqlite:////tmp/synthetic.sqlite", 500_000, 250_000),
        ("test", "postgresql://example/test", 500_000, 250_000),
        ("test", "sqlite:////tmp/synthetic.sqlite", 999_999, 500_000),
        ("test", "sqlite:////tmp/synthetic.sqlite", 1_000, 250_000),
    ]
    for env, url, requested, expected in cases:
        monkeypatch.setattr(providers, "settings", replace(base, environment=env,
            database_url=url, synthetic_test_budget_micros=requested))
        assert providers.synthetic_evaluation_budget() == expected
