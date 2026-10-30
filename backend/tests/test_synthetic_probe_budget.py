"""A larger operator-approved evaluation budget stays inside isolated tests."""
from dataclasses import replace

import pytest
from pydantic import ValidationError
from schulpilot import providers
from schulpilot.model_routing import ModelRoute

from scripts.evaluate_openrouter_mix import ocr_anchor_found


def test_evaluation_budget_is_bounded_and_cannot_expand_production(monkeypatch):
    base = providers.settings
    cases = [
        ("test", "sqlite:////tmp/synthetic.sqlite", 2_000_000, 2_000_000),
        ("production", "sqlite:////tmp/synthetic.sqlite", 2_000_000, 250_000),
        ("test", "postgresql://example/test", 2_000_000, 250_000),
        ("test", "sqlite:////tmp/synthetic.sqlite", 9_999_999, 2_000_000),
        ("test", "sqlite:////tmp/synthetic.sqlite", 1_000, 250_000),
    ]
    for env, url, requested, expected in cases:
        monkeypatch.setattr(providers, "settings", replace(base, environment=env,
            database_url=url, synthetic_test_budget_micros=requested))
        assert providers.synthetic_evaluation_budget() == expected


def test_fraction_anchor_accepts_latex_without_accepting_other_numbers():
    assert ocr_anchor_found("1/5", r"\(\frac{1}{5}+\frac{2}{5}=\frac{3}{5}\)")
    assert ocr_anchor_found("1/5", "1/5 + 2/5 = 3/5")
    assert not ocr_anchor_found("1/5", r"\(\frac{1}{6}\)")


def test_route_reservation_accepts_explicit_increase_but_keeps_bound():
    values = dict(model="openai/gpt-6.1-terra", upstreams=["azure/eu"],
        input_per_million_micros=1_200_000, output_per_million_micros=6_000_000,
        max_output_tokens=8000, reserve_micros=3_617_499, image_capable=True,
        capability_evidence="Synthetic endpoint metadata only", pricing_evidence="Synthetic price metadata only",
        verified_at=1)
    assert ModelRoute.model_validate(values).reserve_micros == 3_617_499
    with pytest.raises(ValidationError):
        ModelRoute.model_validate({**values, "reserve_micros":10_000_001})
