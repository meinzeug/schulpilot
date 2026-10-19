"""Remove obsolete immutable releases while retaining current and rollback code."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE = Path("/opt/schulpilot")
RELEASES = BASE / "releases"
RELEASE_ID = re.compile(r"\d{8}T\d{6}Z-[0-9a-f]{7,40}\Z")
SERVICES = ("schulpilot-api.service", "schulpilot-worker.service")


class PruneError(RuntimeError):
    """Raised when the release tree is not safe to prune."""


def _pointer_target(pointer: Path, root: Path, *, required: bool) -> Path | None:
    if not pointer.is_symlink():
        if required or pointer.exists():
            raise PruneError(f"{pointer.name} is not a release symlink")
        return None
    target = pointer.resolve(strict=True)
    if target.parent != root or not target.is_dir() or not RELEASE_ID.fullmatch(target.name):
        raise PruneError(f"{pointer.name} does not point to a direct release directory")
    return target


def plan_prune(releases_root: Path, current_link: Path, previous_link: Path) -> list[Path]:
    """Return old releases after validating the entire top-level release tree."""
    root = releases_root.resolve(strict=True)
    if not root.is_dir():
        raise PruneError("release root is not a directory")
    current = _pointer_target(current_link, root, required=True)
    previous = _pointer_target(previous_link, root, required=False)
    keep = {target for target in (current, previous) if target is not None}
    if len(keep) != 1 + (previous is not None):
        raise PruneError("current and previous must refer to different releases")

    entries = sorted(root.iterdir())
    for entry in entries:
        if entry.is_symlink() or not entry.is_dir() or not RELEASE_ID.fullmatch(entry.name):
            raise PruneError(f"unexpected entry in release root: {entry.name}")
        if entry.resolve(strict=True).parent != root:
            raise PruneError(f"release escapes release root: {entry.name}")
    if not keep.issubset(set(entries)):
        raise PruneError("current or previous release is missing from the release root")
    return [entry for entry in entries if entry not in keep]


def _assert_no_nested_mounts(candidate: Path) -> None:
    mountinfo = Path("/proc/self/mountinfo")
    if not mountinfo.is_file():
        raise PruneError("cannot verify mount points")
    for line in mountinfo.read_text().splitlines():
        fields = line.split()
        if len(fields) < 5:
            continue
        mount = Path(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), fields[4]))
        if mount == candidate or candidate in mount.parents:
            raise PruneError(f"release contains a mounted path: {mount}")


def _assert_services_use_kept_releases(kept: set[Path]) -> None:
    for service in SERVICES:
        result = subprocess.run(
            ["systemctl", "show", "-p", "MainPID", "--value", service],
            check=True,
            capture_output=True,
            text=True,
        )
        pid = int(result.stdout.strip() or "0")
        if pid <= 0:
            raise PruneError(f"{service} has no running main process")
        cwd = Path(f"/proc/{pid}/cwd").resolve(strict=True)
        if not any(release == cwd or release in cwd.parents for release in kept):
            raise PruneError(f"{service} is using a release outside current/previous")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="delete obsolete releases (default: report only)")
    args = parser.parse_args()

    try:
        root = RELEASES.resolve(strict=True)
        current = _pointer_target(BASE / "current", root, required=True)
        previous = _pointer_target(BASE / "previous", root, required=False)
        kept = {target for target in (current, previous) if target is not None}
        removals = plan_prune(root, BASE / "current", BASE / "previous")
        if not args.apply:
            print(f"Dry run: {len(removals)} releases would be removed; current/previous are preserved.")
            for release in removals:
                print(release.name)
            return 0

        _assert_services_use_kept_releases(kept)
        for release in removals:
            _assert_no_nested_mounts(release)
        for release in removals:
            shutil.rmtree(release)
        print(f"Removed {len(removals)} obsolete releases; current and previous remain available.")
        return 0
    except (OSError, PruneError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"Release cleanup skipped: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
