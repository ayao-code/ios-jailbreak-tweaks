#!/bin/bash
# Build only. No installation, trustcache edits or device mutation.
set -euo pipefail
tool_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$tool_dir/../../.." && pwd)
sdk=${IOS_SDK_PATH:-$HOME/theos/sdks/iPhoneOS16.5.sdk}
output=${1:-"$repo/app/safe-domain-probe/build/render-performance-debug"}
mkdir -p "$(dirname "$output")"
python3 - "$repo/scripts/tools/crane-healthcheck/entitlements.plist" "$output.entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
# The debug entitlement grants reading render statistics. No debug option is set.
entitlements['com.apple.QuartzCore.debug'] = True
with open(sys.argv[2], 'wb') as target:
    plistlib.dump(entitlements, target)
PY
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation "$tool_dir/main.m" -o "$output"
ldid -S"$output.entitlements.plist" "$output"
printf '%s\n' "$output"
