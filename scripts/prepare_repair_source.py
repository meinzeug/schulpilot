"""Build a reproducible public-code allowlist package from exactly committed Git blobs."""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from schulpilot.repair_source import allowed_path, archive_bytes  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true", help="Validate an existing exact package; do not write it")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if args.commit != head or subprocess.check_output(["git", "status", "--porcelain"], cwd=root).strip():
        raise SystemExit("Repair source requires the clean exact build commit.")
    paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", head], cwd=root, text=True).splitlines()
    files = {name: subprocess.check_output(["git", "show", head + ":" + name], cwd=root)
             for name in paths if allowed_path(name)}
    raw = archive_bytes(files, head)
    if args.verify:
        if args.output.is_symlink() or not args.output.is_file() or args.output.stat().st_size != len(raw) or args.output.read_bytes() != raw:
            raise SystemExit("Repair source package differs from the clean exact build commit.")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(raw)
    print(json.dumps({"source_commit": head, "files": len(files), "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "verified": args.verify}))


if __name__ == "__main__":
    main()
