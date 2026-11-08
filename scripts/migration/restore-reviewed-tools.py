#!/usr/bin/env python3
import os
"""Restore reviewed tool installers with target-policy and logged status guards."""

import datetime
import getpass
import hashlib
import json
import pathlib
import plistlib
import shlex
import subprocess

ROOT = pathlib.Path('backups/restore12-to14pm-20261107')
ASSETS = pathlib.Path(os.environ["MIGRATION_ASSETS_DIR"])
DEPENDENCIES = pathlib.Path('backups/migration-14pm-to-mini-20261107/packages/dependencies')
SSH = ['ssh', '-S', '/tmp/14pm-mode-reconnect.sock', '-o', 'BatchMode=yes', '-T', 'placeholder']
POLICY = '/var/mobile/Library/RootHide/cn.zqbb.inject.plist'


def main():
    password = getpass.getpass('Target sudo password: ')

    def remote(command, data=None, root=False, timeout=45):
        if root:
            if data is not None:
                raise ValueError('Payload and credential stdin must remain separate')
            command = 'sudo -S -p "" /bin/sh -c ' + shlex.quote(command)
            data = (password + '\n').encode()
        result = subprocess.run(SSH + [command], input=data, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError((result.stdout + result.stderr).decode(errors='replace')[-1600:])
        return result.stdout

    def identity():
        output = remote('/usr/sbin/sysctl -n hw.machine; /usr/bin/sw_vers').decode().splitlines()
        values = dict(line.split(':', 1) for line in output if ':' in line)
        if output[0] != 'iPhone15,3' or values.get('BuildVersion', '').strip() != '20D47':
            raise RuntimeError('Unexpected restore target')

    identity()
    policy = remote('cat ' + POLICY)
    if plistlib.loads(policy) != {'Runner': True, 'netdisk_iPhone': False}:
        raise RuntimeError('Concurrent policy change; inspect before restoring')
    timestamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    backup = '/var/mobile/restore-tools-install-' + timestamp
    remote('umask 077; mkdir ' + backup + '; mkdir ' + backup + '/installers; '
           'cp -p ' + POLICY + ' ' + backup + '/policy.before; '
           'cp -p /var/lib/dpkg/status ' + backup + '/status.before')
    dependencies = []
    for pattern in ['roothide.patches.filza*.deb', 'gzip_*.deb', 'zip_*.deb', 'unzip_*.deb',
                    'xz-utils_*.deb', 'p7zip_*.deb', 'unrar_*.deb']:
        matches = list(DEPENDENCIES.glob(pattern))
        if len(matches) != 1:
            raise RuntimeError('Ambiguous reviewed dependency')
        dependencies.append(matches[0])
    tools = [
        ASSETS / 'jailbreak/cached-original-debs/58f12e1212d3-byg.iosios.net.hudapp.jb_1.12.0_iphoneos-arm64e.deb',
        ASSETS / 'jailbreak/packages/com.tigisoftware.filza64bit_4.0.1-4~roothide_iphoneos-arm64e.deb',
        ASSETS / 'jailbreak/cached-original-debs/github.poqw312.icleanerpro_7.10.0k_iphoneos-arm64e.repository-recovered.deb',
    ]
    records = []
    destinations = {}
    for path in dependencies + tools:
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        metadata = subprocess.run(['dpkg-deb', '-f', str(path), 'Package', 'Version'],
                                  capture_output=True, text=True, check=True).stdout
        values = dict(line.split(':', 1) for line in metadata.splitlines() if ':' in line)
        package, version = values['Package'].strip(), values['Version'].strip()
        destination = backup + '/installers/' + path.name
        remote('cat > ' + shlex.quote(destination), data=data)
        if remote('sha256sum ' + shlex.quote(destination)).decode().split()[0] != digest:
            raise RuntimeError('Installer upload checksum mismatch')
        records.append({'package': package, 'version': version, 'sha256': digest,
                        'source': str(path), 'installed': False})
        destinations[package] = destination
    report = {'device_backup': backup, 'records': records, 'injection_policy_unchanged': True,
              'icleaner_cleaning_executed': False, 'complete': False}
    report_path = ROOT / 'reports/tool-installation.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    batches = [[r['package'] for r in records[:len(dependencies)]],
               [r['package'] for r in records[len(dependencies):]]]
    for index, packages in enumerate(batches):
        identity()
        if remote('cat ' + POLICY) != policy:
            raise RuntimeError('Policy changed before install; stop')
        command = ('PATH=/usr/bin:/usr/sbin:/bin:/sbin:/rootfs/usr/bin:/rootfs/bin; export PATH; '
                   'dpkg --dry-run --install ' + shlex.join([destinations[p] for p in packages]))
        remote(command, root=True, timeout=90)
        log = backup + '/batch-' + str(index)
        command = command.replace('--dry-run --install', '--install')
        command += (' > ' + log + '.log 2>&1; rc=$?; echo "$rc" > ' + log +
                    '.exit; cat ' + log + '.log; exit "$rc"')
        print('Installing reviewed tools batch:', index, packages, flush=True)
        output = remote(command, root=True, timeout=180)
        (ROOT / 'target14pm' / ('tools-batch-' + str(index) + '.log')).write_bytes(output)
        if remote('cat ' + POLICY) != policy:
            raise RuntimeError('Policy changed after installation')
        status = remote('cat /var/lib/dpkg/status').decode()
        installed = {}
        for para in status.split('\n\n'):
            values = dict(line.split(':', 1) for line in para.splitlines()
                          if ':' in line and not line.startswith(' '))
            if values.get('Status', '').strip() == 'install ok installed':
                installed[values['Package'].strip()] = values['Version'].strip()
        for row in records:
            if row['package'] in packages:
                if installed.get(row['package']) != row['version']:
                    raise RuntimeError('Package not fully installed or wrong version')
                row['installed'] = True
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print('Installed version and unchanged injection policy verified', flush=True)
    report['complete'] = True
    report['service_runtime_and_ui_validation'] = 'pending'
    report_path.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
