"""Technical brand exports preserve their original; no generated content or IO beyond local PNGs."""

import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

import pytest
from PIL import Image

from scripts.export_brand import (
    BACKGROUND,
    EXPORTS,
    MASTER,
    STARTUP_EXPORTS,
    STARTUP_MASTER,
    TRANSPARENT,
    export_brand,
)

ROOT = Path(__file__).resolve().parents[2]


def master_at(root):
    for relative, colour in [(MASTER, (35, 150, 220, 255)), (STARTUP_MASTER, (180, 60, 210, 255))]:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        source = Image.new("RGBA", (640, 480), colour)
        source.putpixel((0, 0), (*colour[:3], 0))
        source.save(path)
    return root / MASTER


def test_export_preserves_original_bytes_alpha_and_full_canvas_proportions(tmp_path):
    source = master_at(tmp_path)
    before = source.read_bytes()
    startup_before = (tmp_path / STARTUP_MASTER).read_bytes()
    with Image.open(source) as image:
        before_alpha = image.getchannel("A").tobytes()
    paths = export_brand(tmp_path)
    assert len(paths) == len(EXPORTS) == 17
    assert source.read_bytes() == before
    assert (tmp_path / STARTUP_MASTER).read_bytes() == startup_before
    with Image.open(source) as image:
        assert image.getchannel("A").tobytes() == before_alpha
    for relative, size, _, background in EXPORTS:
        with Image.open(tmp_path / relative) as image:
            assert image.size == (size, size) and image.mode == "RGBA"
            if background == TRANSPARENT:
                assert image.getchannel("A").getextrema() == (0, 255)
            else:
                assert image.getchannel("A").getextrema() == (255, 255)
                assert image.getpixel((0, 0)) == BACKGROUND
    # The non-square original is fitted as a whole; never cropped or stretched.
    with Image.open(tmp_path / "app/web/brand.png") as image:
        assert image.getchannel("A").getbbox() == (0, 64, 512, 448)
    first = {path.relative_to(tmp_path): hashlib.sha256(path.read_bytes()).digest() for path in paths}
    second = {path.relative_to(tmp_path): hashlib.sha256(path.read_bytes()).digest() for path in export_brand(tmp_path)}
    assert first == second


@pytest.mark.parametrize("master", [MASTER, STARTUP_MASTER])
@pytest.mark.parametrize("alpha", [0, 255])
def test_invalid_master_does_not_partially_replace_exports(tmp_path, alpha, master):
    master_at(tmp_path)
    source = tmp_path / master
    Image.new("RGBA", (32, 32), (35, 150, 220, alpha)).save(source)
    with pytest.raises(ValueError, match="transparent and visible"):
        export_brand(tmp_path)
    assert not (tmp_path / "app/web/brand.png").exists()


def test_header_and_installable_icons_use_head_while_startup_targets_use_full_robot(tmp_path):
    master_at(tmp_path)
    export_brand(tmp_path)
    assert STARTUP_EXPORTS == {
        "app/web/brand.png",
        "app/assets/brand/schulpilot-startup.png",
        "app/android/app/src/main/res/drawable-nodpi/schulpilot_logo.png",
        "app/android/app/src/main/res/drawable-nodpi/schulpilot_splash_logo.png",
    }
    for relative, size, _, _ in EXPORTS:
        with Image.open(tmp_path / relative) as image:
            expected = (180, 60, 210, 255) if relative in STARTUP_EXPORTS else (35, 150, 220, 255)
            assert image.getpixel((size // 2, size // 2)) == expected


def test_platform_masks_keep_complete_foreground_inside_safe_circles(tmp_path):
    master_at(tmp_path)
    export_brand(tmp_path)
    for path, fraction in [
        ("app/web/icons/maskable-192.png", 0.8),
        ("app/web/icons/maskable-512.png", 0.8),
        ("app/android/app/src/main/res/drawable-nodpi/schulpilot_splash_logo.png", 2 / 3),
    ]:
        with Image.open(tmp_path / path) as image:
            size = image.width
            foreground = [
                (x, y)
                for y in range(size)
                for x in range(size)
                if image.getpixel((x, y))[3] > 0 and image.getpixel((x, y)) != BACKGROUND
            ]
            assert foreground
            radius = size * fraction / 2
            centre = (size - 1) / 2
            assert all((x - centre) ** 2 + (y - centre) ** 2 <= radius**2 for x, y in foreground)


class StartupParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))


def test_web_startup_keeps_local_role_safe_entry_and_accessible_loading_fallbacks():
    text = (ROOT / "app/web/index.html").read_text()
    parser = StartupParser()
    parser.feed(text)
    logo = next(attrs for tag, attrs in parser.tags if tag == "a" and attrs.get("class") == "brand-home")
    assert logo["href"] == "/app" and logo["aria-label"]
    assert any(tag == "h1" for tag, _ in parser.tags)
    assert "Dein Lernraum wird geladen …" in text and "Bitte JavaScript aktivieren" in text
    assert "Heftseiten fotografieren. Stoff verstehen. Gemeinsam weiterlernen." in text
    assert "prefers-reduced-motion:reduce" in text and "animation:none" in text
    assert "#101E24" in text and "background:transparent" in text
    assert "infinite" not in text and "http://" not in text and "https://" not in text
    assert {attrs.get("src") for tag, attrs in parser.tags if tag == "script"} == {
        "push_bootstrap.js",
        "flutter_bootstrap.js",
    }
    manifest = json.loads((ROOT / "app/web/manifest.json").read_text())
    assert manifest["background_color"].lower() == manifest["theme_color"].lower() == "#101e24"
    assert "#" + bytes(BACKGROUND[:3]).hex() == manifest["theme_color"].lower()
    outputs = {relative for relative, *_ in EXPORTS}
    assert all("app/web/" + icon["src"] in outputs for icon in manifest["icons"])


def test_startup_sheet_has_eight_equal_uv_cells_with_complete_transparent_figures():
    path = ROOT / "app/assets/brand/schulpilot-startup-frames-105.png"
    with Image.open(path) as image:
        assert image.format == "PNG" and image.mode == "RGBA"
        assert image.width == image.height * 2
        assert image.getchannel("A").getextrema() == (0, 255)
        # Fractional equal UV cells are intentional; artwork has clear margins,
        # so a half-pixel source boundary cannot clip or leak another figure.
        for row in range(2):
            for column in range(4):
                bounds = (
                    column * image.width // 4,
                    row * image.height // 2,
                    (column + 1) * image.width // 4,
                    (row + 1) * image.height // 2,
                )
                cell = image.crop(bounds)
                alpha = cell.getchannel("A")
                box = alpha.point(lambda value: 255 if value >= 32 else 0).getbbox()
                assert box is not None
                assert 0 < box[0] < box[2] < cell.width
                assert 0 < box[1] < box[3] < cell.height
                assert alpha.histogram()[0] > 0
