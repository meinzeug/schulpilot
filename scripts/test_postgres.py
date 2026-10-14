"""Run backend checks on an isolated PostgreSQL 16 cluster, never production."""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    bins = Path("/usr/lib/postgresql/16/bin")
    if not (bins / "initdb").is_file():
        raise SystemExit("PostgreSQL 16 binaries are required locally.")
    root = Path(tempfile.mkdtemp(prefix="schulpilot-isolated-pg-"))
    root.chmod(0o700)
    data, sock = root / "database", root / "socket"
    sock.mkdir(mode=0o700)
    started = False
    try:
        subprocess.run(
            [
                str(bins / "initdb"),
                "-D",
                str(data),
                "--auth-local=trust",
                "--auth-host=reject",
                "--no-locale",
                "--encoding=UTF8",
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                str(bins / "pg_ctl"),
                "-D",
                str(data),
                "-l",
                str(root / "postgres.log"),
                "-o",
                f"-F -k {sock} -c listen_addresses='' -c unix_socket_permissions=0700 -p 55440",
                "-w",
                "start",
            ],
            check=True,
            capture_output=True,
        )
        started = True
        subprocess.run([str(bins / "createdb"), "-h", str(sock), "-p", "55440", "schulpilot_isolated_test"], check=True)
        env = {
            **os.environ,
            "PYTHONPATH": "backend",
            "TEST_DATABASE_URL": f"postgresql+psycopg://{os.environ['USER']}@/schulpilot_isolated_test?host={sock}&port=55440",
        }
        return subprocess.run(
            [sys.executable, "-m", "pytest", "-q", *(sys.argv[1:] or ["backend/tests"])], env=env
        ).returncode
    finally:
        if started:
            subprocess.run([str(bins / "pg_ctl"), "-D", str(data), "-m", "fast", "-w", "stop"], capture_output=True)
        shutil.rmtree(root)


if __name__ == "__main__":
    sys.exit(main())
