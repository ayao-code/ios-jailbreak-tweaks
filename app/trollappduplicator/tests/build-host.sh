#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$1
mkdir -p "$build"
# Use exactly the same packager and bundled ZIP implementation as the iOS app.
for file in "$root"/thirdparty/SSZipArchive/minizip/*.c "$root"/thirdparty/SSZipArchive/minizip/aes/*.c "$root/MachOInspector.c" "$root/GroupMigration.c"; do
  case "$file" in */mztools.c) continue;; esac
  clang -c -O1 -I"$root" "$file" -o "$build/$(basename "$file").o"
done
clang -fobjc-arc -fblocks -DCLONE_HOST_TEST=1 -Wno-deprecated-declarations -I"$root" \
  "$root/tests/host_runner.m" "$root/AppDuplicator.m" "$root/ClonePolicy.m" \
  "$root/thirdparty/SSZipArchive/SSZipArchive.m" "$build"/*.o \
  -framework Foundation -lz -o "$build/runner"
clang -fobjc-arc -fblocks -DCLONE_HOST_TEST=1 -Wno-deprecated-declarations -I"$root" \
  "$root/tests/upstream_runner.m" "$root/AppDuplicator.m" "$root/ClonePolicy.m" \
  "$root/thirdparty/SSZipArchive/SSZipArchive.m" "$build"/*.o \
  -framework Foundation -lz -o "$build/upstream-runner"
