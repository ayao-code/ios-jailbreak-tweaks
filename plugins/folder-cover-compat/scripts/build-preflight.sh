#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$project/.build/preflight"
sdk=${THEOS:-"$HOME/theos"}/sdks/iPhoneOS16.5.sdk
mkdir -p "$out"
xcrun clang -target arm64e-apple-ios16.3 -isysroot "$sdk" \
    -fno-objc-arc -fblocks -O1 -Wall -Wextra -Werror \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$project/checks/initializer.m" -o "$out/cover-preflight"
ldid -S"$project/../../scripts/tools/crane-healthcheck/entitlements.plist" "$out/cover-preflight"
for stub in PrimalFolder2 BoldersReborn; do
    xcrun clang -target arm64e-apple-ios16.3 -isysroot "$sdk" -dynamiclib \
        "$project/checks/stub.c" -o "$out/$stub.dylib"
done
python3 - "$out" <<'PY'
from pathlib import Path
import sys, struct, uuid
out = Path(sys.argv[1])
values = {'PrimalFolder2': '00000000-0000-0000-0000-000000000000',
          'BoldersReborn': '00000000-0000-0000-0000-000000000000'}
for name, value in values.items():
    path = out / (name + '.dylib'); data = bytearray(path.read_bytes()); offset = 32
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        cmd, size = struct.unpack_from('<II', data, offset)
        if cmd == 0x1b:
            data[offset + 8:offset + 24] = uuid.UUID(value).bytes
            break
        offset += size
    else:
        raise RuntimeError('no UUID load command')
    path.write_bytes(data)
PY
ldid -S "$out/PrimalFolder2.dylib"
ldid -S "$out/BoldersReborn.dylib"
cp "$project/.build/zzFolderCoverCompat.dylib" "$out/zzFolderCoverCompat.dylib"
