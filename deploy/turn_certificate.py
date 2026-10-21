"""Copy only this host's existing ACME certificate to the isolated TURN user."""

import os
import pwd
import subprocess
from pathlib import Path

HOST = "schulpilot.dorfspy.de"
SOURCE = Path("/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory") / HOST
TARGET = Path("/etc/schulpilot-turn")


def synchronize():
    if os.geteuid() != 0:
        raise SystemExit("Run as the local operator")
    account = pwd.getpwnam("turnserver")
    changed = False
    for suffix, name in (("crt", "tls.crt"), ("key", "tls.key")):
        source = SOURCE / (HOST + "." + suffix)
        data = source.read_bytes()
        destination = TARGET / name
        if not destination.exists() or destination.read_bytes() != data:
            temporary = TARGET / (name + ".new")
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
            with os.fdopen(descriptor, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            os.chown(temporary, 0, account.pw_gid)
            temporary.replace(destination)
            changed = True
    if changed and subprocess.run(["systemctl", "is-active", "--quiet", "schulpilot-turn"]).returncode == 0:
        subprocess.run(["systemctl", "restart", "schulpilot-turn"], check=True)
    print("SCHULPILOT TURN certificate synchronized" if changed else "SCHULPILOT TURN certificate unchanged")


if __name__ == "__main__":
    synchronize()
