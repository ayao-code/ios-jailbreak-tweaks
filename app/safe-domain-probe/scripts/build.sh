#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-ios}
output_dir="$project_dir/build"
mkdir -p "$output_dir"

if [ "$mode" = audit ]; then
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
        "$project_dir/audit-filters.m" -o "$output_dir/audit-filters"
    printf '%s\n' "$output_dir/audit-filters"
    exit 0
fi
if [ "$mode" = host ]; then
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
        -framework Foundation -framework Security \
        "$project_dir/ProbeReport.m" "$project_dir/host-main.m" \
        -o "$output_dir/probe-host"
    printf '%s\n' "$output_dir/probe-host"
    exit 0
fi
if [ "$mode" != ios ]; then
    printf 'usage: bash scripts/build.sh [ios|host|audit]\n' >&2
    exit 2
fi

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

package_dir=$(mktemp -d "$output_dir/package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
app_dir="$package_dir/Payload/SafeDomainProbe.app"
extension_dir="$app_dir/PlugIns/SafeDomainProbeShare.appex"
mkdir -p "$extension_dir"
common_flags=(-target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2
    -Wall -Wextra -Werror -Wno-unused-parameter -framework Foundation
    -framework UIKit -framework Security)
xcrun clang "${common_flags[@]}" "$project_dir/ProbeReport.m" "$project_dir/main.m" \
    -o "$app_dir/SafeDomainProbe"
xcrun clang "${common_flags[@]}" -DSDP_APP_EXTENSION=1 \
    -fapplication-extension -Wl,-application_extension \
    "$project_dir/ProbeReport.m" "$project_dir/ShareExtension.m" \
    -o "$extension_dir/SafeDomainProbeShare"
cp "$project_dir/Resources/Info.plist" "$app_dir/Info.plist"
cp "$project_dir/Resources/ShareInfo.plist" "$extension_dir/Info.plist"
plutil -lint "$app_dir/Info.plist" "$extension_dir/Info.plist"
archive="$output_dir/SafeDomainProbe-0.1.6-unsigned.ipa"
rm -f "$archive"
(cd "$package_dir" && zip -qry "$archive" Payload)
shasum -a 256 "$archive"
printf 'BUILD_ONLY: not provisioned, not installed, not ordinary-sandbox runtime evidence\n'
