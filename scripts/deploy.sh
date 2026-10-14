#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -f app/build/web/index.html
release="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
ssh -o BatchMode=yes dorfspy python3 - < deploy/bootstrap_host.py
ssh dorfspy "mkdir -p /opt/schulpilot/releases/$release"
rsync -a --exclude='__pycache__' --exclude='.pytest_cache' backend deploy "dorfspy:/opt/schulpilot/releases/$release/"
rsync -a app/build/web/ "dorfspy:/opt/schulpilot/releases/$release/web/"
ssh dorfspy python3 - "$release" "$(git rev-parse HEAD)" <<'PY'
import json,sys
from pathlib import Path
root=Path('/opt/schulpilot/releases')/sys.argv[1]
(root/'release.json').write_text(json.dumps({'release_id':sys.argv[1],'source_commit':sys.argv[2]})+'\n')
PY
ssh dorfspy "python3 /opt/schulpilot/releases/$release/deploy/activate.py $release"
curl --retry 10 --retry-all-errors --retry-delay 3 --fail --silent --show-error https://schulpilot.dorfspy.de/api/health
