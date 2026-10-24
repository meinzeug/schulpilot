"""Create small transparent header PNGs without changing the generated masters."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
HEADER_SIZE = 256
EXPORTS = (
    ("app/assets/brand/schulpilot-bell-105.png", "app/assets/brand/schulpilot-bell-header.png"),
    ("app/assets/brand/schulpilot-avatar-105.png", "app/assets/brand/schulpilot-avatar-header.png"),
)


def export_header_graphics(root=ROOT):
    root = Path(root)
    prepared = []
    # Validate both inputs before replacing any existing header export.
    for master, relative in EXPORTS:
        with Image.open(root / master) as source:
            if source.format != "PNG" or source.mode != "RGBA":
                raise ValueError("Header masters must be RGBA PNGs with their original transparency.")
            minimum, maximum = source.getchannel("A").getextrema()
            if minimum != 0 or maximum == 0:
                raise ValueError("Header masters must contain both transparent and visible pixels.")
            factor = HEADER_SIZE / max(source.size)
            size = tuple(max(1, round(edge * factor)) for edge in source.size)
            # Fit the complete canvas: no crop, background, colour or alpha edits.
            prepared.append((relative, source.resize(size, Image.Resampling.LANCZOS)))

    exported = []
    for relative, image in prepared:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, optimize=True)
        image.close()
        exported.append(path)
    return exported


def main():
    export_header_graphics()


if __name__ == "__main__":
    main()
