#!/usr/bin/python3
"""Systemd entrypoint for one rootless, private-socket provider container."""

import os
import re
from pathlib import Path

image = Path("/opt/schulpilot-codex/image-id").read_text().strip()
if not re.fullmatch(r"sha256:[a-f0-9]{64}", image):
    raise SystemExit("Pinned Codex container image is missing.")
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
    image,
]
os.execv(args[0], args)
