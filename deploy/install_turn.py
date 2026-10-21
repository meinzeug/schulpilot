"""Explicit operator installation of one authenticated coturn relay.

Not run by ordinary deployments or empty installations. Credentials remain in
root-controlled configuration. Existing coturn installations must be reconciled
by an operator instead of being overwritten. No Caddy or other app changes.
"""

import ipaddress
import json
import os
import pwd
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HOST = "schulpilot.dorfspy.de"
DIRECTORY = Path("/etc/schulpilot-turn")
ENVIRONMENT = Path("/etc/schulpilot/environment")
URLS = [f"turn:{HOST}:3478?transport=udp", f"turn:{HOST}:3478?transport=tcp", f"turns:{HOST}:5349?transport=tcp"]
DENIED = ["0.0.0.0-0.255.255.255", "10.0.0.0-10.255.255.255", "100.64.0.0-100.127.255.255",
          "127.0.0.0-127.255.255.255", "169.254.0.0-169.254.255.255", "172.16.0.0-172.31.255.255",
          "192.0.0.0-192.0.0.255", "192.168.0.0-192.168.255.255", "198.18.0.0-198.19.255.255",
          "224.0.0.0-255.255.255.255", "::1", "fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
          "fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "ff00::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"]


def values(text):
    result = {}
    for line in text.splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            name, value = line.split("=", 1)
            result[name] = " ".join(shlex.split(value))
    return result


def configuration(address, secret):
    # coturn interprets an all-zero singular range as unbounded at BOTH ends,
    # accidentally denying every address. Its own good_peer_addr rejects zero
    # and loopback peers before these ranges are considered.
    for denied in DENIED:
        bounds = denied.split("-")
        if all(ipaddress.ip_address(bound).is_unspecified for bound in bounds):
            raise ValueError("An unspecified TURN deny range would block every peer")
    return "\n".join([
        "# SCHULPILOT: authenticated DTLS/SRTP relay; no media recording.",
        "listening-port=3478", "tls-listening-port=5349", f"listening-ip={address}", f"relay-ip={address}",
        "min-port=49160", "max-port=49259", "fingerprint", "use-auth-secret", f"static-auth-secret={secret}",
        f"realm={HOST}", "server-name=SCHULPILOT", "stale-nonce=600", "no-cli", "no-tcp-relay", "no-multicast-peers",
        "no-tlsv1", "no-tlsv1_1", "no-dtls", "cert=/etc/schulpilot-turn/tls.crt", "pkey=/etc/schulpilot-turn/tls.key",
        "user-quota=6", "total-quota=100", "max-bps=500000", "bps-capacity=12500000",
        "no-software-attribute", "no-stdout-log", "log-file=/dev/null", "simple-log", "relay-threads=2",
        "pidfile=/tmp/schulpilot-turn.pid",
        *["denied-peer-ip=" + address for address in DENIED], "",
    ])


def main():
    if sys.argv[1:] != ["--install"] or os.geteuid() != 0:
        raise SystemExit("Explicit local operator action required: install_turn.py --install as root")
    if Path("/etc/turnserver.conf").exists() and not DIRECTORY.exists():
        raise SystemExit("Existing coturn configuration needs operator reconciliation")
    original = ENVIRONMENT.read_text()
    settings = values(original)
    if settings.get("PUBLIC_URL") != "https://" + HOST:
        raise SystemExit("This installer is bound to the existing SCHULPILOT host")
    address = sorted({item[4][0] for item in socket.getaddrinfo(HOST, None, socket.AF_INET)})
    if len(address) != 1 or not ipaddress.ip_address(address[0]).is_global:
        raise SystemExit("A single public IPv4 address is required")
    # Ensure DNS is not accidentally pointing at a different machine.
    addresses = json.loads(subprocess.check_output(["ip", "-j", "address", "show"], text=True))
    if address[0] not in {a["local"] for interface in addresses for a in interface.get("addr_info", [])}:
        raise SystemExit("Public address is not configured on this host")
    backup = Path("/var/backups/schulpilot") / ("before-turn-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    backup.mkdir(mode=0o700)
    shutil.copy2(ENVIRONMENT, backup / "environment")
    (backup / "environment").chmod(0o600)
    if DIRECTORY.exists():
        shutil.copytree(DIRECTORY, backup / "turn")
    # The distributor service is never started with its default configuration.
    subprocess.run(["systemctl", "mask", "coturn.service"], check=True)
    subprocess.run(["apt-get", "update", "-qq"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["apt-get", "install", "-y", "--no-install-recommends", "coturn"], check=True,
                   env={**os.environ, "DEBIAN_FRONTEND": "noninteractive"}, stdout=subprocess.DEVNULL)
    account = pwd.getpwnam("turnserver")
    DIRECTORY.mkdir(mode=0o750, exist_ok=True)
    os.chown(DIRECTORY, 0, account.pw_gid)
    DIRECTORY.chmod(0o750)
    secret = settings.get("SCHULPILOT_TURN_SECRET") or secrets.token_urlsafe(48)
    if len(secret) < 32 or not all(c.isalnum() or c in "_-" for c in secret):
        raise SystemExit("Invalid existing TURN secret")
    config = DIRECTORY / "turnserver.conf"
    config.write_text(configuration(address[0], secret))
    config.chmod(0o640)
    os.chown(config, 0, account.pw_gid)
    # Certificate source/key remain accessible only to root/Caddy, not the relay.
    from turn_certificate import synchronize
    synchronize()
    shutil.copy2(Path(__file__).resolve().parent / "turn_certificate.py", DIRECTORY / "refresh_certificate.py")
    (DIRECTORY / "refresh_certificate.py").chmod(0o644)
    lines = [line for line in original.splitlines()
             if not line.startswith(("SCHULPILOT_TURN_URLS=", "SCHULPILOT_TURN_SECRET="))]
    lines.extend(["SCHULPILOT_TURN_URLS=" + shlex.quote(json.dumps(URLS)),
                  "SCHULPILOT_TURN_SECRET=" + shlex.quote(secret)])
    temporary = ENVIRONMENT.with_suffix(".turn-new")
    temporary.write_text("\n".join(lines) + "\n")
    temporary.chmod(0o640)
    os.chown(temporary, ENVIRONMENT.stat().st_uid, ENVIRONMENT.stat().st_gid)
    temporary.replace(ENVIRONMENT)
    source = Path(__file__).resolve().parent
    for name in ("schulpilot-turn.service", "schulpilot-turn-cert.service", "schulpilot-turn-cert.timer"):
        shutil.copy2(source / name, Path("/etc/systemd/system") / name)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "--now", "schulpilot-turn", "schulpilot-turn-cert.timer"], check=True)
    # Do not enable/change a disabled firewall. Add only this application's ports.
    if shutil.which("ufw"):
        status = subprocess.check_output(["ufw", "status"], text=True)
        if "Status: active" in status:
            for port, protocol in (("3478", "udp"), ("3478", "tcp"), ("5349", "tcp"), ("49160:49259", "udp")):
                subprocess.run(["ufw", "allow", port + "/" + protocol, "comment", "SCHULPILOT family calls"], check=True,
                               stdout=subprocess.DEVNULL)
    subprocess.run(["systemctl", "is-active", "--quiet", "schulpilot-turn"], check=True)
    installed = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", "coturn"], text=True)
    print(json.dumps({"turn_installed": True, "package": installed, "tls_port": 5349,
                      "udp_tcp_port": 3478, "relay_range": "49160-49259", "authenticated": True}))


if __name__ == "__main__":
    main()
