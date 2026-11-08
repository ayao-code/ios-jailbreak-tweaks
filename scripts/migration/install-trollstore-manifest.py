#!/usr/bin/env python3
"""Install an explicit verified IPA manifest through the target TrollStore helper."""

import argparse
import getpass
import hashlib
import json
import pathlib
import plistlib
import shlex
import subprocess
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--socket', required=True)
    parser.add_argument('--manifest', type=pathlib.Path, required=True)
    parser.add_argument('--asset-root', type=pathlib.Path, required=True)
    parser.add_argument('--report', type=pathlib.Path, required=True)
    parser.add_argument('--only')
    parser.add_argument('--product-type', default='iPhone13,1')
    parser.add_argument('--ios-version', default='16.3.1')
    parser.add_argument('--build-version', default='20D67')
    args = parser.parse_args()
    password = getpass.getpass('Target sudo password: ')
    ssh = ['ssh', '-S', args.socket, '-o', 'BatchMode=yes', '-T', 'placeholder']

    def remote(command, *, root=False, data=None, timeout=180, accepted=(0,)):
        if root:
            if data is not None:
                raise ValueError('Do not mix sudo credentials with payload stdin')
            command = 'sudo -S -p "" /bin/sh -c ' + shlex.quote(command)
            data = (password + '\n').encode()
        result = subprocess.run(ssh + [command], input=data, capture_output=True,
                                timeout=timeout)
        if result.returncode not in accepted:
            raise RuntimeError(result.stderr.decode(errors='replace')[-2000:])
        return result.stdout

    def identity():
        values = remote('/usr/sbin/sysctl -n hw.machine; /usr/bin/sw_vers').decode()
        lines = values.splitlines()
        actual = {'product': lines[0].strip() if lines else ''}
        actual.update({k.strip(): v.strip() for line in lines[1:] if ':' in line
                       for k, v in [line.split(':', 1)]})
        if (actual.get('product') != args.product_type or
                actual.get('ProductVersion') != args.ios_version or
                actual.get('BuildVersion') != args.build_version):
            raise RuntimeError('Unexpected target device')

    identity()
    rows = json.loads(args.manifest.read_text())
    if args.only:
        rows = [row for row in rows if row['bundle_id'] == args.only]
        if len(rows) != 1:
            raise RuntimeError('Selected bundle is absent or ambiguous')
    forbidden = {'com.opa334.TrollStore', 'com.opa334.Dopamine-roothide',
                 'cn.zqbb.dopaRH', 'com.opa334.Dopamine', 'cn.zqbb.inject.manager'}
    if len({r['bundle_id'] for r in rows}) != len(rows):
        raise RuntimeError('Duplicate bundle in manifest')
    apps = remote('uicache -l').decode()
    helpers = [line.split(' : ', 1)[1] for line in apps.splitlines()
               if line.startswith('com.opa334.TrollStore : ')]
    if len(helpers) != 1:
        raise RuntimeError('Expected exactly one existing TrollStore')
    helper = '/rootfs' + helpers[0] + '/trollstorehelper'
    remote('test -x ' + shlex.quote(helper))
    # SSH runs in the jbroot namespace, whereas TrollStore's helper executes
    # in the real system namespace. Stage in shared media and pass its real path.
    staging = '/rootfs/var/mobile/Media/migration-20261107-ipas'
    remote('umask 077; mkdir -p ' + staging)
    records = json.loads(args.report.read_text()) if args.report.exists() else []
    completed = {r['bundle_id'] for r in records if r.get('installed')}

    for row in rows:
        bundle = row['bundle_id']
        if bundle in forbidden:
            raise RuntimeError('Refusing a jailbreak/system application')
        if bundle in completed:
            # A persisted report does not prove that an app still exists.
            current = remote('uicache -l').decode()
            matches = [line.split(' : ', 1)[1] for line in current.splitlines()
                       if line.startswith(bundle + ' : ')]
            if len(matches) != 1:
                raise RuntimeError('Previously verified app no longer registered: ' + bundle)
            info = plistlib.loads(remote('cat ' + shlex.quote('/rootfs' + matches[0] + '/Info.plist')))
            if info.get('CFBundleShortVersionString', info.get('CFBundleVersion')) != row['version']:
                raise RuntimeError('Previously verified app version changed: ' + bundle)
            print('Already verified:', bundle, flush=True)
            continue
        ipa = (args.asset_root / row['file']).resolve()
        if not ipa.is_relative_to(args.asset_root.resolve()):
            raise RuntimeError('Asset path escaped root')
        with ipa.open('rb') as file:
            digest = hashlib.file_digest(file, 'sha256').hexdigest()
        if digest != row['sha256']:
            raise RuntimeError('IPA hash mismatch')
        with zipfile.ZipFile(ipa) as archive:
            names = [n for n in archive.namelist()
                     if n.startswith('Payload/') and n.count('/') == 2
                     and n.endswith('.app/Info.plist')]
            if len(names) != 1:
                raise RuntimeError('Ambiguous main app')
            info = plistlib.loads(archive.read(names[0]))
            if info['CFBundleIdentifier'] != bundle:
                raise RuntimeError('Bundle ID mismatch')
            if archive.testzip() is not None:
                raise RuntimeError('IPA CRC error')
        identity()
        current = remote('uicache -l').decode()
        if any(line.startswith(bundle + ' : ') for line in current.splitlines()):
            raise RuntimeError('Existing app needs a separate backup/update review: ' + bundle)
        destination = staging + '/' + bundle + '.ipa'
        print('Uploading:', bundle, ipa.stat().st_size, flush=True)
        with ipa.open('rb') as file:
            result = subprocess.run(ssh + ['cat > ' + shlex.quote(destination)],
                                    stdin=file, capture_output=True, timeout=240)
        if result.returncode:
            raise RuntimeError('Upload failed')
        actual = remote('sha256sum ' + shlex.quote(destination)).decode().split()[0]
        if actual != digest:
            raise RuntimeError('Uploaded hash mismatch')
        helper_destination = destination.removeprefix('/rootfs')
        # Upstream installApp returns 184 after successful installation when
        # a secondary binary remains encrypted. Preserve it and report the
        # limitation instead of deleting extensions or retrying blindly.
        output = remote(shlex.quote(helper) + ' install ' + shlex.quote(helper_destination),
                        root=True, accepted=(0, 184))
        current = remote('uicache -l').decode()
        matches = [line.split(' : ', 1)[1] for line in current.splitlines()
                   if line.startswith(bundle + ' : ')]
        if len(matches) != 1:
            raise RuntimeError('Installation not registered')
        actual_info = plistlib.loads(remote('cat ' + shlex.quote('/rootfs' + matches[0] + '/Info.plist')))
        if any(actual_info.get(k) != info.get(k) for k in
               ['CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString']):
            raise RuntimeError('Installed version mismatch')
        records.append({'bundle_id': bundle, 'version': row['version'],
                        'build': info.get('CFBundleVersion'), 'sha256': digest,
                        'installed': True, 'registered_path': matches[0],
                        'version_readback_equal': True,
                        'encrypted_extensions_possible': bundle in {
                            'com.xunlei.mvideo', 'com.feng.New.WPForumClient',
                            'com.zhihu.ios', 'com.baidu.netdisk', 'com.jindk.ZipMaster'},
                        'helper_output': output.decode(errors='replace')[-300:]})
        temp = args.report.with_suffix('.json.tmp')
        temp.write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')
        temp.replace(args.report)
        remote('rm -- ' + shlex.quote(destination))
        print('Installed and version verified:', bundle, flush=True)


if __name__ == '__main__':
    main()
