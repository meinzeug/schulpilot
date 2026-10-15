#!/usr/bin/python3
"""Systemd entrypoint for one rootless, private-socket provider container."""

import json
import os
import re
from pathlib import Path

image = Path("/opt/schulpilot-codex/image-id").read_text().strip()
if not re.fullmatch(r"sha256:[a-f0-9]{64}", image):
    raise SystemExit("Pinned Codex container image is missing.")
policy = json.loads(Path("/opt/schulpilot-codex/search-policy.json").read_text())
if (
    set(policy) != {"auth_mode", "web_search"}
    or policy["auth_mode"] not in ("api_key", "account")
    or type(policy["web_search"]) is not bool
):
    raise SystemExit("Invalid local Codex search policy.")
args = [
    "/usr/bin/podman",
    "--cgroup-manager=cgroupfs",
    "run",
    "--rm",
    "--replace",
    "--name",
    "schulpilot-codex",
    "--read-only",
    "--cap-drop=ALL",
    "--security-opt=no-new-privileges",
    "--userns=keep-id",
    "--user",
    f"{os.getuid()}:{os.getgid()}",
    "--network=slirp4netns:allow_host_loopback=false",
    "--tmpfs=/tmp:rw,noexec,nosuid,size=128m",
    "--mount=type=bind,src=/var/lib/schulpilot-codex/auth,dst=/run/credentials",
    "--mount=type=bind,src=/run/schulpilot-provider,dst=/run/provider",
    "--env=CODEX_AUTH_MODE=" + policy["auth_mode"],
    "--env=CODEX_WEB_SEARCH=" + str(policy["web_search"]).lower(),
    image,
]
os.execv(args[0], args)
