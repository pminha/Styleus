#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/build/ModuleCache"
swift test --scratch-path build/swift-tests --cache-path build/swift-cache \
  --config-path build/swift-config --security-path build/swift-security --disable-sandbox "$@"
