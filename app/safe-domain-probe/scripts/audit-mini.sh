#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
mux=${SSH_CONTROL_SOCKET:?Set SSH_CONTROL_SOCKET to an existing authorized 12 mini SSH master}
if [ ! -S "$mux" ]; then
    printf 'existing_ssh_master_unavailable\n' >&2
    exit 1
fi
ssh_options=(-S "$mux" -o BatchMode=yes -o ConnectTimeout=8 -T)
model=$(ssh "${ssh_options[@]}" placeholder 'sysctl -n hw.machine')
if [ "$model" != iPhone13,1 ]; then
    printf 'target_is_not_iphone_12_mini; stopping_without_writes\n' >&2
    exit 1
fi
bash "$project_dir/scripts/build.sh" audit
temporary_dir=$(mktemp -d "$project_dir/build/filter-audit.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
mkdir "$temporary_dir/filters"
ssh "${ssh_options[@]}" placeholder \
    'cd /var/jb/usr/lib/TweakInject && tar -cf - -- *.plist' \
    | /usr/bin/python3 -c '
import sys, tarfile
from pathlib import Path
destination = Path(sys.argv[1])
archive = tarfile.open(fileobj=sys.stdin.buffer, mode="r|*")
count = 0
for entry in archive:
    if not entry.isfile() or "/" in entry.name or "\\" in entry.name or not entry.name.endswith(".plist"):
        raise SystemExit("unexpected_filter_archive_entry")
    if entry.size > 1024 * 1024 or count >= 2000:
        raise SystemExit("filter_archive_limit_exceeded")
    (destination / entry.name).write_bytes(archive.extractfile(entry).read())
    count += 1
if count == 0:
    raise SystemExit("empty_filter_inventory")
' "$temporary_dir/filters"
"$project_dir/build/audit-filters" "$temporary_dir/filters" \
    > "$project_dir/build/mini-filter-audit.json"
/usr/bin/python3 - "$project_dir/build/mini-filter-audit.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(json.dumps({'target_model': 'iPhone13,1', 'counts': report['counts'],
    'runtime_injection': report['runtime_injection'],
    'protected_app_isolation': report['protected_app_isolation']}, indent=2))
PY
