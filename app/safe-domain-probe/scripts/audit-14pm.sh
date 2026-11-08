#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
mux=${SSH_CONTROL_SOCKET:?Set SSH_CONTROL_SOCKET to an existing authorized 14PM SSH master}
if [ ! -S "$mux" ]; then
    printf 'existing_ssh_master_unavailable\n' >&2
    exit 1
fi

/usr/bin/python3 - "$mux" "$project_dir/build" <<'PY'
import datetime
import hashlib
import io
import json
import plistlib
import re
import subprocess
import sys
import tarfile
from pathlib import Path

socket_path, output_directory = sys.argv[1:]
ssh = ['ssh', '-S', socket_path, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-T', 'placeholder']
remote_path = 'PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/usr/sbin:/bin:/sbin; export PATH; '

def read_remote(command):
    result = subprocess.run(ssh + [remote_path + command], capture_output=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError('read_only_remote_command_failed_' + str(result.returncode))
    return result.stdout

def decode_plist(data):
    try:
        return plistlib.loads(data)
    except plistlib.InvalidFileException:
        result = subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', '--', '-'],
                                input=data, capture_output=True, timeout=10)
        if result.returncode != 0:
            raise ValueError('invalid_property_list')
        return json.loads(result.stdout)

def metadata_members(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
        entries = archive.getmembers()
        if len(entries) > 2000:
            raise ValueError('metadata_entry_limit_exceeded')
        for entry in entries:
            if entry.size > 1024 * 1024 or entry.name.startswith('/') or '..' in Path(entry.name).parts:
                raise ValueError('metadata_entry_not_allowed')
            yield entry, archive.extractfile(entry).read() if entry.isfile() else None

model = read_remote('sysctl -n hw.machine').decode().strip()
if model != 'iPhone15,3':
    raise SystemExit('target_is_not_14_pro_max; no_device_writes')
system_version = decode_plist(read_remote('cat /System/Library/CoreServices/SystemVersion.plist'))
preferences_path = '/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist'
raw_preferences = read_remote('cat ' + preferences_path)
preferences = decode_plist(raw_preferences)
signing_hash = read_remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
main_bundle = 'com.taobao.taobao4iphone'
apps = preferences.get('appSettings', {})
main_settings = apps.get(main_bundle, {})
filters = []
unparsed = []
nonregular = []
filter_archive = read_remote('cd /var/jb/usr/lib/TweakInject && tar -cf - -- *.plist')
for entry, data in metadata_members(filter_archive):
    if '/' in entry.name or not entry.name.endswith('.plist'):
        raise ValueError('unexpected_filter_entry')
    if data is None:
        nonregular.append({'file': entry.name, 'kind': 'symlink' if entry.issym() else 'other',
                           'contents': 'not_followed_or_parsed'})
        continue
    try:
        dictionary = decode_plist(data)
        declaration = dictionary.get('Filter')
        if not isinstance(declaration, dict):
            raise ValueError('missing_filter')
    except (ValueError, AttributeError):
        unparsed.append(entry.name)
        continue
    bundles = declaration.get('Bundles', [])
    executables = declaration.get('Executables', [])
    if not isinstance(bundles, list) or not isinstance(executables, list):
        unparsed.append(entry.name)
        continue
    filters.append({'file': entry.name, 'bundle_targets': bundles, 'executable_targets': executables})
metadata_archive = read_remote('setopt nullglob; for bundle in /var/containers/Bundle/Application/*/Taobao4iPhone.app; do '
                               'cd "$bundle" && tar -cf - -- Info.plist PlugIns/*/Info.plist; break; done')
metadata = []
for entry, data in metadata_members(metadata_archive):
    if data is None or not entry.name.endswith('/Info.plist') and entry.name != 'Info.plist':
        raise ValueError('unexpected_app_metadata_entry')
    dictionary = decode_plist(data)
    metadata.append({'bundle_id': dictionary.get('CFBundleIdentifier'),
                     'version': dictionary.get('CFBundleShortVersionString'),
                     'executable': dictionary.get('CFBundleExecutable'),
                     'is_main': entry.name == 'Info.plist',
                     'extension_point': dictionary.get('NSExtension', {}).get('NSExtensionPointIdentifier'),
                     'explicit_choicy_settings': apps.get(dictionary.get('CFBundleIdentifier'))})
crane_raw = read_remote('cat /var/jb/var/mobile/Library/Preferences/com.opa334.craneprefs.plist')
crane = decode_plist(crane_raw).get('appSettings_' + main_bundle, {})
crane_summary = {'entry_present': bool(crane), 'active_container_setting_nonempty': bool(crane.get('activeContainer')),
                 'container_count': len(crane.get('Containers', [])),
                 'boolean_settings': {key: value for key, value in crane.items() if isinstance(value, bool)},
                 'container_names_and_identifiers': 'not_recorded'}
jobs = read_remote('launchctl list').decode().splitlines()
taobao_jobs = []
for line in jobs:
    if 'UIKitApplication:' + main_bundle + '[' in line:
        fields = line.split()
        taobao_jobs.append({'pid': fields[0], 'last_exit': fields[1]})
environment_keys = ['DYLD_INSERT_LIBRARIES', 'JBROOT', 'JB_ROOT_PATH', 'JB_SANDBOX_EXTENSIONS',
                    'JBRAND', '_SafeMode', '_MSSafeMode', 'CRANE_CONTAINER_IDENTIFIER']
for job in taobao_jobs:
    if not job['pid'].isdigit():
        continue
    domain = read_remote('launchctl print pid/' + job['pid']).decode()
    job['launchctl_environment_presence'] = {key: bool(re.search(r'(?m)^\s*' + re.escape(key) + r'\s*=>', domain))
                                            for key in environment_keys}
    job['current_dyld_images'] = 'not_enumerated'
after_preferences = read_remote('cat ' + preferences_path)
after_crane = read_remote('cat /var/jb/var/mobile/Library/Preferences/com.opa334.craneprefs.plist')
after_signing_hash = read_remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
services = {'securityd', 'containermanagerd', 'cfprefsd', 'pkd', 'lsd', 'accountsd', 'apsd', 'backboardd'}
selected_filters = [item for item in filters if main_bundle in item['bundle_targets']
                    or services.intersection(item['executable_targets'])
                    or item['file'].strip() in ('Crane.plist', 'Choicy.plist')]
allowed = main_settings.get('allowedTweaks', [])
installed_names = {Path(item['file']).stem for item in filters}
report = {'schema_version': 1, 'collected_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'target_model': model,
          'os_version': {key: system_version.get(key) for key in ('ProductVersion', 'ProductBuildVersion')},
          'basebin_version': read_remote('cat /var/jb/basebin/.version').decode().strip(),
          'mode': 'read_only_no_device_files_written',
          'taobao_bundle_metadata': metadata,
          'choicy_main_settings': main_settings,
          'choicy_configuration_sha256': hashlib.sha256(raw_preferences).hexdigest(),
          'choicy_configuration_unchanged_during_collection': raw_preferences == after_preferences,
          'crane_configuration_unchanged_during_collection': crane_raw == after_crane,
          'systemhook_sha256': signing_hash,
          'systemhook_unchanged_during_collection': signing_hash == after_signing_hash,
          'allowed_names_without_same_named_regular_filter': [name for name in allowed if name not in installed_names],
          'crane_target_configuration_shape': crane_summary,
          'static_filter_counts': {'parsed': len(filters), 'unparsed': len(unparsed), 'nonregular': len(nonregular)},
          'unparsed_filters': unparsed, 'nonregular_filters': nonregular,
          'selected_filter_declarations': selected_filters,
          'taobao_launchd_jobs': taobao_jobs,
          'taobao_rejection_cause': 'not_proven', 'safe_isolated_ios_environment': 'not_implemented',
          'limits': ['Configuration and Filter declarations do not prove current loaded images or business rejection cause.',
                     'No debug attachment, hooks, injected code or sensitive-app container reads are used.',
                     'Existing Crane containers may change behavior if target injection is disabled.',
                     'Missing explicit extension settings do not by themselves prove unprotected extension execution.']}
destination = Path(output_directory)
destination.mkdir(parents=True, exist_ok=True)
output_path = destination / '14pm-baseline.json'
output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ('target_model', 'os_version', 'basebin_version',
    'static_filter_counts', 'allowed_names_without_same_named_regular_filter',
    'choicy_configuration_unchanged_during_collection', 'crane_configuration_unchanged_during_collection',
    'systemhook_unchanged_during_collection', 'taobao_rejection_cause')}, ensure_ascii=False, indent=2))
PY
