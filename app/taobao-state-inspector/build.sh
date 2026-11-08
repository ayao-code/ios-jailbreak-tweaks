#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
sdk=${IOS_SDK_PATH:-}
if [ -z "$sdk" ]; then
    sdk=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
fi
if [ -z "$sdk" ]; then
    sdk="$HOME/theos/sdks/iPhoneOS16.5.sdk"
fi
if [ ! -d "$sdk/System/Library/Frameworks/UIKit.framework" ]; then
    printf 'iPhoneOS SDK unavailable; set IOS_SDK_PATH\n' >&2
    exit 1
fi
output_dir="$project_dir/build"
mkdir -p "$output_dir"
package_dir=$(mktemp -d "$output_dir/package.XXXXXX")
app_dir="$package_dir/Payload/TaobaoStateInspector.app"
mkdir -p "$app_dir"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Foundation -framework UIKit -framework Security -framework LocalAuthentication \
    "$project_dir/main.m" "$project_dir/StateReport.m" -o "$app_dir/TaobaoStateInspector"
cp "$project_dir/Info.plist" "$app_dir/Info.plist"
plutil -lint "$app_dir/Info.plist" "$project_dir/entitlements.plist"
codesign --force --sign - --entitlements "$project_dir/entitlements.plist" "$app_dir"
codesign --verify --strict "$app_dir"
archive="$output_dir/TaobaoStateInspector-0.1.0-$(date +%Y%m%d-%H%M%S).ipa"
(cd "$package_dir" && zip -qry "$archive" Payload)
shasum -a 256 "$archive"
printf 'BUILD_ONLY: ad-hoc signed for user-authorized TrollStore installation; runtime unverified\n'
printf '%s\n' "$archive"
