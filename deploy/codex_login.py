#!/usr/bin/python3
"""Local operator entrypoint. No network listener or user-supplied commands."""

import getpass
import json
import os
import pwd
import socket
import stat
import subprocess
import sys
import time
from pathlib import Path

HOME = Path("/var/lib/schulpilot-codex")
AUTH = HOME / "auth"


def adopt_worker_login():
    """Move only this worker user's default CLI login, never a developer's."""
    worker = pwd.getpwnam("schulpilot-codex")
    # Nothing after this point needs root. The worker owns its home and can
    # rename its entries; never apply root privileges to those paths.
    if os.geteuid() == 0:
        os.setgroups([])
        os.setgid(worker.pw_gid)
        os.setuid(worker.pw_uid)
    if os.geteuid() != worker.pw_uid or os.getegid() != worker.pw_gid:
        raise SystemExit("Der Import muss unter der eigenen Worker-Identität laufen.")

    descriptors = []
    created = None
    destination_fd = None
    complete = False

    def open_directory(name, *, parent=None):
        descriptor = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
        descriptors.append(descriptor)
        info = os.fstat(descriptor)
        if info.st_uid != worker.pw_uid or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError("unsafe directory")
        return descriptor

    def identity(info):
        return info.st_dev, info.st_ino

    def unchanged(directory, name, info):
        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        return identity(current) == identity(info)

    try:
        home = open_directory(HOME)
        source_directory = open_directory(".codex", parent=home)
        source_directory_info = os.fstat(source_directory)
        source = os.open(
            "auth.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            dir_fd=source_directory,
        )
        descriptors.append(source)
        info = os.fstat(source)
        if (
            not stat.S_ISREG(info.st_mode) or info.st_uid != worker.pw_uid
            or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1
            or not 0 < info.st_size <= 40_000
        ):
            raise ValueError("unsafe login")
        raw = b""
        while len(raw) <= 40_000:
            part = os.read(source, min(4096, 40_001 - len(raw)))
            if not part:
                break
            raw += part
        data = json.loads(raw)
        tokens = data.get("tokens") if isinstance(data, dict) else None
        if len(raw) > 40_000 or not isinstance(tokens, dict) or not all(
            isinstance(tokens.get(key), str) and bool(tokens[key].strip())
            for key in ("access_token", "refresh_token")
        ) or data.get("OPENAI_API_KEY") or data.get("auth_mode") not in (None, "chatgpt"):
            raise ValueError("invalid account login")
        after = os.fstat(source)
        if (after.st_size, after.st_mtime_ns, after.st_ctime_ns) != (info.st_size, info.st_mtime_ns, info.st_ctime_ns):
            raise ValueError("concurrent source change")

        try:
            os.mkdir("auth", mode=0o700, dir_fd=home)
        except FileExistsError:
            pass
        destination_directory = open_directory("auth", parent=home)
        destination_directory_info = os.fstat(destination_directory)
        destination_fd = os.open(
            "auth.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600, dir_fd=destination_directory,
        )
        descriptors.append(destination_fd)
        created = os.fstat(destination_fd)
        os.fchmod(destination_fd, 0o600)
        os.fchown(destination_fd, worker.pw_uid, worker.pw_gid)
        remaining = memoryview(raw)
        while remaining:
            written = os.write(destination_fd, remaining)
            if written <= 0:
                raise OSError("incomplete login write")
            remaining = remaining[written:]
        os.fsync(destination_fd)
        # Resolve neither a replaced directory nor a symlink during cleanup.
        # A concurrent source refresh must win; remove our own copy on failure.
        if not (
            unchanged(home, ".codex", source_directory_info)
            and unchanged(home, "auth", destination_directory_info)
            and unchanged(source_directory, "auth.json", info)
            and unchanged(destination_directory, "auth.json", created)
        ):
            raise ValueError("concurrent login replacement")
        after = os.fstat(source)
        if (after.st_size, after.st_mtime_ns, after.st_ctime_ns) != (info.st_size, info.st_mtime_ns, info.st_ctime_ns):
            raise ValueError("concurrent source refresh")
        os.unlink("auth.json", dir_fd=source_directory)
        # The destination is fully written and the source has been removed.
        # A later directory-fsync error must never erase both credentials.
        complete = True
        os.fsync(source_directory)
        os.fsync(destination_directory)
    except FileExistsError:
        raise SystemExit("Eine eigene Worker-Anmeldung ist bereits vorhanden; sie wird nicht überschrieben.") from None
    except (OSError, ValueError, TypeError):
        raise SystemExit("Import abgebrochen: eigene Anmeldung, geschützte Verzeichnisse oder unveränderte Quelldatei fehlen.") from None
    finally:
        if not complete and created is not None:
            try:
                if unchanged(destination_directory, "auth.json", created):
                    os.unlink("auth.json", dir_fd=destination_directory)
            except OSError:
                pass
        for descriptor in reversed(descriptors):
            os.close(descriptor)
    print(json.dumps({"credential_mode": "account", "imported_from_worker_home": True}))


def main():
    if os.geteuid() != 0:
        raise SystemExit("Bitte mit sudo auf dem SCHULPILOT-Server ausführen.")
    command = sys.argv[1:]
    if command == ["adopt-login"]:
        adopt_worker_login()
        return
    if command == ["status"]:
        try:
            data = json.loads((AUTH / "auth.json").read_text())
            mode = "api_key" if data.get("OPENAI_API_KEY") else "account" if data.get("tokens") else "missing"
        except (OSError, ValueError, TypeError):
            mode = "missing"
        print(json.dumps({"credential_mode": mode, "upstream_connection_verified": False}))
        return
    if command == ["probe"]:
        subprocess.run(["/usr/bin/python3", "/opt/schulpilot/current/deploy/admin.py", "probe-codex"], check=True)
        return
    if command not in (["login"], ["login-api"], ["logout"]):
        raise SystemExit("Verwendung: schulpilot-codex login | login-api | adopt-login | status | probe | logout")
    if not sys.stdin.isatty():
        raise SystemExit("Die Anmeldung benötigt ein eigenes interaktives Terminal.")
    subprocess.run(["systemctl", "stop", "schulpilot-codex.service"], check=True)
    environment = {"PATH": "/usr/bin:/bin", "HOME": str(HOME), "CODEX_HOME": str(AUTH), "LANG": "C.UTF-8"}
    args = [
        "/usr/sbin/runuser",
        "-u",
        "schulpilot-codex",
        "--",
        "/opt/schulpilot-codex/bin/codex",
        "-c",
        'cli_auth_credentials_store="file"',
    ]
    try:
        if command == ["logout"]:
            subprocess.run([*args, "logout"], env=environment, cwd=HOME, check=True)
            return
        if command == ["login-api"]:
            key = getpass.getpass("Eigener SCHULPILOT-OpenAI-API-Schlüssel: ")
            subprocess.run(
                [*args, "login", "--with-api-key"], input=key.encode(), env=environment, cwd=HOME, check=True
            )
        else:
            subprocess.run([*args, "login", "--device-auth"], env=environment, cwd=HOME, check=True)
        (AUTH / "auth.json").chmod(0o600)
    finally:
        subprocess.run(["systemctl", "start", "schulpilot-codex.service"], check=True)
    # Actual activation follows only successful counted synthetic tests.
    for _ in range(30):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.connect("/run/schulpilot-provider/codex.sock")
            break
        except OSError:
            time.sleep(0.2)
    subprocess.run(["/usr/bin/python3", "/opt/schulpilot/current/deploy/admin.py", "probe-codex"], check=True)


if __name__ == "__main__":
    main()
