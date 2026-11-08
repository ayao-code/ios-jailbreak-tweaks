#!/bin/sh
set -eu
tool=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:?usage: build.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
sdk=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -framework Foundation "$tool/main.m" -o "$output/focus-state-readonly"
ldid -S"$tool/entitlements.plist" "$output/focus-state-readonly"
