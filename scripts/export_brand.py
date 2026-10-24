"""Resize the untouched generated brand source for Flutter, web and Android."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = Path("app/assets/brand/schulpilot-ai-105.png")
STARTUP_MASTER = Path("app/assets/brand/schulpilot-startup-105.png")
STARTUP_EXPORTS = frozenset(
    {
        "app/web/brand.png",
        "app/assets/brand/schulpilot-startup.png",
        "app/android/app/src/main/res/drawable-nodpi/schulpilot_logo.png",
        "app/android/app/src/main/res/drawable-nodpi/schulpilot_splash_logo.png",
    }
)
TRANSPARENT = (0, 0, 0, 0)
BACKGROUND = (16, 30, 36, 255)

# Fractions describe a proportional fit of the complete source canvas. No
# cropping, recolouring, alpha cleanup or changes to the original are applied.
EXPORTS = (
    ("app/assets/brand/schulpilot-mark.png", 512, 1, TRANSPARENT),
    ("app/web/brand.png", 512, 1, TRANSPARENT),
    ("app/assets/brand/schulpilot-startup.png", 512, 1, TRANSPARENT),
    ("app/web/favicon.png", 64, 0.82, TRANSPARENT),
    ("app/web/icons/icon-192.png", 192, 0.78, BACKGROUND),
    ("app/web/icons/icon-512.png", 512, 0.78, BACKGROUND),
    # A square of this size fits entirely in the central 80% safe circle.
    ("app/web/icons/maskable-192.png", 192, 0.56, BACKGROUND),
    ("app/web/icons/maskable-512.png", 512, 0.56, BACKGROUND),
    ("app/android/app/src/main/res/drawable-nodpi/schulpilot_foreground.png", 1080, 0.50, TRANSPARENT),
    ("app/android/app/src/main/res/drawable-nodpi/schulpilot_logo.png", 512, 0.84, TRANSPARENT),
    # Android 12's system splash mask has a central two-thirds safe circle.
    ("app/android/app/src/main/res/drawable-nodpi/schulpilot_splash_logo.png", 512, 0.44, TRANSPARENT),
    ("app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png", 48, 0.78, BACKGROUND),
    ("app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png", 72, 0.78, BACKGROUND),
    ("app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", 96, 0.78, BACKGROUND),
    ("app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", 144, 0.78, BACKGROUND),
    ("app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", 192, 0.78, BACKGROUND),
    ("design/brand/play-store-icon.png", 512, 0.78, BACKGROUND),
)


def export_brand(root=ROOT):
    root = Path(root)
    marks = {}
    # Both originals are checked before any existing platform PNG is replaced.
    for master in (MASTER, STARTUP_MASTER):
        with Image.open(root / master) as source:
            if source.format != "PNG" or source.mode != "RGBA":
                raise ValueError("The brand master must be an RGBA PNG with its original transparency.")
            mark = source.copy()
        minimum, maximum = mark.getchannel("A").getextrema()
        if minimum != 0 or maximum == 0:
            raise ValueError("The brand master must contain both transparent and visible pixels.")
        marks[master] = mark

    exported = []
    for relative, size, fraction, background in EXPORTS:
        canvas = Image.new("RGBA", (size, size), background)
        master = STARTUP_MASTER if relative in STARTUP_EXPORTS else MASTER
        icon = marks[master].copy()
        icon.thumbnail((round(size * fraction), round(size * fraction)), Image.Resampling.LANCZOS)
        canvas.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(path, optimize=True)
        exported.append(path)
    return exported


def main():
    export_brand()


if __name__ == "__main__":
    main()
