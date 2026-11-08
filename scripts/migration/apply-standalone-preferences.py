#!/usr/bin/env python3
"""Apply explicitly inventoried tweak domains with CFPreferences and readback."""

import hashlib
import json
import pathlib
import plistlib
import shlex
import subprocess
import time

ROOT = pathlib.Path('backups/migration-14pm-to-mini-20261107')
SSH = ['ssh', '-S', '/tmp/migrate-target-20261107.sock', '-o', 'BatchMode=yes', '-T', 'placeholder']
TOOL = '/var/mobile/migration-tools/tweak-prefs'
BACKUP = '/var/mobile/migration-20261107-backup/preferences'


def remote(command, data=None, check=True):
    result = subprocess.run(SSH + [command], input=data, capture_output=True, timeout=25)
    if check and result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace')[-1000:])
    return result


def api(operation, domain, patch=None):
    command = f'_SafeMode=1 _MSSafeMode=1 {TOOL} {operation} {shlex.quote(domain)}'
    if patch:
        real = remote('readlink -f ' + shlex.quote(patch)).stdout.decode().strip()
        if not real.startswith('/rootfs/private/var/mobile/Containers/Shared/AppGroup/.jbroot-'):
            raise RuntimeError('Unexpected patch namespace')
        command += ' ' + shlex.quote(real.removeprefix('/rootfs'))
    return plistlib.loads(remote(command).stdout)


if __name__ == '__main__':
    if remote('/usr/sbin/sysctl -n hw.machine').stdout.strip() != b'iPhone13,1':
        raise SystemExit('Unexpected target')
    rows = json.loads((ROOT / 'reports/standalone-preferences-plan.json').read_text())
    remote('umask 077; mkdir -p ' + BACKUP)
    saved = ROOT / 'target/preference-backups'
    saved.mkdir(mode=0o700, exist_ok=True)
    report_path = ROOT / 'reports/preferences-applied.json'
    results = json.loads(report_path.read_text()) if report_path.exists() else []
    completed = {entry['domain'] for entry in results}
    for row in rows:
        domain, path = row['domain'], row['path']
        if domain in completed:
            continue
        desired = row['values'].copy()
        if domain == 'ayao.lockaudioprofiles':
            # Snapshots and command IDs are runtime state, not user settings.
            desired = {k: v for k, v in desired.items()
                       if not k.startswith('snapshot') and k not in
                       {'manualVolumeRequest', 'ringerMuteOwned', 'silenceSnapshotValid'}}
        before = api('read', domain)
        original = remote('cat ' + shlex.quote(path), check=False)
        metadata = None
        if original.returncode == 0:
            parsed = plistlib.loads(original.stdout)
            if parsed != before:
                raise RuntimeError('CFPreferences and disk disagree before mutation: ' + domain)
            metadata = remote('stat -c "%u:%g %a" ' + shlex.quote(path)).stdout.decode().strip()
            local_backup = saved / (domain + '.plist')
            absent_backup = remote('test -e ' + BACKUP + '/' + domain + '.absent', check=False).returncode == 0
            if not local_backup.exists() and not absent_backup:
                local_backup.write_bytes(original.stdout)
                remote('cp -p ' + shlex.quote(path) + ' ' + BACKUP + '/' + domain + '.plist')
                if remote('cat ' + BACKUP + '/' + domain + '.plist').stdout != original.stdout:
                    raise RuntimeError('Device backup differs')
        else:
            remote('test ! -e ' + shlex.quote(path))
            remote('touch ' + BACKUP + '/' + domain + '.absent')
        api_backup = saved / (domain + '.api-before.plist')
        if not api_backup.exists():
            api_backup.write_bytes(plistlib.dumps(before))
        patch = {'set': desired, 'remove': [k for k in before if k not in desired]}
        patch_path = '/var/mobile/migration-tools/' + domain + '.patch.plist'
        remote('cat > ' + patch_path, plistlib.dumps(patch))
        actual = before if before == desired else api('apply', domain, patch_path)
        if actual != desired:
            raise RuntimeError('API readback mismatch: ' + domain)
        for _ in range(20):
            disk = remote('cat ' + shlex.quote(path), check=False)
            if disk.returncode == 0 and plistlib.loads(disk.stdout) == desired:
                break
            time.sleep(1)
        else:
            raise RuntimeError('API did not persist matching values: ' + domain)
        # Preserve the target's existing format, or the source format for a new
        # domain. Re-encode only after the official API has persisted semantics.
        binary = original.stdout.startswith(b'bplist') if original.returncode == 0 else row['format'] == 'binary'
        if disk.stdout.startswith(b'bplist') != binary:
            content = plistlib.dumps(desired, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML)
            temp = path + '.migration-20261107.tmp'
            remote('cat > ' + temp, content)
            current = remote('stat -c "%u:%g %a" ' + shlex.quote(path)).stdout.decode().split()
            # The API-created file supplies ownership; do not hard-code it.
            owner, mode = current if metadata is None else metadata.split()
            uid, gid = owner.split(':')
            remote('chmod ' + mode + ' ' + temp + '; mv ' + temp + ' ' + shlex.quote(path))
        final = remote('cat ' + shlex.quote(path)).stdout
        if plistlib.loads(final) != desired or api('read', domain) != desired:
            raise RuntimeError('Final semantic mismatch: ' + domain)
        (ROOT / 'target' / (domain + '.after.plist')).write_bytes(final)
        results.append({'domain': domain, 'saved_keys': len(desired), 'api_and_disk_equal': True,
                        'sha256': hashlib.sha256(final).hexdigest(),
                        'format': 'binary' if final.startswith(b'bplist') else 'xml',
                        'excluded_runtime_keys': sorted(set(row['values']) - set(desired)),
                        'original_present': original.returncode == 0})
        (ROOT / 'reports/preferences-applied.json').write_text(json.dumps(results, indent=2) + '\n')
        print('Preferences persisted and verified:', domain, len(desired), flush=True)
