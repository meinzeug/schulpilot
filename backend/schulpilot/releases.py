import json
from pathlib import Path

from fastapi import APIRouter

from .config import settings

router = APIRouter(tags=["Android-Download"])


@router.get("/app-release")
def android_release():
    manifest = Path(__file__).resolve().parents[2] / "android-release.json"
    if not manifest.is_file():
        return {"available": False}
    data = json.loads(manifest.read_text())
    return {
        "available": True,
        **data,
        "download_url": settings.public_url + "/downloads/schulpilot-android.apk?v=" + data["sha256"][:16],
    }
