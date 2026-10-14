"""Deterministically size the generated master for Flutter, web and Android."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = (234, 248, 255, 255)


def main():
    master = Image.open(ROOT / "design/brand/schulpilot-master.png").convert("RGBA")
    mark = master.crop(master.getchannel("A").getbbox())

    def save(path, size, fraction=1, background=(0, 0, 0, 0)):
        canvas = Image.new("RGBA", (size, size), background)
        icon = mark.copy()
        icon.thumbnail((round(size * fraction), round(size * fraction)), Image.Resampling.LANCZOS)
        canvas.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
        path = ROOT / path
        path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(path, optimize=True)

    save("app/assets/brand/schulpilot-mark.png", 512)
    save("app/web/brand.png", 512)
    save("app/web/favicon.png", 64, .82, BACKGROUND)
    for size in (192, 512):
        save(f"app/web/icons/icon-{size}.png", size, .78, BACKGROUND)
        save(f"app/web/icons/maskable-{size}.png", size, .64, BACKGROUND)
    res = "app/android/app/src/main/res"
    save(f"{res}/drawable-nodpi/schulpilot_foreground.png", 1080, .50)
    save(f"{res}/drawable-nodpi/schulpilot_logo.png", 512, .84)
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(f"{res}/mipmap-{density}/ic_launcher.png", size, .78, BACKGROUND)
    save("design/brand/play-store-icon.png", 512, .78, BACKGROUND)


if __name__ == "__main__":
    main()
