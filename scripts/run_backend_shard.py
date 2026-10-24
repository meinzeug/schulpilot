"""Run an unchanged pytest collection in one of three deterministic file shards.

No database, application imports or fixture changes. Collection receipts describe
selection, not test execution or success (in particular when pytest uses -x).
"""

import argparse
import hashlib
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

import pytest


def _digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


@dataclass(frozen=True)
class Partition:
    all_nodes: tuple[tuple[str, str], ...]
    selected: tuple[tuple[str, str], ...]
    deselected: tuple[tuple[str, str], ...]
    files: tuple[str, ...]
    shard_index: int
    shard_count: int

    def receipt(self):
        counts = dict.fromkeys(self.files, 0)
        for path, _ in self.all_nodes:
            counts[path] += 1
        return {
            "version": 1,
            "shard_index": self.shard_index,
            "shard_count": self.shard_count,
            "all_count": len(self.all_nodes),
            "selected_count": len(self.selected),
            "deselected_count": len(self.deselected),
            "all_files": [
                {"path": path, "shard_index": index % self.shard_count, "node_count": counts[path]}
                for index, path in enumerate(self.files)
            ],
            "all_nodeids": [nodeid for _, nodeid in self.all_nodes],
            "selected_nodeids": [nodeid for _, nodeid in self.selected],
            "deselected_nodeids": [nodeid for _, nodeid in self.deselected],
            "collection_sha256": _digest(self.all_nodes),
            "selected_sha256": _digest(self.selected),
            "deselected_sha256": _digest(self.deselected),
        }


def partition_nodes(records, shard_index, shard_count):
    """Pure partition: unique relative files, all items in a file stay together."""
    if type(shard_count) is not int or shard_count < 1:
        raise ValueError("shard_count must be a positive integer")
    if type(shard_index) is not int or not 0 <= shard_index < shard_count:
        raise ValueError("shard_index is outside the shard range")
    nodes, seen = [], set()
    for path, nodeid in records:
        if not isinstance(path, str) or not path or "\\" in path:
            raise ValueError("test paths must be canonical relative POSIX paths")
        relative = PurePosixPath(path)
        if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != path:
            raise ValueError("test paths must be canonical relative POSIX paths")
        if not isinstance(nodeid, str) or nodeid.partition("::")[0] != path:
            raise ValueError("node ID does not match its collection file")
        if nodeid in seen:
            raise ValueError("duplicate collected node ID")
        seen.add(nodeid)
        nodes.append((path, nodeid))
    nodes.sort()
    files = tuple(sorted({path for path, _ in nodes}))
    owners = {path: index % shard_count for index, path in enumerate(files)}
    selected = tuple(node for node in nodes if owners[node[0]] == shard_index)
    deselected = tuple(node for node in nodes if owners[node[0]] != shard_index)
    return Partition(tuple(nodes), selected, deselected, files, shard_index, shard_count)


def _write_receipt(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".backend-shard-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


class ShardPlugin:
    def __init__(self, shard_index, shard_count, receipt):
        self.shard_index = shard_index
        self.shard_count = shard_count
        self.receipt_path = Path(receipt)
        self.partition = None
        self._own_deselection = False
        self._external_deselection = False
        self._partition_ready = False

    def pytest_deselected(self, items):
        if items and not self._own_deselection:
            self._external_deselection = True

    @pytest.hookimpl(trylast=True)
    def pytest_collection_modifyitems(self, session, config, items):
        if self._external_deselection:
            raise pytest.UsageError("Sharding requires the full collection without other deselection filters")
        try:
            records = [(item.path.resolve().relative_to(config.rootpath.resolve()).as_posix(), item.nodeid)
                       for item in items]
            self.partition = partition_nodes(records, self.shard_index, self.shard_count)
        except (TypeError, ValueError):
            raise pytest.UsageError("Invalid or duplicate test collection for file sharding") from None
        if not self.partition.all_nodes or not self.partition.selected:
            raise pytest.UsageError("Full collection and selected shard must both be nonempty")
        chosen = {nodeid for _, nodeid in self.partition.selected}
        removed = [item for item in items if item.nodeid not in chosen]
        # Keep pytest's original ordering, fixtures, marks and items unchanged.
        items[:] = [item for item in items if item.nodeid in chosen]
        self._own_deselection = True
        try:
            config.hook.pytest_deselected(items=removed)
        finally:
            self._own_deselection = False
        self._partition_ready = True

    @pytest.hookimpl(trylast=True)
    def pytest_collection_finish(self, session):
        if not self._partition_ready:
            # Preserve the original collection/partition failure; never receipt
            # a partially collected tree or replace its diagnostic here.
            return
        if session.testsfailed or self._external_deselection:
            raise pytest.UsageError("Cannot receipt an incomplete or externally filtered collection")
        actual = sorted(item.nodeid for item in session.items)
        if actual != sorted(nodeid for _, nodeid in self.partition.selected):
            raise pytest.UsageError("Selected collection changed after file sharding")
        _write_receipt(self.receipt_path, self.partition.receipt())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard-index", type=int, required=True, choices=range(3))
    parser.add_argument("--shard-count", type=int, default=3, choices=(3,))
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--collect-only", action="store_true")
    parser.add_argument("pytest_args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.receipt.suffix != ".json" or args.receipt.is_symlink():
        parser.error("--receipt must be a regular JSON output path")
    # No stale receipt from an earlier selection may survive a failed run.
    args.receipt.unlink(missing_ok=True)
    arguments = args.pytest_args
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if not arguments:
        arguments = ["backend/tests"]
    if args.collect_only:
        arguments = ["--collect-only", *arguments]
    plugin = ShardPlugin(args.shard_index, args.shard_count, args.receipt)
    return int(pytest.main(arguments, plugins=[plugin]))


if __name__ == "__main__":
    sys.exit(main())
