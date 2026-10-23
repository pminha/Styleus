#!/usr/bin/env python3
"""Keep personal signing choices in an ignored file, outside the public project."""

import argparse
import subprocess
import sys
from pathlib import Path

from signing_config import (
    configure_personal_team, extract_project_signing, read_local, read_project, write_local,
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", help="your 10-character Personal Team ID from Xcode")
    parser.add_argument("--bundle-prefix", help="a unique prefix, for example org.youralias.styleus")
    parser.add_argument(
        "--import-xcode", action="store_true",
        help="save current target signing choices from Xcode, then regenerate the public project",
    )
    args = parser.parse_args()
    if args.import_xcode == bool(args.team or args.bundle_prefix):
        parser.error("choose either --import-xcode or both --team and --bundle-prefix")
    if not args.import_xcode and not (args.team and args.bundle_prefix):
        parser.error("--team and --bundle-prefix are required together")
    root = Path(__file__).resolve().parents[1]
    local = root / "Config/Local.xcconfig"
    try:
        values = read_local(local)
        if args.import_xcode:
            values.update(extract_project_signing(read_project(root / "Styleus.xcodeproj/project.pbxproj")))
        else:
            values.update(configure_personal_team(args.team, args.bundle_prefix))
        write_local(local, values)
        subprocess.run([sys.executable, str(root / "scripts/generate_project.py")], check=True)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Avoid dumping Xcode/plutil output that may contain personal signing data.
        if isinstance(error, ValueError):
            parser.error(str(error))
        print("Could not configure signing. Check project/local file permissions and Xcode tools.", file=sys.stderr)
        return 1
    print("Saved private signing in Config/Local.xcconfig. Reopen the project in Xcode.")
    print("Keep this file, Apple Account and bundle identifiers unchanged when renewing the iPad app.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
