#!/bin/bash
set -euo pipefail
project=$(cd "$(dirname "$0")" && pwd)
output=${1:?usage: build.sh OUTPUT_DIRECTORY}
version=${PROBE_VERSION:-0.1.0~test16}
[[ "$version" =~ ^[0-9][A-Za-z0-9.+~:-]*$ ]] || { echo "Invalid PROBE_VERSION" >&2; exit 2; }
theos=${THEOS:-"$HOME/theos"}
sdk=$theos/sdks/iPhoneOS16.5.sdk
mkdir -p "$output"
mkdir -p "$project/../../packages"
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
  -Wall -Wextra -Werror -framework Foundation "$project/client.m" \
  -o "$output/vpn-adapter-native-probe"
ldid -S"$project/../background-entitlements.plist" "$output/vpn-adapter-native-probe"
codehash=$(ldid -h "$output/vpn-adapter-native-probe" 2>&1 | sed -n 's/^CDHash=//p')
python3 - "$codehash" "$output/caller-codehash.h" <<'PY'
import sys
from pathlib import Path
raw=bytes.fromhex(sys.argv[1])
assert len(raw)==20
Path(sys.argv[2]).write_text('static const unsigned char AdapterExpectedCodeHash[20] = {'+', '.join(hex(value) for value in raw)+'};\n')
PY
xcrun clang -target arm64-apple-ios16.0 -isysroot "$sdk" -fobjc-arc -O2 \
  -Wall -Wextra -Werror -framework Foundation -include "$output/caller-codehash.h" \
  "$project/authorize.m" -o "$output/vpn-adapter-authorize"
ldid -S"$project/../background-entitlements.plist" "$output/vpn-adapter-authorize"
for arch in arm64 arm64e; do
  xcrun clang -target "$arch-apple-ios16.0" -isysroot "$sdk" -fobjc-arc -O2 \
    -Wall -Wextra -Werror -Wno-deprecated-declarations -dynamiclib \
    -framework Foundation -framework UIKit -framework NetworkExtension \
    -Wl,-install_name,@rpath/VPNAdapterProbe.dylib \
    -DADAPTER_HELPER_BUILD=1 -include "$output/caller-codehash.h" \
    "$project/helper.m" -o "$output/probe-$arch.dylib"
done
xcrun lipo -create "$output/probe-arm64.dylib" "$output/probe-arm64e.dylib" \
  -output "$output/VPNAdapterProbe.dylib"
ldid -S "$output/VPNAdapterProbe.dylib"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
mkdir -p "$stage/DEBIAN" "$stage/Library/MobileSubstrate/DynamicLibraries"
cp "$project/control" "$stage/DEBIAN/control"
python3 - "$stage/DEBIAN/control" "$version" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text('\n'.join('Version: ' + sys.argv[2] if line.startswith('Version: ')
                          else line for line in path.read_text().splitlines()) + '\n')
PY
cp "$output/VPNAdapterProbe.dylib" "$project/VPNAdapterProbe.plist" \
  "$stage/Library/MobileSubstrate/DynamicLibraries/"
dpkg-deb --build --root-owner-group "$stage" \
  "$project/../../packages/ayao.vpnadapterprobe_${version}_iphoneos-arm64e.deb"
