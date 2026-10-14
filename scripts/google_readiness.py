"""Read-only Google release preflight; never creates cloud resources or keys."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path

PACKAGE = "de.dorfspy.schulpilot"
ANDROID = "{http://schemas.android.com/apk/res/android}"
MIN_TARGET_API = 36
TEXT_LIMITS = {"title": 30, "short_description": 80, "full_description": 4000}


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("Expected JSON object")
    return payload


def run_tool(command):
    return subprocess.run(command, capture_output=True, text=True, timeout=60, check=False)


def source_version(root):
    try:
        content = (root / "app/pubspec.yaml").read_text(encoding="utf-8")
        match = re.search(r"^version:\s*([^\s+]+)\+(\d+)\s*$", content, re.MULTILINE)
        return {"name": match[1], "code": int(match[2])} if match else None
    except (OSError, UnicodeError):
        return None


def parse_manifest(xml):
    manifest = ET.fromstring(xml)
    application = manifest.find("application")
    sdk = manifest.find("uses-sdk")
    raw_api = sdk.get(ANDROID + "targetSdkVersion") if sdk is not None else None
    raw_code = manifest.get(ANDROID + "versionCode")
    permissions = sorted({node.get(ANDROID + "name", "") for node in manifest if node.tag.startswith("uses-permission")})
    return {
        "package": manifest.get("package"),
        "version_code": int(raw_code) if raw_code and raw_code.isdecimal() else None,
        "version_name": manifest.get(ANDROID + "versionName"),
        "target_sdk": int(raw_api) if raw_api and raw_api.isdecimal() else None,
        "permissions": permissions,
        "direct_installer_permission": "android.permission.REQUEST_INSTALL_PACKAGES" in permissions,
        "debuggable": application is not None and application.get(ANDROID + "debuggable", "false").lower() == "true",
    }


def elf_alignment(data):
    """Inspect actual ELF64 PT_LOAD segments; zip alignment is a separate check."""
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("Invalid ELF header")
    if data[4] == 1:
        return {"elf_class": 32, "checked": False}
    if data[4] != 2:
        raise ValueError("Unknown ELF class")
    if data[5] not in (1, 2):
        raise ValueError("Unknown ELF byte order")
    order = "<" if data[5] == 1 else ">"
    header = struct.unpack_from(order + "16sHHIQQQIHHHHHH", data)
    offset, entry_size, count = header[5], header[9], header[10]
    if entry_size < 56 or count == 0 or offset + entry_size * count > len(data):
        raise ValueError("Invalid ELF program headers")
    loads = []
    relro_ends = []
    for i in range(count):
        values = struct.unpack_from(order + "IIQQQQQQ", data, offset + i * entry_size)
        kind, _, file_offset, virtual_address, _, _, memory_size, alignment = values
        if kind == 1:
            loads.append({"alignment": alignment, "offset_matches_address": file_offset % 16384 == virtual_address % 16384})
        elif kind == 0x6474E552:
            relro_ends.append((virtual_address + memory_size) % 16384 == 0)
    if not loads:
        raise ValueError("ELF has no PT_LOAD segments")
    return {
        "elf_class": 64,
        "checked": True,
        "load_segment_alignments": [entry["alignment"] for entry in loads],
        "load_segments_16k": all(entry["alignment"] >= 16384 and entry["alignment"] & (entry["alignment"] - 1) == 0 and entry["offset_matches_address"] for entry in loads),
        "relro_end_aligned_16k": all(relro_ends),
        "relro_segments": len(relro_ends),
    }


def inspect_native_libraries(path):
    libraries = []
    with zipfile.ZipFile(path) as bundle:
        for entry in bundle.infolist():
            if "/lib/" not in entry.filename or not entry.filename.endswith(".so"):
                continue
            if entry.file_size > 128 * 1024 * 1024:
                raise ValueError("Native library too large for bounded inspection")
            info = elf_alignment(bundle.read(entry))
            if any(abi in entry.filename for abi in ("/arm64-v8a/", "/x86_64/")) and info["elf_class"] != 64:
                raise ValueError("64-bit ABI contains a non-ELF64 native library")
            libraries.append({"name": entry.filename, **info})
    checked = [entry for entry in libraries if entry["checked"]]
    return {
        "libraries": libraries,
        "elf64_libraries_checked": len(checked),
        "elf64_alignment_16k": all(entry["load_segments_16k"] and entry["relro_end_aligned_16k"] for entry in checked) if checked else None,
        "runtime_16k_test": "not_performed",
    }


def build_report(root, *, aab_path=None, bundletool=None, fetch=fetch_json, runner=run_tool):
    root = Path(root).resolve()
    aab = Path(aab_path).resolve() if aab_path else root / "artifacts/schulpilot-0.1.0-upload.aab"
    blockers = []
    report = {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "package": PACKAGE,
        "source_version": source_version(root),
        "operator_details_complete": None,
        "operator_data_approval": None,
        "public_apk_available": None,
        "public_version_code": None,
        "aab_present": aab.is_file(),
        # Keep the existing consumer field; clarify that it is only file presence.
        "aab_built": aab.is_file(),
        "aab_built_evidence": "file_presence_only",
        "aab_artifact": {"path": str(aab)},
        "bundletool_valid": None,
        "bundle_validation": "not_run",
        "bundle_manifest": None,
        "bundle_requests_16k_zip_alignment": None,
        "native_libraries": None,
        "aab_signature_valid": None,
        "debug_certificate_detected": None,
        "store_texts_prepared": False,
        "store_text_lengths": {},
        "play_upload_performed": False,
        "physical_device_test": "not_recorded",
        "live_push_delivery": "not_recorded",
    }
    for key, url in (("legal", "https://schulpilot.dorfspy.de/api/legal"), ("release", "https://schulpilot.dorfspy.de/api/app-release")):
        try:
            data = fetch(url)
            if key == "legal":
                report["operator_details_complete"] = data.get("complete")
                report["operator_data_approval"] = data.get("operator_data_approval")
                if data.get("complete") is not True:
                    blockers.append("operator_details_incomplete_or_unknown")
            else:
                report["public_apk_available"] = data.get("available", False)
                report["public_version_code"] = data.get("version_code")
                if data.get("available") is not True:
                    blockers.append("public_apk_unavailable")
        except (OSError, ValueError, urllib.error.URLError):
            blockers.append(key + "_endpoint_unavailable_or_invalid")
    for name, limit in TEXT_LIMITS.items():
        path = root / ("store/de-DE/" + name + ".txt")
        try:
            content = path.read_text(encoding="utf-8").strip()
            report["store_text_lengths"][name] = len(content)
            if not content or len(content) > limit:
                blockers.append("store_text_invalid_" + name)
        except (OSError, UnicodeError):
            report["store_text_lengths"][name] = None
            blockers.append("store_text_missing_or_unreadable_" + name)
    report["store_texts_prepared"] = not any(code.startswith("store_text_") for code in blockers)
    if not aab.is_file():
        blockers.append("aab_missing")
    else:
        try:
            digest = hashlib.sha256()
            with aab.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            report["aab_artifact"].update(size_bytes=aab.stat().st_size, sha256=digest.hexdigest())
            report["native_libraries"] = inspect_native_libraries(aab)
            if report["native_libraries"]["elf64_alignment_16k"] is not True:
                blockers.append("native_elf64_alignment_missing_or_invalid")
        except (OSError, ValueError, zipfile.BadZipFile, struct.error, RuntimeError):
            blockers.append("aab_native_libraries_unreadable")
        if bundletool is None:
            blockers.append("bundletool_not_provided")
        elif not Path(bundletool).is_file():
            report["bundle_validation"] = "tool_missing"
            blockers.append("bundletool_missing")
        else:
            base_command = ["java", "-jar", str(Path(bundletool).resolve())]
            try:
                validation = runner(base_command + ["validate", "--bundle=" + str(aab)])
                report["bundletool_valid"] = validation.returncode == 0
                report["bundle_validation"] = "passed" if validation.returncode == 0 else "failed"
                if validation.returncode:
                    blockers.append("bundletool_validation_failed")
                else:
                    manifest_result = runner(base_command + ["dump", "manifest", "--bundle=" + str(aab), "--module=base"])
                    if manifest_result.returncode:
                        blockers.append("bundle_manifest_unreadable")
                    else:
                        metadata = parse_manifest(manifest_result.stdout)
                        report["bundle_manifest"] = metadata
                        if metadata["package"] != PACKAGE:
                            blockers.append("bundle_package_mismatch")
                        if metadata["target_sdk"] is None or metadata["target_sdk"] < MIN_TARGET_API:
                            blockers.append("bundle_target_api_below_36_or_unknown")
                        if metadata["direct_installer_permission"]:
                            blockers.append("play_bundle_has_direct_installer_permission")
                        if metadata["debuggable"]:
                            blockers.append("play_bundle_is_debuggable")
                        source = report["source_version"]
                        if source is None or source["code"] != metadata["version_code"] or source["name"] != metadata["version_name"]:
                            blockers.append("bundle_source_version_mismatch_or_unknown")
                    config = runner(base_command + ["dump", "config", "--bundle=" + str(aab)])
                    report["bundle_requests_16k_zip_alignment"] = config.returncode == 0 and "PAGE_ALIGNMENT_16K" in config.stdout
                    if report["bundle_requests_16k_zip_alignment"] is not True:
                        blockers.append("bundle_16k_zip_alignment_missing_or_unknown")
            except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError):
                if report["bundletool_valid"] is None:
                    report["bundle_validation"] = "tool_error"
                blockers.append("bundletool_execution_or_manifest_error")
        try:
            if shutil.which("jarsigner"):
                signature = runner(["jarsigner", "-J-Duser.language=en", "-J-Duser.country=US", "-verify", str(aab)])
                output = signature.stdout.lower()
                report["aab_signature_valid"] = signature.returncode == 0 and "jar verified." in output and "unsigned entries" not in output
                if report["aab_signature_valid"] is not True:
                    blockers.append("aab_signature_invalid_or_unsigned")
            else:
                blockers.append("jarsigner_unavailable")
            if shutil.which("keytool"):
                certificate = runner(["keytool", "-J-Duser.language=en", "-J-Duser.country=US", "-printcert", "-jarfile", str(aab)])
                if certificate.returncode == 0 and "Owner:" in certificate.stdout:
                    report["debug_certificate_detected"] = bool(re.search(r"\bCN\s*=\s*Android\s*Debug\b", certificate.stdout, re.IGNORECASE))
                    if report["debug_certificate_detected"]:
                        blockers.append("aab_signed_with_android_debug_certificate")
                else:
                    blockers.append("aab_certificate_unreadable")
            else:
                blockers.append("keytool_unavailable")
        except (OSError, subprocess.SubprocessError):
            blockers.append("aab_signature_tool_error")
    report["blockers"] = sorted(set(blockers))
    report["local_preflight_passed"] = not report["blockers"]
    report["evidence_limits"] = [
        "aab_built is retained for compatibility and indicates file presence only.",
        "Bundle zip alignment and native ELF alignment are separate checks; neither is a 16-KB runtime test.",
        "This report does not verify Play Console approval, account testing eligibility or actual FCM delivery.",
    ]
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundletool", type=Path)
    parser.add_argument("--aab", type=Path, help="The actual Play-flavor upload bundle to inspect")
    parser.add_argument("--output", type=Path, default=Path("artifacts/google-readiness.json"))
    parser.add_argument("--strict", action="store_true", help="Exit nonzero when local release blockers remain")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    report = build_report(root, aab_path=args.aab, bundletool=args.bundletool)
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 1 if args.strict and report["blockers"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
