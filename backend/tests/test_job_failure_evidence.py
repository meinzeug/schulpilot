"""Failures must distinguish missing evidence from a busy provider."""

from schulpilot.job_failures import message_code
from schulpilot.providers import ProviderError


def test_unbacked_answer_is_not_a_busy_provider():
    text = "Eine kurze Sachantwort ist nicht im bestätigten Material belegt. Das Paket wurde nicht übernommen."
    assert message_code(text) == "invalid_output"
    assert ProviderError(text).code == "invalid_output"


def test_only_actual_busy_worker_message_is_classified_as_busy():
    assert message_code("Der Codex-Worker ist gerade belegt. Bitte später versuchen.") == "provider_busy"
    assert message_code("Die KI ist beschäftigt.") == "provider_busy"
    assert message_code("Diese Stufe ist für dieses Fach nicht im Katalog belegt.") != "provider_busy"
