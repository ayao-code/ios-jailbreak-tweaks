#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT INT TERM
clang -Wall -Wextra -Werror -I"$project" "$project/checks/geometry.c" -o "$output/geometry"
"$output/geometry"
clang -fno-objc-arc -fblocks -O1 -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics \
    "$project/checks/callbacks.m" -o "$output/callbacks"
"$output/callbacks"
plutil -lint "$project/zzFolderCoverCompat.plist"
printf '%s\n' 'Geometry, production callback fixture and filter syntax passed; not device validation.'
