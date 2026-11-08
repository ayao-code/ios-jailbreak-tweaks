#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
sdk=${IOS_SDK_PATH:-$HOME/theos/sdks/iPhoneOS16.5.sdk}
mkdir -p "$project_dir/build"
extra_flags=()
if [ "${SDP_ALI_RESTORE_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_ALI_RESTORE_UI=1")
fi
if [ "${SDP_COUPON_TEST_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_COUPON_TEST_UI=1")
fi
if [ "${SDP_QUNAR_TEST_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_QUNAR_TEST_UI=1")
fi
if [ "${SDP_TROLLSTORE_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_TROLLSTORE_UI=1")
fi
if [ "${SDP_ROOTHIDE_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_ROOTHIDE_UI=1")
fi
if [ "${SDP_INJECT_MANAGER_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_INJECT_MANAGER_UI=1")
fi
if [ "${SDP_SETTINGS_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_SETTINGS_UI=1")
fi
if [ "${SDP_DAMAI_TEST_UI:-0}" = 1 ]; then
    extra_flags+=("-DSDP_DAMAI_TEST_UI=1")
fi
if [ "${#extra_flags[@]}" -eq 0 ]; then
    extra_flags+=("-DSDP_DEFAULT_UI=1")
fi
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation -framework CFNetwork -framework IOKit \
    -F"$sdk/System/Library/PrivateFrameworks" -framework SpringBoardServices -framework FrontBoardServices \
    "${extra_flags[@]}" "$tool_dir/main.m" -o "$project_dir/build/ui-input"
plutil -lint "$tool_dir/entitlements.plist"
ldid -S"$tool_dir/entitlements.plist" "$project_dir/build/ui-input"
printf '%s\n' "$project_dir/build/ui-input"
