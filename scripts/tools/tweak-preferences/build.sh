#!/bin/sh
set -eu

source_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
sdk_dir=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
output_dir="$source_dir/build"
mkdir -p "$output_dir"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk_dir" \
    -fobjc-arc -O2 -Wall -Wextra -Werror \
    -framework Foundation -framework CoreFoundation \
    "$source_dir/main.m" -o "$output_dir/tweak-preferences"
ldid -S"$source_dir/entitlements.plist" "$output_dir/tweak-preferences"
printf '%s\n' "$output_dir/tweak-preferences"
