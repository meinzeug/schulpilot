#!/usr/bin/env bash
set -euo pipefail
# Run from a DEDICATED rootless worker account, after operator review.
# The key is a separate commercial API project key, never development auth.
# Only the job socket is shared with the backend, never a host home or repo.
podman run --name schulpilot-codex --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --pids-limit=64 --memory=512m --cpus=1 \
  --tmpfs=/tmp:rw,noexec,nosuid,size=128m \
  --secret=schulpilot-codex-key,target=/run/secrets/codex_provider_key,uid=10001,mode=0400 \
  --mount=type=bind,src=/run/schulpilot-provider,dst=/run/provider \
  localhost/schulpilot-codex:0.162.1
