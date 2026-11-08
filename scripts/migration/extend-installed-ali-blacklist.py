#!/usr/bin/env python3
"""Append live-verified Ali/Ant IDs under the user's existing authorization.

Never change an allowance, start an app, touch its sandbox, or probe processes.
"""
import datetime
import json
import pathlib
import plistlib
import shlex
import subprocess

ROOT = pathlib.Path('backups/restore12-to14pm-20261107')
SSH = ['ssh', '-S', '/tmp/14pm-ali-blacklist-20261107.sock', '-o', 'BatchMode=yes', '-T', 'placeholder']
CONFIG_DIR = '/var/mobile/Library/RootHide'
CONFIG = CONFIG_DIR + '/RootHideConfig.plist'
CHECKER = '/var/mobile/restore-tools/store-blacklist-check'
APPROVED = {'cn.damai.iphone', 'com.alicloud.smartdrive', 'com.alimama.moon',
            'com.alipay.iphoneclient', 'com.autonavi.amap', 'com.quark.browser',
            'com.taobao.etaocoupon', 'com.taobao.fleamarket', 'com.taobao.live',
            'com.taobao.taobao4iphone', 'com.taobao.tmall', 'com.wdk.hmxs'}


def remote(command, data=None):
    return subprocess.run(SSH + [command], input=data, capture_output=True,
                          check=True, timeout=30).stdout


def main():
    identity = remote('sysctl -n hw.machine; sw_vers; id -u').decode()
    if not all(v in identity for v in ['iPhone15,3', '16.3', '20D47']) or identity.splitlines()[-1] != '501':
        raise RuntimeError('Wrong device/user')
    audit = json.loads((ROOT / 'reports/native-store-sensitive-executable-audit.json').read_text())
    targets = {}
    for row in audit['rows']:
        if row['parent'] not in APPROVED:
            continue
        parent = row['parent']
        appinfo = remote('uicache -i ' + shlex.quote(parent)).decode().splitlines()
        apppath = next(line.split(': ', 1)[1] for line in appinfo if line.startswith('Path: '))
        rootpath = '/rootfs' + apppath
        if row['bundle_id'] == parent:
            paths = [rootpath + '/Info.plist']
        else:
            paths = remote('find ' + shlex.quote(rootpath) + ' -name Info.plist').decode().splitlines()
        found = False
        for path in paths:
            info = plistlib.loads(remote('cat ' + shlex.quote(path)))
            if info.get('CFBundleIdentifier') == row['bundle_id'] and info.get('CFBundleExecutable') == row['executable']:
                found = True
                break
        if not found:
            raise RuntimeError('Live bundle/executable metadata differs')
        targets[row['bundle_id']] = True
    originals = {name: remote('cat ' + CONFIG_DIR + '/' + name) for name in
                 ['cn.zqbb.inject.plist', 'cn.zqbb.inject.system.plist', 'cn.zqbb.inject.wantsblacklist.plist']}
    before = remote('cat ' + CONFIG)
    if not before.startswith(b'<?xml'):
        raise RuntimeError('Not native-compatible XML')
    previous = plistlib.loads(before)
    desired = {**previous, 'appconfig': {**previous['appconfig'], **targets}}
    added = {b: True for b in targets if previous['appconfig'].get(b) is not True}
    if not added:
        print('All live verified Ali IDs already blacklisted'); return
    metadata = remote('stat -c "%u:%g %a" ' + CONFIG).decode().strip()
    owner, mode = metadata.split()
    if owner != '501:501':
        raise RuntimeError('Original owner requires original privileged writer')
    timestamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    evidence = ROOT / 'target14pm' / ('ali-installed-extend-' + timestamp)
    evidence.mkdir(mode=0o700)
    device_backup = '/var/mobile/ali-installed-before-' + timestamp
    remote('umask 077; mkdir ' + device_backup)
    for name, data in {**originals, 'RootHideConfig.plist': before}.items():
        (evidence / name).write_bytes(data)
        remote('cat > ' + device_backup + '/' + name, data)
        if remote('cat ' + device_backup + '/' + name) != data:
            raise RuntimeError('Device backup mismatch')
    content = plistlib.dumps(desired, fmt=plistlib.FMT_XML, sort_keys=False)
    temporary = remote('mktemp ' + CONFIG_DIR + '/.ali-installed.XXXXXX').decode().strip()
    remote('cat > ' + shlex.quote(temporary), content)
    remote('chmod ' + mode + ' ' + shlex.quote(temporary))
    physical = remote('readlink -f ' + shlex.quote(temporary)).decode().strip().removeprefix('/rootfs')
    native = plistlib.loads(remote(CHECKER + ' inspect ' + shlex.quote(physical)))
    if native['appconfig'] != desired['appconfig']:
        raise RuntimeError('Native mutable dictionary differs')
    if remote('cat ' + CONFIG) != before or any(remote('cat ' + CONFIG_DIR + '/' + name) != data for name, data in originals.items()):
        raise RuntimeError('Concurrent policy edit; no replacement')
    remote('mv ' + shlex.quote(temporary) + ' ' + CONFIG)
    try:
        after = remote('cat ' + CONFIG)
        if after != content or remote('stat -c "%u:%g %a" ' + CONFIG).decode().strip() != metadata:
            raise RuntimeError('Published bytes or metadata differ')
        results = plistlib.loads(remote(CHECKER + ' query ' + shlex.join(list(desired['appconfig']) + ['com.example.piliplus', 'com.ownbook.notes'])))
        if any(results.get(b) is not True for b in desired['appconfig'] if desired['appconfig'][b] is True) or results['com.example.piliplus'] or results['com.ownbook.notes']:
            raise RuntimeError('Native service denied-state readback differs')
        if any(remote('cat ' + CONFIG_DIR + '/' + name) != data for name, data in originals.items()):
            raise RuntimeError('Concurrent allowance edits; do not claim preservation')
    except Exception:
        if remote('cat ' + CONFIG) == content:
            rollback = CONFIG_DIR + '/.ali-installed.rollback-' + timestamp
            remote('cat > ' + rollback, before)
            remote('chmod ' + mode + ' ' + rollback + '; mv ' + rollback + ' ' + CONFIG)
        raise
    (evidence / 'RootHideConfig.after.plist').write_bytes(after)
    report = {'observed_at': datetime.datetime.now().astimezone().isoformat(), 'added_ids': added,
              'appconfig_count': len(desired['appconfig']), 'metadata': metadata, 'xml': True,
              'native_class': native['native_dictionary_class'], 'native_service_readback': results,
              'allowance_bytes_unchanged': True, 'other_configuration_keys_unchanged': True,
              'device_backup': device_backup, 'Manager_UI_toggle_not_performed': True,
              'sensitive_app_launch_or_attachment_performed': False}
    (ROOT / 'reports/native-store-ali-extension-blacklist.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Added', len(added), 'verified Ali IDs; total', len(desired['appconfig']), 'service readback passed')


if __name__ == '__main__':
    main()
