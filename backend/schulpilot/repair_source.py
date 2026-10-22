"""Pure allowlist source transport shared with the isolated repair broker.

No repository discovery, secrets, runtime data, Git or provider credentials.
"""

import gzip
import hashlib
import io
import json
import re
import tarfile
from pathlib import PurePosixPath

MAX_ARCHIVE = 16 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_FILE = 1024 * 1024
MAX_FILES = 2400
MAX_PATCH = 512 * 1024
COMMIT = r"^(?:[a-f0-9]{40}|[a-f0-9]{64})$"
EXACT = {"pyproject.toml", "backend/requirements.lock", "app/pubspec.yaml", "app/pubspec.lock"}


def allowed_path(value):
    if not isinstance(value, str) or len(value) > 240 or not re.fullmatch(r"[A-Za-z0-9_./-]+", value):
        return False
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in ("", ".", "..") or p.startswith(".") for p in path.parts):
        return False
    if str(path) != value:
        return False
    return value in EXACT or (value.startswith(("backend/schulpilot/", "backend/tests/")) and value.endswith(".py")) or (
        value.startswith(("app/lib/", "app/test/")) and value.endswith(".dart"))


def archive_bytes(files, commit):
    if not re.fullmatch(COMMIT, commit) or not 1 <= len(files) <= MAX_FILES:
        raise ValueError("invalid_source_manifest")
    total = 0
    for name, data in files.items():
        if not allowed_path(name) or not isinstance(data, bytes) or len(data) > MAX_FILE or b"\x00" in data:
            raise ValueError("invalid_source_entry")
        data.decode("utf-8")
        total += len(data)
    if total > MAX_SOURCE:
        raise ValueError("source_limit")
    manifest = {"version": 1, "source_commit": commit,
                "files": {n: hashlib.sha256(v).hexdigest() for n, v in sorted(files.items())}}
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, data in [("manifest.json", json.dumps(manifest, sort_keys=True).encode()), *sorted(files.items())]:
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), 0o600, 0
                archive.addfile(info, io.BytesIO(data))
    raw = output.getvalue()
    if len(raw) > MAX_ARCHIVE:
        raise ValueError("archive_limit")
    return raw


def read_archive(raw, expected_commit):
    if not isinstance(raw, bytes) or len(raw) > MAX_ARCHIVE or not re.fullmatch(COMMIT, expected_commit):
        raise ValueError("invalid_source_archive")
    # Bound decompression before tarfile sees PAX/GNU extension headers: their
    # payload is consumed internally before an application can inspect entries.
    ceiling = MAX_SOURCE + MAX_FILE + (MAX_FILES + 1) * 2048 + 10240
    with gzip.GzipFile(fileobj=io.BytesIO(raw), mode="rb") as compressed:
        expanded = compressed.read(ceiling + 1)
    if len(expanded) > ceiling:
        raise ValueError("expanded_archive_limit")
    files, total, manifest = {}, 0, None
    with tarfile.open(fileobj=io.BytesIO(expanded), mode="r:") as archive:
        for count, entry in enumerate(archive):
            if count > MAX_FILES or not entry.isfile() or entry.size > MAX_FILE:
                raise ValueError("invalid_source_entry")
            name = entry.name
            if name != "manifest.json" and not allowed_path(name) or name in files or name == "manifest.json" and manifest is not None:
                raise ValueError("invalid_source_path")
            total += entry.size
            if total > MAX_SOURCE:
                raise ValueError("source_limit")
            stream = archive.extractfile(entry)
            if stream is None:
                raise ValueError("missing_source")
            value = stream.read(MAX_FILE + 1)
            if len(value) != entry.size or b"\x00" in value:
                raise ValueError("invalid_source_text")
            value.decode("utf-8")
            if name == "manifest.json":
                manifest = json.loads(value)
            else:
                files[name] = value
    if (not isinstance(manifest, dict) or set(manifest) != {"version", "source_commit", "files"}
            or manifest["version"] != 1 or manifest["source_commit"] != expected_commit
            or manifest["files"] != {n: hashlib.sha256(v).hexdigest() for n, v in files.items()} or not files):
        raise ValueError("source_digest_mismatch")
    return files
