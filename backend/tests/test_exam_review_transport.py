"""Pure synthetic transport bounds; no database, provider or saved-report rewrite."""

import copy

import pytest
from schulpilot import exam_review_transport as compact
from schulpilot.exam_review_schemas import ExamReviewOutput


def report(count=1):
    return {
        "summary": "Ein kleiner KI-Auszug, keine vollständige Auswertung.",
        "uncertainties": [],
        "tasks": [
            {
                "id": f"task_{index}",
                "question": "Setze das Verb ein: Mira ... a book.",
                "original_answer": "read",
                "teacher_feedback": "Dritte Person Singular beachten.",
                "score_label": "0 von 1",
                "ai_proposal": "Vergleiche die Verbform mit deiner bestätigten Regel.",
                "uncertainties": [],
                "sources": [{"ref": "p1", "quote": "Mira ... a book."}],
            }
            for index in range(count)
        ],
    }


@pytest.mark.parametrize("tokens,expected", [(1000, 2), (2600, 2), (4000, 2), (6000, 2), (7999, 2), (8000, 4)])
def test_request_schema_and_post_parse_limits_match(tokens, expected):
    schema = ExamReviewOutput.model_json_schema()
    before = copy.deepcopy(schema)
    assert compact.bind_schema(schema, tokens) is schema
    assert schema["properties"]["tasks"]["maxItems"] == expected
    assert schema["properties"]["summary"]["maxLength"] == 320
    fields = schema["$defs"]["ReviewTask"]["properties"]
    assert fields["ai_proposal"]["maxLength"] == 240
    assert fields["sources"]["maxItems"] == 2
    for key in ("question", "original_answer", "teacher_feedback", "score_label"):
        assert fields[key] == before["$defs"]["ReviewTask"]["properties"][key]
    assert schema["$defs"]["ReviewCitation"] == before["$defs"]["ReviewCitation"]
    value = report(expected)
    assert compact.validate_bounds(value, tokens) is value
    with pytest.raises(ValueError, match="kompakten Ausgaberahmen"):
        compact.validate_bounds(report(expected + 1), tokens)


@pytest.mark.parametrize("tokens", [True, None, "4000", 0, -1, 8001, float("inf")])
def test_unknown_or_unbounded_token_argument_is_not_silently_relaxed(tokens):
    with pytest.raises(ValueError, match="Ausgabebegrenzung"):
        compact.task_limit(tokens)


def test_binding_never_changes_the_persisted_output_contract():
    schema = ExamReviewOutput.model_json_schema()
    compact.bind_schema(schema, 4000)
    stored_contract = ExamReviewOutput.model_json_schema()
    assert stored_contract["properties"]["tasks"]["maxItems"] == 8
    assert stored_contract["$defs"]["ReviewTask"]["properties"]["ai_proposal"]["maxLength"] == 1000
    # Larger historical reports stay readable under their original model.
    assert len(ExamReviewOutput.model_validate(report(8)).tasks) == 8


@pytest.mark.parametrize("field,bound", [("question", 1600), ("original_answer", 1600), ("teacher_feedback", 1600), ("score_label", 160)])
def test_literal_original_fields_are_returned_intact_without_elision(field, bound):
    value = report()
    literal = "Ü🙂" * (bound // 2)
    value["tasks"][0][field] = literal
    before = copy.deepcopy(value)
    assert compact.validate_bounds(value, 4000) == before
    assert value["tasks"][0][field] == literal
    assert "..." not in value["tasks"][0][field]
    assert "…" not in value["tasks"][0][field]


@pytest.mark.parametrize("change", ["summary", "proposal", "sources", "global_uncertainties", "task_uncertainties", "uncertainty_length"])
def test_new_oversize_output_is_rejected_without_truncating_or_mutating(change):
    value = report()
    if change == "summary":
        value["summary"] = "x" * 321
    elif change == "proposal":
        value["tasks"][0]["ai_proposal"] = "x" * 241
    elif change == "sources":
        value["tasks"][0]["sources"] *= 3
    elif change == "global_uncertainties":
        value["uncertainties"] = ["offen"] * 3
    elif change == "task_uncertainties":
        value["tasks"][0]["uncertainties"] = ["offen"] * 3
    else:
        value["uncertainties"] = ["x" * 161]
    before = copy.deepcopy(value)
    with pytest.raises(ValueError, match="kompakten Ausgaberahmen"):
        compact.validate_bounds(value, 4000)
    assert value == before


def test_unicode_counts_match_backend_scalars_and_empty_extract_stays_honest():
    value = report()
    value["summary"] = "🙂" * 320
    value["tasks"][0]["ai_proposal"] = "🙂" * 240
    value["uncertainties"] = ["🙂" * 160]
    assert compact.validate_bounds(value, 4000) is value
    empty = {"summary": "Kein sicherer weiterer Ausschnitt.", "uncertainties": ["Aufgabe nicht sicher zuzuordnen."], "tasks": []}
    assert compact.validate_bounds(empty, 4000) is empty
    ExamReviewOutput.model_validate(empty)


def test_rules_are_bounded_and_keep_original_source_and_explicit_append_requirements():
    text = compact.rules(4000)
    assert "höchstens 2 neue" in text
    assert "vollständig und wörtlich" in text
    assert "niemals kürzen" in text
    assert "Unsicherheit nicht verschweigen" in text
    assert "ausdrücklich angefordert" in text
    assert "keinen automatischen Wiederholungsversuch" in text
    assert "höchstens 4 neue" in compact.rules(8000)


def test_non_analysis_schema_is_not_silently_mutated():
    with pytest.raises(ValueError, match="Ausgabeschema"):
        compact.bind_schema({"properties": {}}, 4000)


@pytest.mark.parametrize("value", [None, [], {}, {"summary": "s", "tasks": [None], "uncertainties": []}])
def test_malformed_reply_does_not_escape_the_compact_transport_guard(value):
    with pytest.raises(ValueError, match="kompakten Ausgaberahmen"):
        compact.validate_bounds(value, 4000)


def test_grouped_assignment_rules_keep_readable_literal_rows_independent_and_roles_explicit():
    text = compact.rules(4000)
    assert "WÖRTLICHE vollständige Teilzeile" in text
    assert "Überschrift bleibt Kontext" in text
    assert "hänge sie nicht an question an" in text
    assert "Unklare Nachbarzeilen" in text
    assert "ohne eine Mindestzahl" in text
    assert "keine Verbform korrigieren" in text
    assert "teacher_feedback leer" in text
    assert "kein Rollenbeleg" in text
    assert "Punktzahl selbst berechnen" in text
