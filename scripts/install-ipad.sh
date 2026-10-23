#!/bin/zsh
# Build current source and renew/install using the same private Personal Team setup.
set -eu
cd "${0:A:h:h}"
if (( $# == 1 )) && [[ "$1" == '--help' || "$1" == '-h' ]]; then
  print 'Usage: zsh scripts/install-ipad.sh DEVICE_ID_OR_NAME'
  print 'List devices with: xcrun devicectl list devices'
  print 'Configure your own Personal Team first; see SETUP.md.'
  print 'Renew using the same checkout, Apple Account and bundle identifiers.'
  exit 0
fi
if (( $# != 1 )) || [[ -z "$1" || "$1" == -* ]]; then
  print -u2 'Usage: zsh scripts/install-ipad.sh DEVICE_ID_OR_NAME'
  print -u2 'Specify the trusted, unlocked iPad explicitly. List devices with: xcrun devicectl list devices'
  exit 2
fi
styleus_device="$1"
mkdir -p build
print 'Checking your iPad signing configuration…'
if ! xcodebuild -project Styleus.xcodeproj -target StyleusPad -configuration Debug -sdk iphoneos \
  -showBuildSettings -json > build/ipad-signing-settings.local.json 2> build/ipad-signing-check.log; then
  print -u2 'Could not read signing settings. Check Xcode selection and build/ipad-signing-check.log.'
  exit 1
fi
if ! python3 - <<'PY'
import json
import sys
from pathlib import Path
entries = json.loads(Path('build/ipad-signing-settings.local.json').read_text())
settings = next(entry['buildSettings'] for entry in entries if entry['target'] == 'StyleusPad')
team = settings.get('DEVELOPMENT_TEAM', '').strip()
bundle = settings.get('PRODUCT_BUNDLE_IDENTIFIER', '').strip()
if not team or not bundle or bundle == 'com.example.styleus.ipad':
    print('Choose your own Personal Team and unique bundle prefix first; see SETUP.md.', file=sys.stderr)
    sys.exit(1)
PY
then
  exit 1
fi
print 'Building and signing with your configured Xcode team…'
if ! xcodebuild -project Styleus.xcodeproj -target StyleusPad -configuration Debug -sdk iphoneos \
  -allowProvisioningUpdates "SYMROOT=$PWD/build/DeviceTargetBuild/Products" \
  "OBJROOT=$PWD/build/DeviceTargetBuild/Intermediates" \
  "MODULE_CACHE_DIR=$PWD/build/DeviceTargetBuild/ModuleCache" \
  "CONFIGURATION_BUILD_DIR=$PWD/build/SignediPadDerivedData/Build/Products/Debug-iphoneos" \
  build > build/ipad-signed-build.log 2>&1; then
  print -u2 'Signing/build failed. See build/ipad-signed-build.log and Signing & Capabilities in Xcode.'
  exit 1
fi
styleus_app='build/SignediPadDerivedData/Build/Products/Debug-iphoneos/Styleus iPad.app'
styleus_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$styleus_app/Info.plist")
print 'Installing on the trusted, unlocked iPad…'
xcrun devicectl device install app --device "$styleus_device" "$styleus_app" --timeout 60
print 'Opening Styleus…'
xcrun devicectl device process launch --device "$styleus_device" --terminate-existing "$styleus_bundle" --timeout 30
print 'For renewal, rerun this script with the same project and bundle identifier.'
