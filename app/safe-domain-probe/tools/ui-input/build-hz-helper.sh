#!/bin/bash
# Standalone, SMS/WeChat-only UI helper; does not inject into either app.
set -euo pipefail
tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
sdk=${IOS_SDK_PATH:-$HOME/theos/sdks/iPhoneOS16.5.sdk}
output="$project_dir/build/ui-input-hz"
mkdir -p "$project_dir/build"
python3 - "$tool_dir/entitlements.plist" "$output.entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
# Required for an independent console tool, not an app's sandbox.
entitlements.update({'com.apple.private.security.no-sandbox': True,
                     'com.apple.private.security.container-required': False})
with open(sys.argv[2], 'wb') as target:
    plistlib.dump(entitlements, target)
PY
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation -framework CFNetwork -framework IOKit \
    -F"$sdk/System/Library/PrivateFrameworks" -framework SpringBoardServices -framework FrontBoardServices \
    -DSDP_HZ_TEST_UI=1 "$tool_dir/main.m" -o "$output"
ldid -S"$output.entitlements.plist" "$output"
printf '%s\n' "$output"
