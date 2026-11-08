#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_arch=${PACKAGE_ARCH:-iphoneos-arm64}
base_package="$project_dir/packages/ayao.photosrecentssort_0.2.6_${package_arch}.deb"
output_package="$project_dir/packages/ayao.photosrecentssort_0.2.9_${package_arch}.deb"
cr3_dylib="$project_dir/CR3PreviewCompat/.theos/obj/CR3PreviewCompat.dylib"
control_center_bundle="$project_dir/ControlCenter/.theos/obj/PhotosAlbumControlCenter.bundle"

if [ ! -f "$cr3_dylib" ]; then
    cr3_dylib="$project_dir/CR3PreviewCompat/.theos/obj/debug/CR3PreviewCompat.dylib"
fi

if [ ! -f "$base_package" ] || [ ! -f "$cr3_dylib" ]; then
    echo "missing base package or CR3PreviewCompat.dylib" >&2
    exit 1
fi

if [ ! -d "$control_center_bundle" ]; then
    control_center_bundle="$project_dir/ControlCenter/.theos/obj/debug/PhotosAlbumControlCenter.bundle"
fi

if [ ! -d "$control_center_bundle" ]; then
    echo "missing PhotosAlbumControlCenter.bundle" >&2
    exit 1
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/photos-enhanced.XXXXXX")
cleanup() {
    find "$build_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

dpkg-deb -R "$base_package" "$build_dir"
if [ -d "$build_dir/var/jb" ]; then
    install_root="$build_dir/var/jb"
else
    install_root="$build_dir"
fi

cp "$project_dir/Preferences/Resources/Root.plist" \
   "$install_root/Library/PreferenceBundles/PhotosRecentsSortPrefs.bundle/Root.plist"
cp "$cr3_dylib" \
   "$install_root/Library/MobileSubstrate/DynamicLibraries/CR3PreviewCompat.dylib"
cp "$project_dir/CR3PreviewCompat/CR3PreviewCompat.plist" \
   "$install_root/Library/MobileSubstrate/DynamicLibraries/CR3PreviewCompat.plist"
mkdir -p "$install_root/Library/ControlCenter/Bundles"
cp -R "$control_center_bundle" \
   "$install_root/Library/ControlCenter/Bundles/PhotosAlbumControlCenter.bundle"

cat > "$build_dir/DEBIAN/control" <<'EOF'
Package: ayao.photosrecentssort
Name: Photos 增强
Version: 0.2.9
Architecture: iphoneos-arm64
Description: 照片 App 增强功能、控制中心相册入口，以及 Canon CR3 在照片、抖音和 Lightroom 中的预览兼容。
Maintainer: ayao
Author: ayao
Section: Tweaks
Depends: mobilesubstrate, preferenceloader, ellekit
Conflicts: ayao.cr3previewcompat
Replaces: ayao.cr3previewcompat
Provides: ayao.cr3previewcompat
EOF

sed -i.bak "s/^Architecture:.*/Architecture: ${package_arch}/" "$build_dir/DEBIAN/control"
rm -f "$build_dir/DEBIAN/control.bak"

dpkg-deb --build --root-owner-group "$build_dir" "$output_package"
echo "$output_package"
