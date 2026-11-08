#!/bin/bash
# Separate standalone helpers; no installation, system patching, or injection.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:?usage: build-native-store-helpers.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
sdk=${IOS_SDK_PATH:-$HOME/theos/sdks/iPhoneOS16.5.sdk}
python3 - "$repo" "$output" <<'PY'
import pathlib, plistlib, sys
repo, output = map(pathlib.Path, sys.argv[1:])
for name, source in [
    ('store-ui-input', 'app/safe-domain-probe/tools/ui-input/entitlements.plist'),
    ('store-screen', 'app/safe-domain-probe/tools/screen-observe/display-entitlements.plist'),
]:
    values = plistlib.loads((repo / source).read_bytes())
    values.update({'com.apple.private.security.no-sandbox': True,
                   'com.apple.private.security.container-required': False})
    (output / (name + '.entitlements.plist')).write_bytes(plistlib.dumps(values))
PY
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation -framework CFNetwork -framework IOKit \
    -F"$sdk/System/Library/PrivateFrameworks" -framework SpringBoardServices -framework FrontBoardServices \
    -DSDP_ALI_RESTORE_UI=1 "$repo/app/safe-domain-probe/tools/ui-input/main.m" -o "$output/store-ui-input"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation -framework UIKit -framework QuartzCore \
    -framework IOSurface -framework CoreGraphics -F"$sdk/System/Library/PrivateFrameworks" \
    -framework SpringBoardServices "$repo/app/safe-domain-probe/tools/screen-observe/main.m" -o "$output/store-screen"
for name in store-ui-input store-screen; do
    ldid -S"$output/$name.entitlements.plist" "$output/$name"
done
