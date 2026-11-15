#!/bin/bash
set -euo pipefail
project=$(cd "$(dirname "$0")" && pwd)
sdk=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
output=${1:?usage: build.sh OUTPUT_DIRECTORY}
mkdir -p "$output" "$project/../packages"
for arch in arm64 arm64e; do
  xcrun clang -target "$arch-apple-ios16.0" -isysroot "$sdk" \
    -fobjc-arc -O2 -Wall -Wextra -Werror -dynamiclib \
    -framework Foundation -framework UIKit -framework NetworkExtension \
    -Wl,-install_name,@rpath/EasyVPNNativeHelper.dylib -Wl,-headerpad_max_install_names \
    -Wl,-rpath,/var/jb/Library/Frameworks -Wl,-rpath,/var/jb/usr/lib \
    -Wl,-rpath,@loader_path/.jbroot/Library/Frameworks -Wl,-rpath,@loader_path/.jbroot/usr/lib \
    -F"${THEOS:-"$HOME/theos"}/vendor/lib" -framework CydiaSubstrate \
    "$project/EasyVPNNativeHelper.m" -o "$output/helper-$arch.dylib"
done
for arch in arm64 arm64e; do
  xcrun install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
    @rpath/CydiaSubstrate.framework/CydiaSubstrate "$output/helper-$arch.dylib"
done
xcrun lipo -create "$output/helper-arm64.dylib" "$output/helper-arm64e.dylib" \
  -output "$output/EasyVPNNativeHelper.dylib"
ldid -S "$output/EasyVPNNativeHelper.dylib"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Werror -framework Foundation \
  "$project/native-probe.m" -o "$output/native-probe"
ldid -S"$project/probe-entitlements.plist" "$output/native-probe"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
mkdir -p "$stage/DEBIAN" "$stage/Library/MobileSubstrate/DynamicLibraries"
cp "$project/control" "$stage/DEBIAN/control"
cp "$output/EasyVPNNativeHelper.dylib" "$project/EasyVPNNativeHelper.plist" \
  "$stage/Library/MobileSubstrate/DynamicLibraries/"
dpkg-deb --build --root-owner-group "$stage" \
  "$project/../packages/ayao.easyvpnnativehelper_0.1.0~test1_iphoneos-arm64e.deb"
