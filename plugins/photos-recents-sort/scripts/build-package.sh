#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base_package="$project_dir/packages/ayao.photosrecentssort_0.1.0_iphoneos-arm64.deb"
output_package="$project_dir/packages/ayao.photosrecentssort_0.2.0_iphoneos-arm64.deb"
cr3_dylib="$project_dir/CR3PreviewCompat/.theos/obj/CR3PreviewCompat.dylib"

if [ ! -f "$cr3_dylib" ]; then
    cr3_dylib="$project_dir/CR3PreviewCompat/.theos/obj/debug/CR3PreviewCompat.dylib"
fi

if [ ! -f "$base_package" ] || [ ! -f "$cr3_dylib" ]; then
    echo "missing base package or CR3PreviewCompat.dylib" >&2
    exit 1
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/photos-enhanced.XXXXXX")
cleanup() {
    find "$build_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

dpkg-deb -R "$base_package" "$build_dir"
cp "$project_dir/Preferences/Resources/Root.plist" \
   "$build_dir/var/jb/Library/PreferenceBundles/PhotosRecentsSortPrefs.bundle/Root.plist"
cp "$cr3_dylib" \
   "$build_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/CR3PreviewCompat.dylib"
cp "$project_dir/CR3PreviewCompat/CR3PreviewCompat.plist" \
   "$build_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/CR3PreviewCompat.plist"

cat > "$build_dir/DEBIAN/control" <<'EOF'
Package: ayao.photosrecentssort
Name: Photos 增强
Version: 0.2.0
Architecture: iphoneos-arm64
Description: 照片 App 增强功能与 Canon CR3 内嵌 JPEG 预览兼容。
Maintainer: ayao
Author: ayao
Section: Tweaks
Depends: mobilesubstrate, preferenceloader, ellekit
Conflicts: ayao.cr3previewcompat
Replaces: ayao.cr3previewcompat
Provides: ayao.cr3previewcompat
EOF

dpkg-deb --build --root-owner-group "$build_dir" "$output_package"
echo "$output_package"
