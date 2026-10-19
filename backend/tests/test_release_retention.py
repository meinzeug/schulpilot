from pathlib import Path

import pytest

from deploy.prune_releases import PruneError, plan_prune

CURRENT = "20261019T153515Z-8850ec9"
PREVIOUS = "20261019T065608Z-863d4f9"
OBSOLETE = "20261019T063153Z-8990410"


def setup_release(root: Path, name: str) -> Path:
    release = root / name
    release.mkdir()
    (release / "release.json").write_text("{}\n")
    return release


def test_prune_keeps_current_and_previous_and_returns_only_old_releases(tmp_path):
    root = tmp_path / "releases"
    root.mkdir()
    current = setup_release(root, CURRENT)
    previous = setup_release(root, PREVIOUS)
    obsolete = setup_release(root, OBSOLETE)
    current_link = tmp_path / "current"
    previous_link = tmp_path / "previous"
    current_link.symlink_to(current)
    previous_link.symlink_to(previous)

    assert plan_prune(root, current_link, previous_link) == [obsolete]
    assert current.is_dir() and previous.is_dir()


def test_prune_aborts_before_deleting_when_unknown_entry_exists(tmp_path):
    root = tmp_path / "releases"
    root.mkdir()
    current = setup_release(root, CURRENT)
    previous = setup_release(root, PREVIOUS)
    obsolete = setup_release(root, OBSOLETE)
    (root / "keep-this-file").write_text("unknown")
    current_link = tmp_path / "current"
    previous_link = tmp_path / "previous"
    current_link.symlink_to(current)
    previous_link.symlink_to(previous)

    with pytest.raises(PruneError, match="unexpected entry"):
        plan_prune(root, current_link, previous_link)
    assert obsolete.is_dir()


def test_prune_rejects_pointer_outside_release_root(tmp_path):
    root = tmp_path / "releases"
    root.mkdir()
    current = setup_release(root, CURRENT)
    outside = setup_release(tmp_path, PREVIOUS)
    obsolete = setup_release(root, OBSOLETE)
    current_link = tmp_path / "current"
    previous_link = tmp_path / "previous"
    current_link.symlink_to(current)
    previous_link.symlink_to(outside)

    with pytest.raises(PruneError, match="direct release directory"):
        plan_prune(root, current_link, previous_link)
    assert obsolete.is_dir()


def test_prune_allows_fresh_install_without_previous_release(tmp_path):
    root = tmp_path / "releases"
    root.mkdir()
    current = setup_release(root, CURRENT)
    obsolete = setup_release(root, OBSOLETE)
    current_link = tmp_path / "current"
    current_link.symlink_to(current)

    assert plan_prune(root, current_link, tmp_path / "previous") == [obsolete]
