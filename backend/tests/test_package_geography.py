"""Only literal fictional geography facts may form this spatial graphic."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_geography import REFERENCE, bases
from schulpilot.schemas import PackageOutput
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = ("Kontinente und Ozeane\n\nDie Erde hat sieben Kontinente.\n"
          "Europa und Asien liegen auf derselben Landmasse.\n"
          "Der Atlantische Ozean liegt zwischen Amerika und Europa.")


@pytest.mark.parametrize("subject", ["Geographie", "Geografie", "Erdkunde"])
def test_anchored_atlantic_scene_survives_codec_and_real_validation(api, subject):
    payload = payload_for(SOURCE, subject)
    with DB() as db:
        payload["visual_context"]["references"] = visual_references.candidates(db, subject, SOURCE, package_prepared=True)
    schema, binding = bind(payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row["disclosure"] == "given")
    solution = next(row for row in binding.candidates if row["disclosure"] == "solution")
    assert intro["reference"]["id"] == REFERENCE
    assert intro["block"]["labels"] == ["Amerika", "Der Atlantische Ozean", "Europa"]
    assert not binding.question_bound(solution, {"prompt":
        "Die Grafik zeigt den Atlantischen Ozean zwischen Amerika und Europa. Wie viele Kontinente hat die Erde?"})
    assert not binding.question_bound(solution, {"prompt": "Wie viele Kontinente hat die Erde?"})
    assert binding.question_bound(solution, {"prompt":
        "Der Atlantische Ozean liegt zwischen zwei Gebieten. Welches Paar ist es?"})
    questions = [{"id": f"q{i}", "type": "short", "prompt": prompt, "answer": answer,
                  "options": [], "accepted": [], "hints": ["Schau dir die Lage an."],
                  "explanation": SOURCE, "presentation": None, "field_group": None,
                  "explanation_steps": [wire_step(solution)]}
                 for i, (prompt, answer) in enumerate([
                     ("Welches Gebiet liegt laut Quelle neben Europa am Atlantischen Ozean?", "Amerika"),
                     ("Welches Gebiet liegt laut Quelle neben Amerika am Atlantischen Ozean?", "Europa")])]
    output = {"units": [{"group_id": "g1", "subject": subject, "topic": "Ozeane",
        "explanation": SOURCE, "explanation_steps": [wire_step(intro)], "questions": questions}]}
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    result = binding.hydrate(codec.decode(codec.encode(output)))
    result = PackageOutput.model_validate(result).model_dump(mode="json")
    package_part_output.validate(result)
    with DB() as db:
        visual_references.validate_output(db, result, payload)
    assert all(not phase["edges"] for phase in intro["block"]["scene"]["steps"])
    assert intro["block"]["source_excerpt"] in SOURCE
    damaged = copy.deepcopy(intro["block"])
    damaged["labels"][1] = "Pazifik"
    from schulpilot.package_prepared_geography import validate
    from schulpilot.subject_content import Graphic
    with pytest.raises(ValueError):
        validate(Graphic.model_validate(damaged), [SOURCE])


@pytest.mark.parametrize("source", [
    "Der Pazifische Ozean liegt zwischen Amerika und Europa.",
    "Der Atlantische Ozean liegt nicht zwischen Amerika und Europa.",
    "Amerika und Europa sind weit entfernt.",
])
def test_spatial_fact_is_never_invented(source):
    assert not list(bases(source))
