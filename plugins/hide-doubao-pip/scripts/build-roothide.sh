#!/bin/sh
set -eu

project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export THEOS=${THEOS:-"$HOME/theos"}
version=$(sed -n 's/^Version: //p' "$project/control")
stage=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT INT TERM
library="$stage/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$library" "$stage/DEBIAN" "$project/packages"

# Do not overwrite the rootless release package or change its control file.
make -C "$project" clean
make -C "$project" all ARCHS=arm64e FINALPACKAGE=1
for module in HideDoubaoPiP DoubaoNoJump; do
    source="$project/.theos/obj/$module.dylib"
    test -f "$source"
    destination="$library/$module.dylib"
    cp "$source" "$destination"
    xcrun install_name_tool \
        -id "@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/$module.dylib" \
        -change /var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
        @loader_path/.jbroot/usr/lib/libsubstrate.dylib \
        -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
        @loader_path/.jbroot/usr/lib/libsubstrate.dylib \
        -change @rpath/CydiaSubstrate.framework/CydiaSubstrate \
        @loader_path/.jbroot/usr/lib/libsubstrate.dylib \
        "$destination"
    if xcrun otool -L "$destination" | grep -q '@rpath/CydiaSubstrate\|/var/jb/'; then
        echo "unconverted rootless dependency in $module" >&2
        exit 1
    fi
    ldid -S "$destination"
    cp "$project/$module.plist" "$library/$module.plist"
    # ElleKit filters on the inspected RootHide device are binary plists.
    # Preserve their serializer, not the unrelated RootHideConfig format.
    plutil -convert binary1 "$library/$module.plist"
done
sed -e "s/^Version:.*/Version: $version/" \
    -e 's/^Architecture:.*/Architecture: iphoneos-arm64e/' \
    "$project/control" > "$stage/DEBIAN/control"
dpkg-deb --build --root-owner-group "$stage" \
    "$project/packages/ayao.hidedoubaopip_${version}_iphoneos-arm64e.deb"
