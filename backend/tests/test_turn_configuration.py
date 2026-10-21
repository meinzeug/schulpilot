"""Regression for coturn's all-zero/unbounded ACL semantics; no network."""
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("turn_install", Path(__file__).resolve().parents[2] / "deploy/install_turn.py")
turn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(turn)


@pytest.mark.parametrize("invalid", ["::", "0.0.0.0", "::-::", "0.0.0.0-0.0.0.0"])
def test_unspecified_coturn_range_cannot_accidentally_deny_every_peer(monkeypatch, invalid):
    monkeypatch.setattr(turn, "DENIED", [*turn.DENIED, invalid])
    with pytest.raises(ValueError, match="unspecified TURN deny range"):
        turn.configuration("192.0.2.1", "synthetic-secret")


def test_fixed_configuration_keeps_private_targets_denied_and_requires_authentication():
    rendered = turn.configuration("192.0.2.1", "synthetic-secret")
    assert "denied-peer-ip=::\n" not in rendered
    assert "denied-peer-ip=10.0.0.0-10.255.255.255\n" in rendered
    assert "denied-peer-ip=169.254.0.0-169.254.255.255\n" in rendered
    assert "denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff\n" in rendered
    assert "use-auth-secret\n" in rendered and "static-auth-secret=synthetic-secret\n" in rendered
    assert "allow-loopback-peers" not in rendered and "no-auth" not in rendered
