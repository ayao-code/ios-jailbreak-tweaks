#!/bin/bash
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$project/../.." && pwd)
output=${1:?usage: build-test-tools.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
sdk=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
for tool in inspect vpn-test enable-module module-test; do
    sources=("$project/tools/$tool.m")
    if [[ $tool == vpn-test ]]; then sources+=("$project/FeilianVPNController.m"); fi
    frameworks=(-framework Foundation)
    if [[ $tool == module-test ]]; then frameworks+=(-framework UIKit); fi
    xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
        -Wall -Wextra -Werror -Wno-unused-parameter \
        "${frameworks[@]}" "${sources[@]}" -o "$output/feilian-$tool"
    # Standalone tools need the exact background-launch entitlement verified
    # against SpringBoard. The installed module inherits its existing host.
    ldid -S"$project/tools/background-entitlements.plist" "$output/feilian-$tool"
done
