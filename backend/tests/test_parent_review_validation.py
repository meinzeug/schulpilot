"""Synthetic parent-review schema, local rejection and private diagnostics."""

import copy
import itertools
import json

import httpx
import pytest
from schulpilot import parent_insights, providers, worker
from schulpilot.db import DB, Attempt, Job, ParentLearningReview, ProviderConfig, Usage
from sqlalchemy import select
from test_parent_insights import endpoint, finish, request, seed
from test_parent_insights import transport as _transport
from test_providers import configured
from test_tutor import notebook as _notebook


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


@pytest.fixture
def transport(monkeypatch):
    return _transport.__wrapped__(monkeypatch)


def topic(ref="topic:synthetic", counts=(1, 0, 0, 0)):
    return dict(zip(("needs_practice_tasks", "assisted_tasks", "uncertain_tasks", "independent_tasks"), counts)) | {
        "ref": ref, "subject": "Mathematik", "topic": "Künstliches Bruchthema",
    }


def report(ref="topic:synthetic"):
    return {"summary": "Gespeicherte Aufgaben zeigen weiteren Übungsbedarf.",
        "findings": [{"topic_ref": ref, "need": "practice", "interpretation": "Eine Aufgabe gelang noch nicht.",
                      "next_check": "Den nächsten kleinen Schritt erneut prüfen."}],
        "plan": [{"topic_ref": ref, "action": "practice", "purpose": "Eine neue Anwendung versuchen.",
                  "expected_result": "Den nächsten Schritt selbstständig lösen."}]}


def test_schema_permissions_match_local_validator_for_every_evidence_combination():
    topics = [topic(f"topic:{index}", counts) for index, counts in enumerate(itertools.product((0, 1), repeat=4))
              if any(counts)]
    payload = {"topics": topics}
    schema = providers.strict_schema(parent_insights.ReviewOutput, preserve_limits=True)
    parent_insights.bind_schema(schema, payload)
    providers.prune_schema(schema)
    assert schema["properties"]["findings"]["maxItems"] == 6
    assert "Finding" not in schema.get("$defs", {})
    assert "PlanStep" not in schema.get("$defs", {})
    for observed in topics:
        for field, category in (("findings", "need"), ("plan", "action")):
            matching = [branch for branch in schema["properties"][field]["items"]["anyOf"]
                        if observed["ref"] in branch["properties"]["topic_ref"]["enum"]]
            assert len(matching) == 1
            branch = matching[0]
            assert branch["additionalProperties"] is False
            if field == "findings":
                expected = tuple(need for need, counter in (
                    ("practice", "needs_practice_tasks"), ("support", "assisted_tasks"),
                    ("assessment_open", "uncertain_tasks"), ("independent_success", "independent_tasks"),
                ) if observed[counter])
                for need in ("practice", "support", "assessment_open", "independent_success"):
                    value = report(observed["ref"])
                    value["findings"][0]["need"] = need
                    if need in expected:
                        assert parent_insights.validate(value, payload)
                    else:
                        with pytest.raises(parent_insights.ReviewValidationError, match="unsupported_finding"):
                            parent_insights.validate(value, payload)
                assert branch["properties"][category]["enum"] == list(expected)
            else:
                expected = {"explain", "practice", "recall", "check_understanding"}
                if observed["uncertain_tasks"]:
                    expected.add("clarify_assessment")
                assert set(branch["properties"][category]["enum"]) == expected


def test_parent_prompt_and_bound_schema_reach_real_adapter_without_extra_calls(api, household, monkeypatch):
    parent, _ = household
    configured(parent["families"][0]["id"])
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.provider = "openrouter"
    config.openrouter_free_only = False
    config.capability_evidence = "synthetic transport; upstream=fixture-upstream"
    payload = {"parent_review": True, "strategy_version": parent_insights.VERSION, "topics": [topic()]}
    calls = []
    output = json.dumps(report())

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, headers, json):
            calls.append(json)
            return httpx.Response(200, json={"choices": [{"finish_reason": "stop",
                "message": {"content": output}}],
                "usage": {"prompt_tokens": 100, "completion_tokens": 150, "cost": 0.000037}})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    result = providers.request_provider(config, "decision", payload)
    assert parent_insights.validate(result.data, payload)
    assert len(calls) == 1
    sent = calls[0]
    assert sent["messages"][0]["content"] == parent_insights.RULES
    schema = sent["response_format"]["json_schema"]["schema"]
    finding = schema["properties"]["findings"]["items"]["anyOf"][0]
    assert finding["properties"]["topic_ref"]["enum"] == ["topic:synthetic"]
    assert finding["properties"]["need"]["enum"] == ["practice"]
    assert schema["properties"]["findings"]["maxItems"] == 1
    assert "clarify_assessment" not in schema["properties"]["plan"]["items"]["anyOf"][0]["properties"]["action"]["enum"]
    assert sent["provider"]["only"] == ["fixture-upstream"]
    assert sent["provider"]["data_collection"] == "deny"
    assert sent["provider"]["allow_fallbacks"] is False


@pytest.mark.parametrize("reason", sorted(parent_insights.ReviewValidationError.REASONS))
def test_local_rejection_records_only_finite_reason_and_retains_answers_and_costs(api, book, transport, reason):
    seed(book)
    if reason == "no_open_assessment":
        with DB.begin() as db:
            for attempt in db.scalars(select(Attempt).where(Attempt.outcome == "uncertain")):
                attempt.outcome = "incorrect"

    def damage(out):
        if reason == "schema_mismatch":
            out["private-unexpected-key"] = "PRIVATE-PROVIDER-CONTENT"
        elif reason == "repeated_topic":
            out["findings"].append(copy.deepcopy(out["findings"][0]))
        elif reason == "unknown_topic":
            out["plan"][0]["topic_ref"] = "PRIVATE-FOREIGN-ID"
        elif reason == "unsupported_finding":
            out["findings"][0]["need"] = "independent_success"
        elif reason == "no_open_assessment":
            out["plan"][0]["action"] = "clarify_assessment"
        elif reason == "unexpected_exercise":
            out["summary"] = "Aufgabe 1: PRIVATE-PROVIDER-CONTENT"
        else:
            out["summary"] = "https://example.invalid/PRIVATE-PROVIDER-CONTENT"

    transport["invalid"] = damage
    started = request(api, book)
    assert started.status_code == 202
    finish()
    with DB() as db:
        row = db.get(ParentLearningReview, started.json()["id"])
        job = db.get(Job, row.job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        assert row.status == job.status == "failed" and row.report is None
        assert job.error_code == "invalid_output" and job.attempts == 1
        assert usage.cost_micros == 37
        assert usage.telemetry == {"validation_reason": reason}
        assert "PRIVATE" not in json.dumps([usage.telemetry, row.error, job.error])
        assert len(list(db.scalars(select(Attempt)))) == 3
        assert all(a.answer == "PRIVATE-SYNTHETIC-ANSWER" for a in db.scalars(select(Attempt)))
        assert worker.claim(db) is None
    assert len(transport["calls"]) == 1
    assert api.get(endpoint(book)).json()["latest_attempt"]["status"] == "failed"

