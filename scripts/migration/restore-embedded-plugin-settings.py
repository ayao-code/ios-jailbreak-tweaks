#!/usr/bin/env python3
"""Native container-specific settings restore using exact reviewed keys.

No injection policy writes, app starts/stops, account/license transfer, or
global-cache resets. Backups include existing files solely for rollback.
"""
import argparse
import datetime
import json
import pathlib
import plistlib
import re
import shlex
import subprocess
import time

ROOT=pathlib.Path('backups/restore12-to14pm-20261107')
TOOL='/var/mobile/restore-tools/embedded-plugin-prefs'
POLICY='/var/mobile/Library/RootHide/'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--socket',required=True)
    args=parser.parse_args()
    ssh=['ssh','-S',args.socket,'-o','BatchMode=yes','-T','placeholder']
    def remote(cmd,data=None):
        return subprocess.run(ssh+[cmd],input=data,capture_output=True,check=True,timeout=30).stdout
    def native(op,domain,container,patch=None):
        argv=[op,domain,container]
        if patch:argv.append(patch)
        return plistlib.loads(remote(TOOL+' '+shlex.join(argv)))
    def check_identity():
        value=remote('sysctl -n hw.machine; sw_vers; id -u').decode()
        if not all(v in value for v in ['iPhone15,3','16.3','20D47']) or value.splitlines()[-1]!='501':
            raise RuntimeError('Wrong target/user')
    check_identity()
    helper_path=remote('readlink -f '+TOOL).decode().strip()
    root_match=re.fullmatch(r'(/rootfs/private/var/mobile/Containers/Shared/AppGroup/\.jbroot-[0-9A-Fa-f]{16})/var/mobile/restore-tools/embedded-plugin-prefs',helper_path)
    if not root_match:raise RuntimeError('Unexpected live helper root')
    current_root=root_match.group(1)
    if remote('readlink -f '+POLICY+'cn.zqbb.inject.plist').decode().strip()!=current_root+'/var/mobile/Library/RootHide/cn.zqbb.inject.plist':
        raise RuntimeError('Live helper/policy roots differ')
    plan=json.loads((ROOT/'reports/current12-embedded-plugin-settings.json').read_text())
    policies={name:remote('cat '+POLICY+name) for name in ['cn.zqbb.inject.plist','cn.zqbb.inject.system.plist','cn.zqbb.inject.wantsblacklist.plist','RootHideConfig.plist']}
    stamp=datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
    local=ROOT/'target14pm'/('embedded-plugin-before-'+stamp);local.mkdir(mode=0o700)
    backup='/var/mobile/embedded-plugin-before-'+stamp
    remote('umask 077; mkdir '+backup)
    for name,data in policies.items():
        (local/name).write_bytes(data);remote('cat > '+backup+'/'+name,data)
        if remote('cat '+backup+'/'+name)!=data:raise RuntimeError('Policy backup mismatch')
    result=[]
    for row in plan:
        domain,app=row['domain'],row['source_app']
        if app not in ['com.tencent.xin','com.ss.iphone.ugc.Aweme']:raise RuntimeError('Forbidden app')
        package=['com.25mao.doutu.rootless','com.25mao.miyou.rootless','com.dumpapp.wechat-rootless'] if app=='com.tencent.xin' else ['byg.iosios.net.dyyy']
        for p in package:
            status=remote('dpkg-query -s '+shlex.quote(p)).decode()
            if 'Status: install ok installed' not in status:raise RuntimeError('Required plugin not installed')
        appinfo=remote('uicache -i '+shlex.quote(app)).decode().splitlines()
        container=next(x.split(': ',1)[1] for x in appinfo if x.startswith('Data Container Path: '))
        if not container.startswith('/private/var/mobile/Containers/Data/Application/'):raise RuntimeError('Unexpected container')
        path='/rootfs'+container+'/Library/Preferences/'+domain+'.plist'
        remote('test ! -L '+shlex.quote(path))
        raw=remote('cat '+shlex.quote(path));before=plistlib.loads(raw)
        if not raw.startswith(b'bplist'):raise RuntimeError('Original format requires separate native serializer review')
        meta=remote('stat -c "%u:%g %a" '+shlex.quote(path)).decode().strip()
        source=pathlib.Path(row['file']);values=plistlib.loads(source.read_bytes())
        if set(values)!=set(row['key_names']) or len(values)!=row['saved_key_count']:raise RuntimeError('Manifest differs')
        if values.get('intelligentSocialShareEntitlementEnabled') is True:raise RuntimeError('No entitlement activation transfer')
        keys=set(values);selected={k:v for k,v in before.items() if k in keys}
        if native('read',domain,container)!=selected:raise RuntimeError('Plugin native API/disk mismatch')
        # Preserve all existing native and non-reviewed plugin keys, including
        # those absent in source; absence does not mean false or deletion.
        desired={**before,**values}
        saved=backup+'/'+domain+'.plist'
        remote('cat > '+saved,raw)
        if remote('cat '+saved)!=raw:raise RuntimeError('Device backup mismatch')
        (local/(domain+'.before.plist')).write_bytes(raw)
        (local/(domain+'.metadata.txt')).write_text(meta+'\n')
        patch='/var/mobile/restore-tools/embedded-'+domain+'-'+stamp+'.plist'
        remote('umask 077; cat > '+shlex.quote(patch),plistlib.dumps({'set':values},fmt=plistlib.FMT_BINARY))
        physical=remote('readlink -f '+patch).decode().strip()
        if not physical.startswith(current_root+'/var/mobile/restore-tools/'):
            raise RuntimeError('Unexpected patch namespace')
        check_identity()
        if remote('cat '+shlex.quote(path))!=raw or any(remote('cat '+POLICY+n)!=v for n,v in policies.items()):
            raise RuntimeError('Concurrent app/policy change; not written')
        applied=native('apply',domain,container,physical.removeprefix('/rootfs'))
        if applied!=values:raise RuntimeError('Native plugin API readback differs')
        for attempt in range(20):
            after=remote('cat '+shlex.quote(path));disk=plistlib.loads(after)
            if all(k in disk and disk[k]==v for k,v in values.items()):break
            time.sleep(.5)
        else:raise RuntimeError('Plugin values not persisted; no blind retry')
        changed=[k for k in set(before)|set(disk) if k not in keys and (k not in before or k not in disk or before[k]!=disk[k])]
        if changed:raise RuntimeError('Concurrent/non-target keys changed; stop without overwriting user state: '+','.join(changed))
        if disk!=desired or not after.startswith(b'bplist') or remote('stat -c "%u:%g %a" '+shlex.quote(path)).decode().strip()!=meta:
            raise RuntimeError('Disk contents/format/metadata differ')
        if native('read',domain,container)!=values:raise RuntimeError('Fresh native API differs')
        if any(remote('cat '+POLICY+n)!=v for n,v in policies.items()):raise RuntimeError('Concurrent policy edits')
        (local/(domain+'.after.plist')).write_bytes(after)
        entry={'domain':domain,'app':app,'source_snapshot':str(source),'source_snapshot_collected_at':'2026-11-07 10:07 +08:00',
               'source_keys':len(values),'already_equal_keys':sum(k in before and before[k]==v for k,v in values.items()),
               'restored_keys':sum(k not in before or before[k]!=v for k,v in values.items()),
               'native_api_and_disk_equal':True,'all_non_target_keys_preserved':True,
               'original_binary_format_and_metadata_preserved':True,'metadata':meta,
               'target_container':container,'device_backup':saved,'injection_policy_bytes_unchanged':True,
               'app_account_chat_or_license_restored':False,'app_runtime_functionality_not_verified':True}
        result.append(entry)
        (ROOT/'reports/embedded-plugin-settings-restored.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        print(domain,len(values),'source keys verified; changed',entry['restored_keys'],'non-target preserved',flush=True)
        remote('rm -- '+shlex.quote(patch))
    print('All',sum(r['source_keys'] for r in result),'reviewed plugin settings persisted; no allowance edits')


if __name__=='__main__':main()
