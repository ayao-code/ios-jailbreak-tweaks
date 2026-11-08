#!/bin/bash
set -euo pipefail
tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/.." && pwd)
sdk=${IOS_SDK_PATH:-"$HOME/theos/sdks/iPhoneOS16.5.sdk"}
mkdir -p "$project_dir/build"
binary="$project_dir/build/alibaba-keychain-reset"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation \
    -framework Security -framework LocalAuthentication -framework MobileCoreServices \
    "$tool_dir/alibaba-keychain-reset.m" -o "$binary"
ldid -S"$tool_dir/alibaba-keychain-entitlements.plist" "$binary"
printf '%s\n' "$binary"
