#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir=${1:?usage: build.sh absolute-output-directory}
mkdir -p "$output_dir"
sdk=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
# This one-shot helper uses MRC to avoid newer ARC runtime imports from the
# host compiler. All retained helper objects die when this process exits.
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" \
    -fno-objc-arc -fblocks -O1 -Wall -Wextra -Werror -framework Foundation \
    -Wl,-rpath,@executable_path/.jbroot/usr/lib \
    -Wl,-rpath,@executable_path/.jbroot/Library/Frameworks \
    "$source_dir/main.m" -o "$output_dir/crane-healthcheck"
ldid -S"$source_dir/entitlements.plist" "$output_dir/crane-healthcheck"
