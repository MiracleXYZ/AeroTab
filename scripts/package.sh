#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="build/AeroTab.app"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
test "$(plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist")" = "$version"
architecture="$(lipo -archs "$bundle/Contents/MacOS/AeroTab")"
case "$architecture" in arm64|x86_64) ;; *) echo "Expected one architecture, got: $architecture" >&2; exit 1 ;; esac
codesign --verify --strict "$bundle"
archive="build/AeroTab-$version-$architecture.zip"
ditto -c -k --keepParent --norsrc --noextattr "$bundle" "$archive"
echo "Packaged: $archive"
