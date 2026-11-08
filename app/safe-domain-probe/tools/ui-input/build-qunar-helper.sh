#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
build_dir=$(mktemp -d "$project_dir/build/qunar-helper-package.XXXXXX")
app_dir="$build_dir/Payload/QunarUIHelper.app"
archive="$project_dir/build/QunarUIHelper-1.0.0.ipa"

if [ -e "$archive" ]; then
    printf 'refusing to overwrite existing archive: %s\n' "$archive" >&2
    exit 1
fi

SDP_QUNAR_TEST_UI=1 bash "$tool_dir/build.sh" >/dev/null
bash "$tool_dir/../screen-observe/build.sh" display >/dev/null

mkdir -p "$app_dir"
cp "$project_dir/build/ui-input" "$app_dir/ui-input-qunar"
cp "$project_dir/build/screen-observe-display" "$app_dir/screen-observe-display"
cp "$tool_dir/qunar-helper-info.plist" "$app_dir/Info.plist"
plutil -lint "$app_dir/Info.plist"
(cd "$build_dir" && zip -qry "$archive" Payload)
printf '%s\n' "$archive"
