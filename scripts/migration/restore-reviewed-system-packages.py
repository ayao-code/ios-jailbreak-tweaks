#!/usr/bin/env python3
"""Restore the explicit system-only batch without changing app injection policy."""

import datetime
import getpass
import hashlib
import json
import pathlib
import plistlib
import shlex
import subprocess

ROOT = pathlib.Path('backups/restore12-to14pm-20261107')
SSH = ['ssh', '-S', '/tmp/14pm-mode-reconnect.sock', '-o', 'BatchMode=yes', '-T', 'placeholder']
POLICY = '/var/mobile/Library/RootHide/cn.zqbb.inject.plist'


def main():
    password = getpass.getpass('Target sudo password: ')

    def remote(command, *, data=None, root=False, timeout=40):
        if root:
            if data is not None:
                raise ValueError('Credential stdin must not contain file data')
            command = 'sudo -S -p "" /bin/sh -c ' + shlex.quote(command)
            data = (password + '\n').encode()
        result = subprocess.run(SSH + [command], input=data, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError((result.stdout + result.stderr).decode(errors='replace')[-1800:])
        return result.stdout

    def identity():
        values = remote('/usr/sbin/sysctl -n hw.machine; /usr/bin/sw_vers').decode().splitlines()
        pairs = dict(line.split(':', 1) for line in values if ':' in line)
        if (values[0] != 'iPhone15,3' or pairs.get('ProductVersion', '').strip() != '16.3' or
                pairs.get('BuildVersion', '').strip() != '20D47'):
            raise RuntimeError('Wrong restore target')

    identity()
    policy = remote('cat ' + POLICY)
    if plistlib.loads(policy) != {'Runner': True, 'netdisk_iPhone': False}:
        raise RuntimeError('Injection policy changed; reassess system-only scope')
    remote('test ! -e /var/jb; test ! -e /usr/lib/TweakInject; '
           'test ! -e /Library/MobileSubstrate/DynamicLibraries')
    plans = json.loads((ROOT / 'reports/system-only-reviewed-packages.json').read_text())
    system_scope = {r['package'] for r in json.loads((ROOT / 'reports/system-only-install.json').read_text())}
    dependencies = {'ellekit', 'preferenceloader', 'com.roothide.patchloader',
                    'rootless-compat', 'ws.hbang.alderis'}
    if {r['package'] for r in plans} != system_scope | dependencies:
        raise RuntimeError('Unexpected package scope')
    stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    backup = '/var/mobile/restore-system-batch-' + stamp
    remote('umask 077; mkdir ' + backup + '; mkdir ' + backup + '/packages; '
           'cp -p ' + POLICY + ' ' + backup + '/policy.before; '
           'cp -p /var/lib/dpkg/status ' + backup + '/dpkg-status.before')
    (ROOT / 'target14pm' / ('policy-before-system-' + stamp + '.plist')).write_bytes(policy)
    (ROOT / 'target14pm' / ('status-before-system-' + stamp + '.txt')).write_bytes(remote('cat /var/lib/dpkg/status'))
    report = {'device_backup': backup, 'packages': [], 'policy_not_modified': True,
              'complete': False, 'app_plugins_and_global_filters_not_in_batch': True}
    (ROOT / 'reports/system-batch-live.json').write_text(json.dumps(report, indent=2) + '\n')
    files = {}
    for row in plans:
        path = pathlib.Path(row['installer'])
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != row['sha256']:
            raise RuntimeError('Installer hash changed')
        destination = backup + '/packages/' + path.name
        remote('cat > ' + shlex.quote(destination), data=content)
        if remote('sha256sum ' + shlex.quote(destination)).decode().split()[0] != row['sha256']:
            raise RuntimeError('Uploaded installer hash changed')
        files[row['package']] = destination
    for name, selected in [('dependencies', [r for r in plans if r['package'] in dependencies]),
                           ('system-tweaks', [r for r in plans if r['package'] in system_scope])]:
        identity()
        if remote('cat ' + POLICY) != policy:
            raise RuntimeError('Concurrent injection policy edit; stop')
        command = ('PATH=/usr/bin:/usr/sbin:/bin:/sbin:/rootfs/usr/bin:/rootfs/bin; export PATH; '
                   'dpkg --install ' + shlex.join([files[r['package']] for r in selected]) +
                   ' > ' + backup + '/' + name + '.log 2>&1; rc=$?; echo "$rc" > ' +
                   backup + '/' + name + '.exit; cat ' + backup + '/' + name + '.log; exit "$rc"')
        print('Installing reviewed batch:', name, len(selected), flush=True)
        output = remote(command, root=True, timeout=180)
        (ROOT / 'target14pm' / (name + '-install.log')).write_bytes(output)
        if remote('cat ' + POLICY) != policy:
            raise RuntimeError('Injection policy changed; stop further installation')
        status = remote('cat /var/lib/dpkg/status').decode()
        installed = {}
        for para in status.split('\n\n'):
            values = dict(line.split(':', 1) for line in para.splitlines()
                          if ':' in line and not line.startswith(' '))
            if values.get('Status', '').strip() == 'install ok installed':
                installed[values['Package'].strip()] = values.get('Version', '').strip()
        for row in selected:
            if installed.get(row['package']) != row['version']:
                raise RuntimeError('Installed package status/version mismatch')
            report['packages'].append({'package': row['package'], 'version': row['version'],
                                       'installed_version_readback': True})
        (ROOT / 'reports/system-batch-live.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Version and policy readback verified:', name, flush=True)
    report['complete'] = True
    report['runtime_functionality_verified'] = False
    (ROOT / 'reports/system-batch-live.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
