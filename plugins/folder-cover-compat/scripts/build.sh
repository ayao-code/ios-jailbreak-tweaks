#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export THEOS=${THEOS:-"$HOME/theos"}
output="$project/.build"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM
mkdir -p "$output" "$project/packages" "$stage/DEBIAN" "$stage/Library/MobileSubstrate/DynamicLibraries"
chmod 755 "$stage"
lib="$stage/Library/MobileSubstrate/DynamicLibraries/zzFolderCoverCompat.dylib"
xcrun clang -target arm64e-apple-ios16.3 \
    -isysroot "$THEOS/sdks/iPhoneOS16.5.sdk" -fno-objc-arc -fblocks \
    -O1 -Wall -Wextra -Werror -dynamiclib -framework Foundation -framework UIKit -framework CoreGraphics \
    -L"$THEOS/vendor/lib/iphone/rootless" \
    -F"$THEOS/vendor/lib/iphone/rootless" -framework CydiaSubstrate \
    "$project/Tweak.m" -o "$lib"
xcrun install_name_tool \
    -id @loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/zzFolderCoverCompat.dylib \
    -change /var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
    @loader_path/.jbroot/usr/lib/libsubstrate.dylib \
    -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
    @loader_path/.jbroot/usr/lib/libsubstrate.dylib \
    -change @rpath/CydiaSubstrate.framework/CydiaSubstrate \
    @loader_path/.jbroot/usr/lib/libsubstrate.dylib "$lib"
ldid -S "$lib"
cp "$project/zzFolderCoverCompat.plist" "$stage/Library/MobileSubstrate/DynamicLibraries/"
cp "$project/control" "$stage/DEBIAN/control"
cp "$lib" "$output/zzFolderCoverCompat.dylib"
version=$(sed -n 's/^Version: //p' "$project/control")
dpkg-deb --build --root-owner-group "$stage" "$project/packages/ayao.foldercovercompat_${version}_iphoneos-arm64e.deb"
