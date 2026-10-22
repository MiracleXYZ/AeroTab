#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;; esac
./scripts/swift-env.sh build -c "$configuration"
binary_dir="$(./scripts/swift-env.sh build -c "$configuration" --show-bin-path)"
bundle="$PWD/build/AeroTab.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/AeroTab" "$bundle/Contents/MacOS/AeroTab"
if [ "$configuration" = release ]; then
    # Debug-map entries contain absolute paths from the build machine.
    xcrun strip -S "$bundle/Contents/MacOS/AeroTab"
fi
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp LICENSE "$bundle/Contents/Resources/LICENSE"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$bundle/Contents/Resources/"
icon_workdir="$(mktemp -d "${TMPDIR:-/tmp}/aerotab-icon.XXXXXX")"
trap 'rm -rf "$icon_workdir"' EXIT
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift scripts/GenerateIcon.swift "$icon_workdir/AeroTab.iconset"
iconutil -c icns "$icon_workdir/AeroTab.iconset" -o "$bundle/Contents/Resources/AeroTab.icns"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$bundle"
codesign --verify --strict "$bundle"
echo "Built: $bundle"
echo "Launch when ready: open -g \"$bundle\""
