#!/bin/zsh
set -eu
cd "${0:A:h:h}"
styleus_check_only=0
styleus_configuration=Debug
styleus_usage='Usage: zsh scripts/build.sh [--release] [--check-only]'
if (( $# == 1 )) && [[ "$1" == '--help' || "$1" == '-h' ]]; then
  print "$styleus_usage"
  print 'Build both native apps; the iPad compile checks are unsigned.'
  print -- '--release selects the optimized Release configuration. The default is Debug.'
  print -- '--check-only does not replace dist/Styleus Mac.app or require quitting it.'
  print 'To install or renew on an iPad, use scripts/install-ipad.sh DEVICE_ID_OR_NAME.'
  exit 0
fi
for styleus_option in "$@"; do
  case "$styleus_option" in
    --release) styleus_configuration=Release ;;
    --check-only) styleus_check_only=1 ;;
    *) print -u2 "$styleus_usage"; exit 2 ;;
  esac
done
if (( ! styleus_check_only )) && pgrep -x 'Styleus Mac' >/dev/null 2>&1; then
  print -u2 'Quit Styleus from its Mac menu-bar menu before replacing the app. Closing its window is not enough.'
  exit 1
fi
mkdir -p build
if ! xcodebuild -project Styleus.xcodeproj -scheme StyleusMac -configuration "$styleus_configuration" \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' -allowProvisioningUpdates build > build/mac-build.log 2>&1; then
  print -u2 'Mac build failed. See build/mac-build.log and SETUP.md.'
  exit 1
fi
if ! xcodebuild -project Styleus.xcodeproj -target StyleusPad -configuration "$styleus_configuration" -sdk iphoneos \
  "SYMROOT=$PWD/build/UnsignedDeviceBuild/Products" "OBJROOT=$PWD/build/UnsignedDeviceBuild/Intermediates" \
  "MODULE_CACHE_DIR=$PWD/build/UnsignedDeviceBuild/ModuleCache" \
  "CONFIGURATION_BUILD_DIR=$PWD/build/iPadDerivedData/Build/Products/${styleus_configuration}-iphoneos" \
  CODE_SIGNING_ALLOWED=NO build > build/ipad-build.log 2>&1; then
  print -u2 'iPad device compile check failed. See build/ipad-build.log.'
  exit 1
fi
if ! xcodebuild -project Styleus.xcodeproj -target StyleusPad -configuration "$styleus_configuration" -sdk iphonesimulator \
  "SYMROOT=$PWD/build/SimulatorTargetBuild/Products" "OBJROOT=$PWD/build/SimulatorTargetBuild/Intermediates" \
  "MODULE_CACHE_DIR=$PWD/build/SimulatorTargetBuild/ModuleCache" \
  "CONFIGURATION_BUILD_DIR=$PWD/build/SimulatorDerivedData/Build/Products/${styleus_configuration}-iphonesimulator" \
  CODE_SIGNING_ALLOWED=NO build > build/simulator-build.log 2>&1; then
  print -u2 'iPad simulator compile check failed. See build/simulator-build.log.'
  exit 1
fi
if (( styleus_check_only )); then
  print 'Mac, iPad device and iPad simulator builds passed. Existing dist apps were not replaced.'
  exit 0
fi
mkdir -p dist
xcrun swift -module-cache-path "$PWD/build/ModuleCache" scripts/replace_mac_bundle.swift \
  "build/DerivedData/Build/Products/$styleus_configuration/Styleus Mac.app" 'dist/Styleus Mac.app'
print 'Builds passed. Mac app: dist/Styleus Mac.app'
print 'The iPad build is unsigned. Use Xcode Personal Team signing to install it.'
