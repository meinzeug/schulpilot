"""Pure, bounded policies for the offline repair runner and response broker."""

import difflib
import hashlib
import json
import re
from pathlib import Path

from source_policy import MAX_FILE, MAX_FILES, MAX_PATCH, MAX_SOURCE, allowed_path

MODEL, EFFORT, MAX_CALLS, MAX_SECONDS = "gpt-6.1-sol", "max", 12, 240


def request_body(raw):
    if len(raw) > 4500000:
        raise ValueError("request_limit")
    data = json.loads(raw)
    if (not isinstance(data, dict) or data.get("model") != MODEL
            or data.get("reasoning", {}).get("effort") != EFFORT
            or "previous_response_id" in data or not isinstance(data.get("input"), list)):
        raise ValueError("model_binding")
    tools = data.get("tools", [])
    if not isinstance(tools, list) or len(tools) > 100 or any(t.get("type") not in ("function", "custom") for t in tools):
        raise ValueError("hosted_tools_denied")
    if any(not isinstance(item, dict) or item.get("type") == "item_reference" for item in data["input"]):
        raise ValueError("remote_history_denied")
    # Only fields necessary for an in-memory local coding conversation.
    result = {k: v for k, v in data.items() if k in {
        "model", "instructions", "input", "tools", "tool_choice", "parallel_tool_calls", "reasoning", "text", "include"}}
    result.update(model=MODEL, reasoning={"effort": EFFORT}, stream=True, store=False)
    return result


def podman_command(image, directory, identifier, uid, gid):
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", image) or not re.fullmatch(r"[a-f0-9]{32}", identifier):
        raise ValueError("image_binding")
    root = Path(directory).resolve()
    return ["/usr/bin/podman", "--cgroup-manager=cgroupfs", "run", "--rm", "--name", "repair-" + identifier,
            "--label=schulpilot.repair=true", "--pull=never", "--network=none", "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
            "--userns=keep-id", "--user", f"{uid}:{gid}", "--pids-limit=96", "--memory=1g", "--cpus=1",
            "--ipc=none", "--ulimit=nofile=256:256", "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=128m,mode=1777",
            "--tmpfs=/workspace:rw,nosuid,nodev,size=96m,mode=1777",
            "--volume", str(root / "baseline") + ":/baseline:ro,nosuid,nodev",
            "--volume", str(root / "proxy") + ":/proxy:ro,nosuid,nodev",
            "--volume", str(root / "incident") + ":/incident:ro,nosuid,nodev", image]


def patch_bytes(baseline, directory, forbidden=()):
    """Reject all unexpected output, links and non-code paths before diffing."""
    root, current, total = Path(directory), {}, 0
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("symlink_output")
        if path.is_dir():
            continue
        name = path.relative_to(root).as_posix()
        stat = path.stat()
        if not path.is_file() or stat.st_nlink != 1 or not allowed_path(name) or stat.st_size > MAX_FILE:
            raise ValueError("invalid_output")
        value = path.read_bytes()
        value.decode("utf-8")
        total += len(value)
        if b"\x00" in value or total > MAX_SOURCE or len(current) >= MAX_FILES:
            raise ValueError("output_limit")
        current[name] = value
    parts, changed = [], []
    for name in sorted(set(baseline) | set(current)):
        before, after = baseline.get(name, b""), current.get(name, b"")
        if before == after:
            continue
        if name in baseline and name.startswith(("backend/tests/", "app/test/")):
            raise ValueError("baseline_test_change")
        # Dependencies are supplied for inspection but cannot be changed by a patch.
        if not (name.endswith((".py", ".dart")) and name.startswith(("backend/schulpilot/", "backend/tests/", "app/lib/", "app/test/"))):
            raise ValueError("dependency_change")
        changed.append(name)
        lines = list(difflib.unified_diff(before.decode().splitlines(keepends=True), after.decode().splitlines(keepends=True),
                                         fromfile="a/" + name if name in baseline else "/dev/null",
                                         tofile="b/" + name if name in current else "/dev/null"))
        for line in lines:
            parts.append(line if line.endswith("\n") else line + "\n\\ No newline at end of file\n")
    patch = "".join(parts).encode()
    if not patch:
        raise ValueError("empty_patch")
    if len(patch) > MAX_PATCH or any(value and value in patch for value in forbidden):
        raise ValueError("invalid_patch")
    # Obvious secret material cannot enter the review artifact, even if invented.
    if re.search(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bsk-[A-Za-z0-9_-]{20,}", patch):
        raise ValueError("credential_output")
    return patch, changed, current


def catalog_fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def synthetic_fault(files, fixture):
    """Inject exactly one known guard defect only into a copied public workspace."""
    if fixture != "decision-closed-v1":
        raise ValueError("synthetic_fixture")
    name = "backend/schulpilot/instructional_decisions.py"
    marker = b'        if step["kind"] in ("practice", "check_understanding", "hint") and q.get("closed"):\n'
    original = files.get(name, b"")
    if original.count(marker) != 1:
        raise ValueError("synthetic_source_changed")
    return {**files, name: original.replace(marker, marker.replace(b"if step", b"if False and step"), 1)}
