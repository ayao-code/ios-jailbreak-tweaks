#!/bin/bash
set -euo pipefail

tool_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$tool_dir/../.." && pwd)
build_dir=$(mktemp -d "$project_dir/build/roothide-helper-package.XXXXXX")
app_dir="$build_dir/Payload/RootHideUIHelper.app"
archive="$project_dir/build/RootHideUIHelper-1.0.0.ipa"

SDP_ROOTHIDE_UI=1 bash "$tool_dir/build.sh" >/dev/null
bash "$tool_dir/../screen-observe/build.sh" display >/dev/null

mkdir -p "$app_dir"
cp "$project_dir/build/ui-input" "$app_dir/ui-input-roothide"
cp "$project_dir/build/screen-observe-display" "$app_dir/screen-observe-display"
cp "$tool_dir/roothide-helper-info.plist" "$app_dir/Info.plist"
plutil -lint "$app_dir/Info.plist"
rm -f "$archive"
(cd "$build_dir" && zip -qry "$archive" Payload)
printf '%s\n' "$archive"
