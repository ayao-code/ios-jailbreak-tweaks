import datetime
import hashlib
import io
import json
import os
import pathlib
import plistlib
import re
import shlex
import subprocess
import tarfile


project = pathlib.Path(__file__).resolve().parent.parent
socket_path = os.environ.get('SSH_CONTROL_SOCKET')
if not socket_path:
    raise SystemExit('existing_authorized_ssh_control_socket_required')
ssh = ['ssh', '-S', socket_path, '-o', 'BatchMode=yes', '-T', 'placeholder']
master = subprocess.run(ssh[:-2] + ['-O', 'check', 'placeholder'], capture_output=True, timeout=10)
if master.returncode:
    raise SystemExit('existing_ssh_master_unavailable_no_device_evidence')
prefix = 'PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/usr/sbin:/bin:/sbin; export PATH; '


def remote(command, timeout=30):
    result = subprocess.run(ssh + [prefix + command], capture_output=True, timeout=timeout)
    if result.returncode:
        raise SystemExit('read_only_remote_command_failed_' + str(result.returncode))
    return result.stdout


def read_configurations():
    return {name: remote('cat /var/jb/var/mobile/Library/Preferences/' + name)
            for name in ['com.opa334.choicyprefs.plist', 'com.opa334.craneprefs.plist']}


def selected_jobs():
    result = {}
    for line in remote('launchctl list').decode().splitlines():
        fields = line.split()
        if len(fields) != 3:
            continue
        label = fields[2]
        if label in ['com.apple.SpringBoard', 'com.apple.accountsd']:
            result[label] = fields[0]
        elif label.startswith('UIKitApplication:com.taobao.taobao4iphone['):
            result['taobao'] = fields[0]
    return result


def configuration_changes(before, after):
    result = {}
    for name in before:
        original = plistlib.loads(before[name])
        current = plistlib.loads(after[name])
        if original == current:
            result[name] = {'semantics_unchanged': True, 'target_unchanged': True}
            continue
        key = 'appSettings_com.taobao.taobao4iphone'
        if name == 'com.opa334.choicyprefs.plist':
            target_unchanged = original.get('appSettings', {}).get('com.taobao.taobao4iphone') == \
                current.get('appSettings', {}).get('com.taobao.taobao4iphone')
        else:
            target_unchanged = original.get(key) == current.get(key)
        result[name] = {'semantics_unchanged': False, 'target_unchanged': target_unchanged,
                        'non_target_difference_present': target_unchanged}
    return result


if remote('sysctl -n hw.machine').decode().strip() != 'iPhone15,3':
    raise SystemExit('unexpected_device_no_inventory_written')
before = read_configurations()
jobs_before = selected_jobs()
systemhook_before = remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
settings = plistlib.loads(before['com.opa334.craneprefs.plist'])['appSettings_com.taobao.taobao4iphone']
containers = settings['Containers']
identifiers = [item['identifier'] for item in containers]
if len(identifiers) != 4 or len(set(identifiers)) != 4 or identifiers.count('DEFAULT') != 1:
    raise SystemExit('unexpected_container_configuration_stop')
if settings.get('containerProtectionEnabled') is not True:
    raise SystemExit('container_protection_setting_changed_stop')
if any(identifier != 'DEFAULT' and not re.fullmatch(r'[A-Fa-f0-9-]{36}', identifier)
       for identifier in identifiers):
    raise SystemExit('container_identifier_path_not_allowed')
metadata_archive = remote('setopt nullglob; cd /var/mobile/Containers/Data/Application && '
                          'tar -cf - -- */.com.apple.mobile_container_manager.metadata.plist')
if len(metadata_archive) > 16 * 1024 * 1024:
    raise SystemExit('metadata_archive_limit_exceeded')
roots = []
with tarfile.open(fileobj=io.BytesIO(metadata_archive)) as archive:
    members = archive.getmembers()
    if len(members) > 2000:
        raise SystemExit('metadata_member_limit_exceeded')
    for member in members:
        if not member.isfile() or member.size > 1024 * 1024 or not re.fullmatch(
                r'[A-Fa-f0-9-]{36}/\.com\.apple\.mobile_container_manager\.metadata\.plist', member.name):
            raise SystemExit('unexpected_metadata_archive_member')
        metadata = plistlib.loads(archive.extractfile(member).read())
        if metadata.get('MCMMetadataIdentifier') == 'com.taobao.taobao4iphone':
            roots.append('/var/mobile/Containers/Data/Application/' + member.name.split('/')[0])
if len(roots) != 1:
    raise SystemExit('target_data_root_not_unique')
root = roots[0]
paths = [root] + [root + '/Library/___Crane_Containers/' + identifier
                  for identifier in identifiers if identifier != 'DEFAULT']
storage = []
for index, path in enumerate(paths):
    quoted = shlex.quote(path)
    value = remote('if [ -d ' + quoted + ' ] && [ ! -L ' + quoted + ' ]; then du -sk ' + quoted +
                   '; else printf "missing_or_symlink\\n"; fi', timeout=60).decode().strip()
    present = value != 'missing_or_symlink'
    storage.append({'kind': 'default_root_includes_nested_containers' if index == 0 else 'nondefault_container',
                    'directory_present': present,
                    'allocated_kib': int(value.split()[0]) if present else None})
available = int(remote('df -Pk /var/mobile').decode().splitlines()[-1].split()[3])
configuration_backup = {'local_bytes_match_at_start': False, 'device_bytes_match_at_start': False,
                        'covers_container_data': False}
pointer = project / 'build' / 'latest-config-backup.json'
if pointer.exists():
    backup = pathlib.Path(json.loads(pointer.read_text())['directory']).resolve()
    if backup.parent != (project / 'build').resolve() or not backup.name.startswith('config-backup-'):
        raise SystemExit('unexpected_local_configuration_backup_pointer')
    manifest = json.loads((backup / 'manifest.json').read_text())
    device_backup = manifest['device_directory']
    if not re.fullmatch(r'/var/jb/tmp/safe-domain-config-backup\.[A-Za-z0-9]+', device_backup):
        raise SystemExit('unexpected_device_configuration_backup_pointer')
    configuration_backup['local_bytes_match_at_start'] = all((backup / name).read_bytes() == data
                                                             for name, data in before.items())
    configuration_backup['device_bytes_match_at_start'] = all(remote('cat ' + shlex.quote(device_backup + '/' + name)) == data
                                                              for name, data in before.items())
after = read_configurations()
jobs_after = selected_jobs()
systemhook_after = remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
unchanged = before == after and systemhook_before == systemhook_after
report = {
    'collected_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'model': 'iPhone15,3',
    'mode': 'read_only_metadata_and_allocated_size_no_account_content',
    'configured_container_count': len(containers),
    'active_container_is_default': settings['activeContainer'] == 'DEFAULT',
    'container_protection_setting_enabled': True,
    'protection_hook_effectiveness_without_injection': 'not_proven',
    'storage': storage,
    'storage_is_transactional_snapshot': False,
    'device_available_kib': available,
    'host_available_bytes': os.statvfs(project / 'build').f_bavail * os.statvfs(project / 'build').f_frsize,
    'configuration_backup': configuration_backup,
    'container_data_backup_verified': False,
    'configuration_and_systemhook_bytes_unchanged': unchanged,
    'configuration_semantic_comparison': configuration_changes(before, after),
    'configuration_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in after.items()},
    'selected_jobs_before': jobs_before,
    'selected_jobs_after': jobs_after,
    'selected_jobs_unchanged_during_inventory': jobs_before == jobs_after,
    'data_paths_container_identifiers_and_account_values': 'not_recorded',
    'container_switch_or_application_launch_performed': False,
    'clean_isolated_ios_environment': 'not_proven',
}
output = project / 'build' / '14pm-container-storage-inventory.json'
output.write_text(json.dumps(report, indent=2) + '\n')
output.chmod(0o600)
if not unchanged:
    raise SystemExit('concurrent_configuration_or_systemhook_change_stop')
if jobs_before != jobs_after:
    raise SystemExit('selected_process_changed_during_inventory_stop')
print('read_only_inventory_saved_configuration_unchanged_no_container_data_backup')
