"""Small local header exports retain original bytes, alpha and full proportions."""

import hashlib
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

from scripts.export_header_graphics import EXPORTS, HEADER_SIZE, export_header_graphics

ROOT = Path(__file__).resolve().parents[2]


def masters_at(root):
    paths = []
    for (master, _), size in zip(EXPORTS, [(640, 480), (480, 640)], strict=True):
        path = root / master
        path.parent.mkdir(parents=True, exist_ok=True)
        image = Image.new("RGBA", size, (35, 150, 220, 0))
        ImageDraw.Draw(image).rectangle((40, 40, size[0] - 41, size[1] - 41), fill=(35, 150, 220, 255))
        image.putpixel((size[0] // 2, size[1] // 2), (110, 80, 230, 128))
        image.save(path)
        paths.append(path)
    return paths


def test_header_exports_preserve_masters_proportions_alpha_and_repeatable_pixels(tmp_path):
    masters = masters_at(tmp_path)
    before = {path: path.read_bytes() for path in masters}
    paths = export_header_graphics(tmp_path)
    assert len(paths) == len(EXPORTS) == 2
    for (master, relative), size in zip(EXPORTS, [(256, 192), (192, 256)], strict=True):
        with Image.open(tmp_path / master) as source, Image.open(tmp_path / relative) as output:
            assert output.format == "PNG" and output.mode == "RGBA" and output.size == size
            assert output.getchannel("A").getextrema() == (0, 255)
            assert output.tobytes() == source.resize(size, Image.Resampling.LANCZOS).tobytes()
    assert {path: path.read_bytes() for path in masters} == before
    digests = {path: hashlib.sha256(path.read_bytes()).digest() for path in paths}
    assert export_header_graphics(tmp_path) == paths
    assert {path: hashlib.sha256(path.read_bytes()).digest() for path in paths} == digests
    assert {path: path.read_bytes() for path in masters} == before


@pytest.mark.parametrize("kind", ["rgb", "opaque", "invisible"])
def test_invalid_second_master_preserves_both_previous_exports(tmp_path, kind):
    masters = masters_at(tmp_path)
    mode = "RGB" if kind == "rgb" else "RGBA"
    colour = (30, 100, 220) if kind == "rgb" else (30, 100, 220, 255 if kind == "opaque" else 0)
    Image.new(mode, (32, 32), colour).save(masters[1])
    for _, relative in EXPORTS:
        (tmp_path / relative).write_bytes(b"previous export")
    before = {path: path.read_bytes() for path in masters}
    with pytest.raises(ValueError, match="RGBA PNG|transparent and visible"):
        export_header_graphics(tmp_path)
    assert {path: path.read_bytes() for path in masters} == before
    assert all((tmp_path / relative).read_bytes() == b"previous export" for _, relative in EXPORTS)


def test_committed_header_pngs_match_frozen_master_pixels_and_are_small():
    for master, relative in EXPORTS:
        path = ROOT / relative
        with Image.open(ROOT / master) as source, Image.open(path) as output:
            assert output.format == "PNG" and output.mode == "RGBA"
            assert output.size == (HEADER_SIZE, HEADER_SIZE)
            assert output.getchannel("A").getextrema() == (0, 255)
            assert output.tobytes() == source.resize(output.size, Image.Resampling.LANCZOS).tobytes()
            assert path.stat().st_size < (ROOT / master).stat().st_size / 5
