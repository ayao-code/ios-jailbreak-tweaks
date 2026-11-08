#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/.." && pwd)
sdk=${IOS_SDK_PATH:-"$HOME/theos/sdks/iPhoneOS16.5.sdk"}
mkdir -p "$project_dir/build"
binary="$project_dir/build/keychain-metadata"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation -lsqlite3 \
    "$tool_dir/keychain-metadata.m" -o "$binary"
ldid -S"$tool_dir/metadata-entitlements.plist" "$binary"
printf '%s\n' "$binary"
