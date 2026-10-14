import io

from PIL import Image
from schulpilot.evaluation_corpus import CASES
from schulpilot.fixtures import trusted_payload, worksheet


def test_versioned_benchmark_has_distinct_images_and_only_trusted_content():
    images = []
    for case_id, case in CASES.items():
        image = worksheet(case_id)
        with Image.open(io.BytesIO(image)) as photo:
            assert photo.size == (1120, 760) and not photo.getexif()
        payload = trusted_payload("unit", case_id)
        assert payload["material"]["content"] == "\n".join(case["lines"])
        assert payload["grade"] == case["grade"]
        images.append(image)
    assert len(set(images)) == len(CASES) == 8
