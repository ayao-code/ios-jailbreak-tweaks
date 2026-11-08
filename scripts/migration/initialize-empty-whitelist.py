#!/usr/bin/env python3
"""Explicit first-run initialization only; never enable an app or replace policy."""

import argparse
import datetime
import hashlib
import io
import json
import pathlib
import plistlib
import shlex
import subprocess
import tarfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--socket', required=True)
    parser.add_argument('--evidence-dir', type=pathlib.Path, required=True)
    args = parser.parse_args()
    ssh = ['ssh', '-S', args.socket, '-o', 'BatchMode=yes', '-T', 'placeholder']
    root = '/var/mobile/Library/RootHide'
    active = root + '/cn.zqbb.inject.plist'
    backup_policy = active + '.bak'

    def remote(command, data=None):
        result = subprocess.run(ssh + [command], input=data, capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace')[-1000:])
        return result.stdout

    def identity():
        output = remote('/usr/sbin/sysctl -n hw.machine; /usr/bin/sw_vers; id -u').decode()
        lines = output.splitlines()
        values = dict(line.split(':', 1) for line in lines if ':' in line)
        if (lines[0] != 'iPhone15,3' or lines[-1] != '501' or
                values.get('ProductVersion', '').strip() != '16.3' or
                values.get('BuildVersion', '').strip() != '20D47'):
            raise RuntimeError('Unexpected target identity')

    identity()
    remote('test -d ' + root + '; test ! -L ' + root + '; test -w ' + root +
           '; test ! -e ' + active + '; test ! -L ' + active +
           '; test ! -e ' + backup_policy + '; test ! -L ' + backup_policy)
    timestamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    evidence = args.evidence_dir / ('whitelist-init-' + timestamp)
    evidence.mkdir(mode=0o700, parents=True)
    device_backup = '/var/mobile/restore-policy-before-' + timestamp
    before_tar = remote('tar -cf - -C ' + root + ' .')
    (evidence / 'before.tar').write_bytes(before_tar)
    before = {}
    with tarfile.open(fileobj=io.BytesIO(before_tar)) as archive:
        for member in archive:
            if member.isfile():
                before[member.name.removeprefix('./')] = archive.extractfile(member).read()
    if 'cn.zqbb.inject.system.plist' not in before:
        raise RuntimeError('Missing native system defaults')
    plistlib.loads(before['cn.zqbb.inject.system.plist'])
    remote('umask 077; mkdir ' + device_backup + '; cp -pR ' + root + ' ' +
           device_backup + '/RootHide; touch ' + device_backup + '/active-and-bak.absent')
    for name, content in before.items():
        if remote('cat ' + shlex.quote(device_backup + '/RootHide/' + name)) != content:
            raise RuntimeError('Device backup differs')

    content = plistlib.dumps({}, fmt=plistlib.FMT_XML)
    digest = hashlib.sha256(content).hexdigest()
    (evidence / 'desired-empty.plist').write_bytes(content)
    # Match runtime configuration ownership/mode observed on the native files.
    native_metadata = remote('stat -c "%u:%g %a" ' + root + '/cn.zqbb.inject.system.plist').decode().strip()
    if native_metadata != '501:501 755':
        raise RuntimeError('Unexpected native file metadata')
    temporary = remote('mktemp ' + root + '/.empty-whitelist.XXXXXX').decode().strip()
    if not temporary.startswith(root + '/.empty-whitelist.'):
        raise RuntimeError('Unexpected temporary path')
    remote('cat > ' + shlex.quote(temporary), content)
    if remote('sha256sum ' + shlex.quote(temporary)).decode().split()[0] != digest:
        raise RuntimeError('Uploaded content mismatch')
    identity()
    remote('set -e; test ! -e ' + active + '; test ! -L ' + active +
           '; test ! -e ' + backup_policy + '; chmod 755 ' + shlex.quote(temporary) +
           '; mv ' + shlex.quote(temporary) + ' ' + active)
    actual = remote('cat ' + active)
    if actual != content or plistlib.loads(actual) != {}:
        raise RuntimeError('Official path readback differs')
    metadata = remote('stat -c "%u:%g %a" ' + active).decode().strip()
    if metadata != native_metadata:
        raise RuntimeError('Official path metadata differs')
    for name, original in before.items():
        if remote('cat ' + shlex.quote(root + '/' + name)) != original:
            raise RuntimeError('Non-target configuration changed')
    remote('test ! -e ' + backup_policy)
    (evidence / 'after.plist').write_bytes(actual)
    report = {
        'target': 'iPhone15,3 / 16.3 / 20D47',
        'user_explicitly_authorized_first_run_initialization': True,
        'active_path': active, 'user_entries': {}, 'ordinary_app_injection_enabled': False,
        'format': 'xml', 'metadata': metadata, 'sha256': digest,
        'device_backup': device_backup, 'existing_configs_byte_unchanged': True,
        'system_defaults_unchanged': True, 'source12_allowlist_not_copied': True,
        'consumer_mode_contract': 'Current systemhook selects whitelist behavior when active plist exists',
        'mode_contract_and_persisted_state_verified': True,
        'manager_ui_and_process_image_verification': 'not performed',
    }
    (evidence / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (args.evidence_dir / 'whitelist-initialization-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    # Official foreground app refresh request, no switch or app allowance.
    remote('uiopen --bundleid cn.zqbb.inject.manager')


if __name__ == '__main__':
    main()
