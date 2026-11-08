#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
build_dir=$(mktemp -d "$project_dir/build/damai-helper-package.XXXXXX")
app_dir="$build_dir/Payload/DamaiUIHelper.app"
archive="$project_dir/build/DamaiUIHelper-1.0.1.ipa"

SDP_DAMAI_TEST_UI=1 bash "$tool_dir/build.sh" >/dev/null
bash "$tool_dir/../screen-observe/build.sh" display >/dev/null

mkdir -p "$app_dir"
cp "$project_dir/build/ui-input" "$app_dir/ui-input-damai"
cp "$project_dir/build/screen-observe-display" "$app_dir/screen-observe-display"
cp "$tool_dir/damai-helper-info.plist" "$app_dir/Info.plist"
plutil -lint "$app_dir/Info.plist"
rm -f "$archive"
(cd "$build_dir" && zip -qry "$archive" Payload)
printf '%s\n' "$archive"
