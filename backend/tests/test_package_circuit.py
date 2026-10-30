"""Circuit state is compiled only from explicit synthetic source evidence."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_circuit import REFERENCE, bases, validate
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = ("Der einfache Stromkreis\n\nEin Stromkreis enthält eine Batterie, eine Lampe und\nLeitungen.\n\n"
          "Die Lampe leuchtet, wenn der Stromkreis geschlossen ist.\n\n"
          "Ein geöffneter Schalter unterbricht den Stromkreis.")


def test_exact_open_closed_circuit_survives_real_transport_and_validation(api):
    payload = payload_for(SOURCE, "Physik")
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(db, "Physik", SOURCE, package_prepared=True)
    schema, binding = bind(payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row["disclosure"] == "given" and row["block"]["variant"] == "closed")
    closed = next(row for row in binding.candidates if row["disclosure"] == "solution" and row["block"]["variant"] == "closed")
    opened = next(row for row in binding.candidates if row["disclosure"] == "solution" and row["block"]["variant"] == "open")
    assert intro["reference"]["id"] == REFERENCE
    assert not binding.question_bound(opened, {"prompt": "Der Schalter ist offen. Wie viele Kontinente gibt es?"})
    assert not binding.question_bound(opened, {"prompt": "Was geschieht bei geschlossenem Schalter?"})
    questions = [{"id": f"q{i}", "type": "short", "prompt": prompt, "answer": answer,
                  "options": [], "accepted": [], "hints": ["Sieh dir den Schalter an."],
                  "explanation": SOURCE, "presentation": None, "field_group": None,
                  "explanation_steps": [wire_step(graphic)]}
                 for i, (prompt, answer, graphic) in enumerate([
                     ("Welches Bauteil leuchtet im geschlossenen Stromkreis?", "Lampe", closed),
                     ("Welches Bauteil unterbricht den Stromkreis im geöffneten Zustand?", "Schalter", opened)])]
    output = {"units": [{"group_id": "g1", "subject": "Physik", "topic": "Stromkreis", "explanation": SOURCE,
                         "explanation_steps": [wire_step(intro)], "questions": questions}]}
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    result = binding.hydrate(codec.decode(codec.encode(output)))
    result = PackageOutput.model_validate(result).model_dump(mode="json")
    package_part_output.validate(result)
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    damaged = copy.deepcopy(closed["block"])
    damaged["labels"].append("Motor")
    with pytest.raises(ValueError):
        validate(Graphic.model_validate(damaged), [SOURCE])


@pytest.mark.parametrize("source", [
    SOURCE.replace("geöffneter Schalter", "geschlossener Schalter"),
    SOURCE.replace("Lampe leuchtet", "Lampe leuchtet nicht"),
    SOURCE.replace("eine Batterie", "einen Motor"),
])
def test_missing_or_conflicting_source_does_not_create_a_circuit(source):
    assert not list(bases(source))
