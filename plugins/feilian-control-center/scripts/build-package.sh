#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export THEOS=${THEOS:-"$HOME/theos"}
make -C "$project" FINALPACKAGE=1
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM
chmod 755 "$stage"
mkdir -p "$stage/DEBIAN" "$stage/Library/ControlCenter/Bundles" "$project/packages"
mkdir -p "$stage/Library/MobileSubstrate/DynamicLibraries"
cp "$project/control" "$stage/DEBIAN/control"
cp -R "$project/.theos/obj/FeilianControlCenter.bundle" "$stage/Library/ControlCenter/Bundles/"
cp "$project/.theos/obj/FeilianConnectHelper.dylib" "$stage/Library/MobileSubstrate/DynamicLibraries/"
cp "$project/FeilianConnectHelper.plist" "$stage/Library/MobileSubstrate/DynamicLibraries/"
version=$(sed -n 's/^Version: //p' "$project/control")
dpkg-deb --build --root-owner-group "$stage" "$project/packages/ayao.feiliancontrolcenter_${version}_iphoneos-arm64e.deb"
