#!/usr/bin/env python3
"""Reconcile only IconOrder's live layout using its native preferences client."""

import datetime
import json
import pathlib
import plistlib
import shlex
import subprocess

ROOT = pathlib.Path('backups/migration-14pm-to-mini-20261107')
SSH = ['ssh', '-S', '/tmp/migrate-target-20261107.sock', '-o', 'BatchMode=yes', '-T', 'placeholder']
TOOL = '/var/mobile/migration-tools/tweak-prefs'
DOMAIN = 'com.ichitaso.iconorder'
PATH = '/var/mobile/Library/Preferences/' + DOMAIN + '.plist'


def remote(command, data=None):
    result = subprocess.run(SSH + [command], input=data, capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace')[-1000:])
    return result.stdout


def native(operation, patch=None):
    command = f'_SafeMode=1 _MSSafeMode=1 {TOOL} {operation} {DOMAIN}'
    if patch:
        command += ' ' + shlex.quote(patch)
    return plistlib.loads(remote(command))


if __name__ == '__main__':
    identity = remote('/usr/sbin/sysctl -n hw.machine; /usr/bin/sw_vers').decode()
    if 'iPhone13,1' not in identity or '20D67' not in identity:
        raise SystemExit('Unexpected target')
    raw = remote('cat ' + PATH)
    old = native('iconorder-disk-read')
    metadata = remote('stat -c "%u:%g %a" ' + PATH).decode().strip()
    timestamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    backup = '/var/mobile/migration-20261107-backup/iconorder-reconcile-' + timestamp + '.plist'
    remote('cp -p ' + PATH + ' ' + backup)
    if remote('cat ' + backup) != raw:
        raise RuntimeError('Backup mismatch')
    (ROOT / 'target' / ('iconorder-reconcile-before-' + timestamp + '.plist')).write_bytes(raw)
    real = '/rootfs/var/mobile/Library/SpringBoard/IconState.plist'
    system_raw = remote('cat ' + real)
    (ROOT / 'target' / ('desktop-reconcile-before-' + timestamp + '.plist')).write_bytes(system_raw)
    remote('cp -p ' + real + ' ' + real + '.reconcile-before-' + timestamp)
    layout = plistlib.load((ROOT / 'reports/desktop-current-reconcile-candidate.plist').open('rb'))
    desired = {**old, 'IconOrder': layout}
    patch = '/var/mobile/migration-tools/iconorder-reconcile.patch.plist'
    remote('cat > ' + patch, plistlib.dumps({'set': {'IconOrder': layout}, 'remove': []},
                                        fmt=plistlib.FMT_BINARY))
    real_patch = remote('readlink -f ' + patch).decode().strip()
    if not real_patch.startswith('/rootfs/private/var/mobile/Containers/Shared/AppGroup/.jbroot-'):
        raise RuntimeError('Unexpected patch namespace')
    actual = native('apply', real_patch.removeprefix('/rootfs'))
    if actual != desired:
        raise RuntimeError('API readback mismatch')
    if raw.startswith(b'<?xml'):
        actual = native('iconorder-xml')
    else:
        actual = native('iconorder-disk-read')
    if actual != desired:
        raise RuntimeError('Consumer disk readback mismatch')
    after = remote('cat ' + PATH)
    current_metadata = remote('stat -c "%u:%g %a" ' + PATH).decode().strip()
    if raw.startswith(b'bplist') != after.startswith(b'bplist'):
        raise RuntimeError('Format changed')
    if current_metadata != metadata:
        raise RuntimeError('Metadata changed')
    (ROOT / 'target/iconorder-current-reconcile-after.plist').write_bytes(after)
    report_path = ROOT / 'reports/desktop-current-reconcile-plan.json'
    report = json.loads(report_path.read_text())
    report.update(preferences_applied=True, api_and_native_consumer_disk_equal=True,
                  original_format_preserved=True, other_keys_unchanged=True,
                  device_backup=backup, metadata=metadata, runtime_reload_pending=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('Native layout preference and consumer readback verified; runtime reload pending')
