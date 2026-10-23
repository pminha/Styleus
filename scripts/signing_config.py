"""Private, per-checkout signing configuration for the public Xcode project."""

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path


TARGETS = {"StyleusPad": "IPAD", "StyleusMac": "MAC"}
SETTING_NAMES = {
    "PRODUCT_BUNDLE_IDENTIFIER": "BUNDLE_ID",
    "DEVELOPMENT_TEAM": "DEVELOPMENT_TEAM",
    "CODE_SIGN_STYLE": "CODE_SIGN_STYLE",
    "CODE_SIGN_IDENTITY": "CODE_SIGN_IDENTITY",
    "PROVISIONING_PROFILE_SPECIFIER": "PROFILE_SPECIFIER",
}
DEFAULTS = {
    "STYLEUS_IPAD_BUNDLE_ID": "com.example.styleus.ipad",
    "STYLEUS_MAC_BUNDLE_ID": "com.example.styleus.mac",
    "STYLEUS_IPAD_DEVELOPMENT_TEAM": "",
    "STYLEUS_MAC_DEVELOPMENT_TEAM": "",
    "STYLEUS_IPAD_CODE_SIGN_STYLE": "Automatic",
    "STYLEUS_MAC_CODE_SIGN_STYLE": "Manual",
    "STYLEUS_IPAD_CODE_SIGN_IDENTITY": "Apple Development",
    "STYLEUS_MAC_CODE_SIGN_IDENTITY": "-",
    "STYLEUS_IPAD_PROFILE_SPECIFIER": "",
    "STYLEUS_MAC_PROFILE_SPECIFIER": "",
}


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def variable(target, setting):
    return f"STYLEUS_{TARGETS[target]}_{SETTING_NAMES[setting]}"


def read_project(path):
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def extract_project_signing(project):
    """Capture literal Xcode UI choices without baking them into the generator.

    Debug/Release signing must agree because the private override applies to both.
    Public variable references are skipped so a second import retains local data.
    """
    values = {}
    objects = project.get("objects", {})
    for target in TARGETS:
        configurations = [
            objects.get(identifier(f"{target}:{config}"), {}).get("buildSettings", {})
            for config in ("Debug", "Release")
        ]
        for configuration in configurations:
            for key, value in configuration.items():
                if any(key.startswith(setting + "[") for setting in SETTING_NAMES):
                    raise ValueError(
                        f"{target} has conditional signing settings; resolve them before importing."
                    )
                if key in SETTING_NAMES and ("$(" in str(value) or "${" in str(value)):
                    if str(value) != f"$({variable(target, key)})":
                        raise ValueError(
                            f"{target} {key} uses a custom variable. "
                            "Use --team and --bundle-prefix, or preserve that custom configuration manually."
                        )
        for setting in SETTING_NAMES:
            literals = {
                str(config[setting]) for config in configurations
                if setting in config and "$(" not in str(config[setting])
            }
            if len(literals) > 1:
                raise ValueError(
                    f"{target} has different Debug/Release {setting} values; "
                    "make the signing settings agree before importing."
                )
            if literals:
                values[variable(target, setting)] = literals.pop()
    return values


def read_local(path):
    if not path.exists():
        return {}
    values = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = re.fullmatch(r"\s*(STYLEUS_[A-Z_]+)\s*=\s*(.*?)\s*", line)
        if match and match[1] in DEFAULTS:
            values[match[1]] = match[2]
        else:
            raise ValueError(
                "Config/Local.xcconfig contains custom settings or includes. "
                "Preserve/edit that file manually; it has not been changed."
            )
    return values


def write_local(path, values):
    """Write only recognized build settings, using private file permissions."""
    for key, value in values.items():
        if key not in DEFAULTS or any(char in str(value) for char in "\r\n\x00"):
            raise ValueError("Invalid local signing setting.")
    path.parent.mkdir(parents=True, exist_ok=True)
    content = (
        "// Private signing for this checkout. Never commit or share this file.\n"
        "// Reuse it and the same Apple Account to renew the existing iPad app.\n"
        + "".join(f"{key} = {values.get(key, default)}\n" for key, default in DEFAULTS.items())
    )
    # O_TRUNC preserves the inode; fchmod also protects a previously copied file.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(content)


def configure_personal_team(team, prefix):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Team ID must contain 10 uppercase letters or digits.")
    if len(prefix.split(".")) < 2 or not all(
        re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", part) for part in prefix.split(".")
    ):
        raise ValueError("Use a unique reverse-domain bundle prefix, such as org.youralias.styleus.")
    values = {}
    for target, suffix in (("StyleusPad", "ipad"), ("StyleusMac", "mac")):
        values.update({
            variable(target, "PRODUCT_BUNDLE_IDENTIFIER"): f"{prefix}.{suffix}",
            variable(target, "DEVELOPMENT_TEAM"): team,
            variable(target, "CODE_SIGN_STYLE"): "Automatic",
            variable(target, "CODE_SIGN_IDENTITY"): "Apple Development",
            variable(target, "PROVISIONING_PROFILE_SPECIFIER"): "",
        })
    return values
