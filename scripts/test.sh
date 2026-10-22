#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
if [ -d "$testing_frameworks/Testing.framework" ]; then
    exec ./scripts/swift-env.sh test --disable-xctest \
        -Xswiftc -F -Xswiftc "$testing_frameworks" \
        -Xlinker -rpath -Xlinker "$testing_frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" "$@"
fi
exec ./scripts/swift-env.sh test --disable-xctest "$@"
