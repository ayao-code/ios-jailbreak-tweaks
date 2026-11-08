#!/usr/bin/env python3
"""Package the tool only; do not install or process any third-party application."""
from pathlib import Path
import json
import hashlib
import plistlib
import sys
import subprocess
import zipfile

app = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[1]
info = plistlib.loads((app / 'Info.plist').read_bytes())
variant = sys.argv[2] if len(sys.argv) > 2 else ''
stem = 'CloneStudio'
if variant == 'upstream':
    info['CFBundleIdentifier'] = 'com.ayao.clonestudio.upstream'
    info['CFBundleDisplayName'] = '分身工坊·原版实验'
    info['CFBundleVersion'] = '0.1.0-upstream3'
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    entitlements = plistlib.loads((root / 'entitlements.plist').read_bytes())
    entitlements['application-identifier'] = info['CFBundleIdentifier']
    variant_entitlements = root / 'build/upstream-tool-entitlements.plist'
    variant_entitlements.parent.mkdir(exist_ok=True)
    variant_entitlements.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML))
    subprocess.run(['ldid', '-S' + str(variant_entitlements),
                    str(app / info['CFBundleExecutable'])], check=True)
    stem = 'CloneStudio-Upstream'
else:
    assert info['CFBundleIdentifier'] == 'com.ayao.clonestudio'
out = root / 'build' / (stem + '-' + info['CFBundleVersion'] + '.tipa')
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(app.rglob('*')):
        if p.is_file():
            z.write(p, Path('Payload') / app.name / p.relative_to(app))
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
(root / 'build' / ('latest-upstream-package.json' if variant == 'upstream' else 'latest-package.json')).write_text(json.dumps({
    'path': str(out), 'sha256': hashlib.sha256(out.read_bytes()).hexdigest(),
    'bytes': out.stat().st_size, 'installed': False,
}, indent=2) + '\n')
print(out)
