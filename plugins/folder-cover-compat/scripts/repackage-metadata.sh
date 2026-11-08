#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
baseline="$project/packages/ayao.foldercovercompat_0.1.3_iphoneos-arm64e.deb"
version=$(sed -n 's/^Version: //p' "$project/control")
output="$project/packages/ayao.foldercovercompat_${version}_iphoneos-arm64e.deb"
test -f "$baseline"
test "$output" != "$baseline"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM
dpkg-deb -R "$baseline" "$stage"
cp "$project/control" "$stage/DEBIAN/control"
dpkg-deb --build --root-owner-group "$stage" "$output"
python3 - "$baseline" "$output" <<'PY'
import hashlib
import pathlib
import subprocess
import sys
import tempfile

def manifest(root):
    result = {}
    for path in pathlib.Path(root).rglob('*'):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            result[relative] = ('link', str(path.readlink()))
        elif path.is_file():
            result[relative] = ('file', path.stat().st_mode & 0o777,
                                hashlib.sha256(path.read_bytes()).hexdigest())
    return result

with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
    subprocess.run(['dpkg-deb', '-x', sys.argv[1], before], check=True)
    subprocess.run(['dpkg-deb', '-x', sys.argv[2], after], check=True)
    if manifest(before) != manifest(after):
        raise SystemExit('Refuse package: installed payload differs from verified baseline')
print('Metadata-only package: library/filter bytes and payload permissions unchanged.')
PY
