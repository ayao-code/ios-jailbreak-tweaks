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
cp "$project/Broker/postinst" "$project/Broker/prerm" "$stage/DEBIAN/"
chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm"
cp -R "$project/.theos/obj/FeilianControlCenter.bundle" "$stage/Library/ControlCenter/Bundles/"
for helper in EasyVPNConnectionHelper FeilianConnectionHelper MultiVPNConnectionHelper; do
  cp "$project/.theos/obj/$helper.dylib" "$project/$helper.plist" "$stage/Library/MobileSubstrate/DynamicLibraries/"
done
version=$(sed -n 's/^Version: //p' "$project/control")
dpkg-deb --build --root-owner-group "$stage" "$project/packages/ayao.feiliancontrolcenter_${version}_iphoneos-arm64e.deb"
