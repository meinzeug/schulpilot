"""Pure CI selection checks; focused invocation needs no app/DB conftest."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from scripts.run_backend_shard import partition_nodes

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts/run_backend_shard.py"


def test_file_partition_is_deterministic_complete_disjoint_and_keeps_parameters_together():
    nodes = [
        (f"backend/tests/test_{file}.py", f"backend/tests/test_{file}.py::test_value[{case}]")
        for file in reversed(range(11)) for case in range(file % 4 + 1)
    ]
    partitions = [partition_nodes(nodes, index, 3) for index in range(3)]
    selected = [{nodeid for _, nodeid in part.selected} for part in partitions]
    all_nodes = {nodeid for _, nodeid in nodes}
    assert set.union(*selected) == all_nodes
    for index, part in enumerate(partitions):
        assert part == partition_nodes(reversed(nodes), index, 3)
        assert selected[index].isdisjoint({nodeid for _, nodeid in part.deselected})
        assert selected[index] | {nodeid for _, nodeid in part.deselected} == all_nodes
        assert all(selected[index].isdisjoint(other) for other in selected[index + 1:])
        assert len(part.selected) + len(part.deselected) == len(nodes)
    for file in {path for path, _ in nodes}:
        assert sum(any(path == file for path, _ in part.selected) for part in partitions) == 1
    receipts = [part.receipt() for part in partitions]
    assert len({receipt["collection_sha256"] for receipt in receipts}) == 1
    assert all(row["shard_index"] == index % 3 for index, row in enumerate(receipts[0]["all_files"]))


def test_pure_empty_partition_has_exact_empty_complements():
    for index in range(3):
        part = partition_nodes([], index, 3)
        assert part.all_nodes == part.selected == part.deselected == part.files == ()
        assert part.receipt()["all_count"] == part.receipt()["selected_count"] == 0


@pytest.mark.parametrize("index,count", [(-1, 3), (3, 3), (0, 0), (0, -1), (True, 3), (0, True), (0, 2.5)])
def test_invalid_shard_indices_and_counts_are_rejected(index, count):
    with pytest.raises(ValueError):
        partition_nodes([], index, count)


@pytest.mark.parametrize("records", [
    [("a.py", "a.py::test_x"), ("a.py", "a.py::test_x")],
    [("a.py", "b.py::test_x")], [("../a.py", "../a.py::test_x")],
    [("/a.py", "/a.py::test_x")], [("a//b.py", "a//b.py::test_x")],
])
def test_duplicate_ids_and_noncanonical_collection_paths_fail_closed(records):
    with pytest.raises(ValueError):
        partition_nodes(records, 0, 3)


def run_collect(directory, receipt, index=0, extra=()):
    environment = {**os.environ, "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1"}
    return subprocess.run(
        [sys.executable, str(RUNNER), "--shard-index", str(index), "--shard-count", "3", "--receipt", str(receipt),
         "--collect-only", "--", "-q", "--noconftest", "-p", "no:cacheprovider", "--rootdir", str(directory),
         *extra, str(directory)],
        cwd=ROOT, env=environment, text=True, capture_output=True, timeout=20,
    )


def test_real_collect_only_plugin_receipts_have_disjoint_complete_union(tmp_path):
    for index in range(6):
        (tmp_path / f"test_sample_{index}.py").write_text(
            "import pytest\n@pytest.mark.parametrize('value', [1,2])\ndef test_example(value): assert value > 0\n"
        )
    receipts = []
    for index in range(3):
        path = tmp_path / f"shard-{index}.json"
        result = run_collect(tmp_path, path, index)
        assert result.returncode == 0, result.stdout + result.stderr
        receipt = json.loads(path.read_text())
        assert receipt["all_count"] == 12 and receipt["selected_count"] == 4 and receipt["deselected_count"] == 8
        assert path.read_text().count("\n") > len(receipt["all_nodeids"])
        receipts.append(receipt)
    assert len({row["collection_sha256"] for row in receipts}) == 1
    selected = [set(row["selected_nodeids"]) for row in receipts]
    assert set.union(*selected) == set(receipts[0]["all_nodeids"])
    assert sum(map(len, selected)) == len(set.union(*selected)) == 12


def test_empty_selected_shard_and_other_deselection_produce_no_receipt(tmp_path):
    (tmp_path / "test_sample.py").write_text("def test_one(): pass\ndef test_two(): pass\n")
    path = tmp_path / "receipt.json"
    path.write_text('{"stale":true}')
    result = run_collect(tmp_path, path, index=2)
    assert result.returncode != 0 and not path.exists()
    assert "nonempty" in result.stderr
    result = run_collect(tmp_path, path, extra=("-k", "test_one"))
    assert result.returncode != 0 and not path.exists()
    assert "full collection" in result.stderr


def test_collection_errors_and_empty_collection_never_write_a_receipt(tmp_path):
    receipt = tmp_path / "receipt.json"
    result = run_collect(tmp_path, receipt)
    assert result.returncode != 0 and not receipt.exists()
    (tmp_path / "test_broken.py").write_text("def test_broken(\n")
    (tmp_path / "test_valid.py").write_text("def test_ok(): pass\n")
    result = run_collect(tmp_path, receipt)
    assert result.returncode != 0 and not receipt.exists()


def test_runner_executes_selected_items_with_existing_marks_fixtures_and_failfast(tmp_path):
    for index in range(3):
        (tmp_path / f"test_run_{index}.py").write_text(
            "import pytest\n@pytest.fixture\ndef value(): return 4\n"
            "def test_pass(value): assert value == 4\n"
            "@pytest.mark.skip(reason='existing explicit skip')\ndef test_skip(): assert False\n"
        )
    receipt = tmp_path / "executed.json"
    result = subprocess.run(
        [sys.executable, str(RUNNER), "--shard-index", "1", "--shard-count", "3", "--receipt", str(receipt),
         "--", "-q", "-x", "--noconftest", "-p", "no:cacheprovider", "--rootdir", str(tmp_path), str(tmp_path)],
        cwd=ROOT, env={**os.environ, "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1"},
        text=True, capture_output=True, timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "1 passed" in result.stdout and "1 skipped" in result.stdout and "4 deselected" in result.stdout
    selected = json.loads(receipt.read_text())["selected_nodeids"]
    assert selected == ["test_run_1.py::test_pass", "test_run_1.py::test_skip"]
