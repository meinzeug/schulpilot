"""Create a dedicated Google Play upload key outside Git. Never overwrite one."""

import os
import secrets
import subprocess
from pathlib import Path

directory = Path.home() / ".local/share/schulpilot-signing"
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
directory.chmod(0o700)
key = directory / "upload.jks"
password_file = directory / "upload.password"
properties = directory / "signing.properties"
if any(p.exists() for p in (key, password_file, properties)):
    if not all(p.is_file() for p in (key, password_file, properties)):
        raise SystemExit("Incomplete existing signing setup; no files were overwritten")
    print("Existing signing setup retained: " + str(properties))
else:
    password = secrets.token_urlsafe(40)
    fd = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(password)
    subprocess.run(
        [
            "keytool",
            "-genkeypair",
            "-keystore",
            str(key),
            "-alias",
            "schulpilot-upload",
            "-keyalg",
            "RSA",
            "-keysize",
            "4096",
            "-validity",
            "10000",
            "-storetype",
            "JKS",
            "-storepass:file",
            str(password_file),
            "-keypass:file",
            str(password_file),
            "-dname",
            "CN=SCHULPILOT Upload",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    key.chmod(0o600)
    fd = os.open(properties, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(
            "storeFile="
            + str(key)
            + "\nkeyAlias=schulpilot-upload\nstorePassword="
            + password
            + "\nkeyPassword="
            + password
            + "\n"
        )
    print("Dedicated upload key created. Signing properties: " + str(properties))
