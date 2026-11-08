#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
sdk=${IOS_SDK_PATH:-$HOME/theos/sdks/iPhoneOS16.5.sdk}
variant=${1:-minimal}
if [ "$variant" != minimal ] && [ "$variant" != display ]; then
    printf 'usage: build.sh [minimal|display]\n' >&2
    exit 2
fi
mkdir -p "$project_dir/build"
output="$project_dir/build/screen-observe-$variant"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" \
    -fobjc-arc -O2 -Wall -Wextra -Werror -framework Foundation -framework UIKit \
    -framework QuartzCore -framework IOSurface -framework CoreGraphics \
    -F"$sdk/System/Library/PrivateFrameworks" -framework SpringBoardServices \
    "$tool_dir/main.m" -o "$output"
if [ "$variant" = display ]; then
    plutil -lint "$tool_dir/display-entitlements.plist"
    ldid -S"$tool_dir/display-entitlements.plist" "$output"
else
    ldid -S "$output"
fi
printf '%s\n' "$output"
