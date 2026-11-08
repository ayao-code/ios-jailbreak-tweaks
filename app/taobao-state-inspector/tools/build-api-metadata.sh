#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/.." && pwd)
sdk=${IOS_SDK_PATH:-"$HOME/theos/sdks/iPhoneOS16.5.sdk"}
mkdir -p "$project_dir/build"
binary="$project_dir/build/keychain-api-metadata"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation \
    -framework Security -framework LocalAuthentication \
    "$tool_dir/keychain-api-metadata.m" -o "$binary"
ldid -S"$project_dir/entitlements.plist" "$binary"
printf '%s\n' "$binary"
